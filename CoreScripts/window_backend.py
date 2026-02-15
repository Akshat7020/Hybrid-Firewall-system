from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
import time, hmac, hashlib, os, json, io, zipfile

APP_DIR = os.path.dirname(os.path.abspath(__file__))
PARENT_DIR = os.path.dirname(APP_DIR)
STATIC_DIR = os.path.join(PARENT_DIR, "static")

app = Flask(__name__, static_folder=STATIC_DIR, static_url_path="/static")
CORS(app)

DATA_FILE = "firewall_agents.json"
SECRET_KEY = os.urandom(32)  # For signing (per-agent secret is better, but simplified)

def load_data():
    if os.path.exists(DATA_FILE):
        try:
            with open(DATA_FILE, "r") as f:
                return json.load(f)
        except:
            return {}
    return {}

def save_data(data):
    with open(DATA_FILE, "w") as f:
        json.dump(data, f, indent=2)

users = load_data()  # user_id → { "agents": {agent_id: {...}}, "token": "hexstr" }

# Cleanup any users with no agents (safe to call on startup)
def cleanup_empty_users():
    removed = []
    for uid in list(users.keys()):
        if uid == 'admin':
            continue
        if not users[uid].get('agents'):
            del users[uid]
            removed.append(uid)
    if removed:
        save_data(users)
        print(f"🧹 Removed empty users on startup: {removed}")

# Run cleanup once on startup
cleanup_empty_users()


def ensure_user_token(user_id):
    # Create a token for a user if it does not exist and return it
    if user_id not in users:
        token = os.urandom(16).hex()
        users[user_id] = {"agents": {}, "token": token}
        save_data(users)
        return token
    if "token" not in users[user_id] or not users[user_id]["token"]:
        users[user_id]["token"] = os.urandom(16).hex()
        save_data(users)
    return users[user_id]["token"]

@app.route("/api/user/init", methods=["POST"])
def user_init():
    d = request.json or {}
    user_id = d.get("user_id")
    if not user_id:
        return jsonify({"error": "missing user_id"}), 400
    token = ensure_user_token(user_id)
    return jsonify({"token": token})


@app.route("/", methods=["GET"])
def index():
    """Serve the main UI"""
    index_path = os.path.join(STATIC_DIR, "index.html")
    if os.path.exists(index_path):
        with open(index_path, "r") as f:
            return f.read()
    return jsonify({"error": "index.html not found"}), 404


def sign(secret, payload):
    return hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()

# ---------------- REGISTER ----------------
@app.route("/api/agent/register", methods=["POST"])
def register():
    d = request.get_json(silent=True) or {}

    user_id = d.get("user_id")
    agent_id = d.get("agent_id")
    os_type = d.get("os_type", "windows")

    if not user_id or not agent_id:
        return jsonify({"error": "missing user_id or agent_id"}), 400

    # Ensure user structure is correct
    if user_id not in users:
        users[user_id] = {
            "agents": {},
            "token": os.urandom(16).hex()
        }

    if agent_id not in users[user_id]["agents"]:
        secret = os.urandom(16).hex()
        users[user_id]["agents"][agent_id] = {
            "os": os_type,
            "firewall": "INACTIVE",
            "connected": False,
            "last_heartbeat": None,
            "last_toggle": None,
            "pending_cmd": None,
            "secret": secret
        }
        save_data(users)
        print(f"✅ New agent registered: {user_id}/{agent_id}")

    return jsonify({"ok": True})


# ---------------- HEARTBEAT ----------------
@app.route("/api/agent/heartbeat", methods=["POST"])
def heartbeat():
    d = request.get_json(silent=True) or {}

    user_id = d.get("user_id")
    agent_id = d.get("agent_id")
    firewall = d.get("firewall")

    if not user_id or not agent_id:
        return jsonify({"error": "missing user_id or agent_id"}), 400

    agent = users.get(user_id, {}).get("agents", {}).get(agent_id)
    if not agent:
        return jsonify({"error": "unknown agent"}), 404

    if firewall in ("ACTIVE", "INACTIVE"):
        agent["firewall"] = firewall

    agent["connected"] = True
    agent["last_heartbeat"] = time.time()

    save_data(users)
    return jsonify({"ok": True})


# ---------------- LIST USER AGENTS ----------------
@app.route("/api/user/agents", methods=["GET"])
def user_agents():
    user_id = request.args.get("user_id")
    token = request.args.get("token")
    if not user_id or not token:
        return jsonify({"error": "missing credentials"}), 400
    stored_token = users.get(user_id, {}).get("token")
    if not stored_token or stored_token != token:
        return jsonify({"error": "unauthorized"}), 403
    agents = users.get(user_id, {}).get("agents", {})
    result = []
    for aid, a in agents.items():
        result.append({
            "agent_id": aid,
            "os": a["os"],
            "connected": a.get("connected", False),
            "firewall": a.get("firewall", "UNKNOWN"),
            "last_heartbeat": a.get("last_heartbeat"),
            "last_toggle": a.get("last_toggle"),
            "last_actor": a.get("last_actor")
        })
    return jsonify(result)

# ---------------- SEND COMMAND (ACTIVATE / DEACTIVATE) ----------------
@app.route("/api/user/firewall", methods=["POST"])
def firewall_cmd():
    d = request.json or {}
    user_id = d.get("user_id")
    token = d.get("token")
    agent_id = d.get("agent_id")
    cmd = d.get("cmd")

    if cmd not in ("ACTIVATE", "DEACTIVATE"):
        return jsonify({"error": "invalid command"}), 400

    stored_token = users.get(user_id, {}).get("token")
    if not stored_token or stored_token != token:
        return jsonify({"error": "unauthorized"}), 403

    agent = users.get(user_id, {}).get("agents", {}).get(agent_id)
    if not agent:
        return jsonify({"error": "agent not found"}), 404

    # Queue the command for the agent and record who triggered it
    agent["pending_cmd"] = cmd
    now = time.time()
    agent["last_toggle"] = now
    agent["last_actor"] = user_id

    # Record a per-user summary so admins can see recent activity
    u = users.get(user_id)
    if u is not None:
        u["last_action"] = f"{cmd} {agent_id}"
        if cmd == "ACTIVATE":
            u["last_activated"] = now
        u.setdefault("activity_log", []).append({"ts": now, "actor": user_id, "cmd": cmd, "agent": agent_id})

    save_data(users)
    print(f"📤 Command {cmd} queued for {user_id}/{agent_id} (actor={user_id})")
    return jsonify({"ok": True})


# ---------------- USER: SELECT PREFERRED FIREWALL (windows|linux) ----------------
@app.route("/api/user/firewall/select", methods=["POST"])
def user_select_firewall():
    d = request.json or {}
    user_id = d.get("user_id")
    token = d.get("token")
    selection = (d.get("selection") or '').lower()
    if selection not in ("windows", "linux"):
        return jsonify({"error": "invalid selection"}), 400
    stored_token = users.get(user_id, {}).get("token")
    if not stored_token or stored_token != token:
        return jsonify({"error": "unauthorized"}), 403
    users.setdefault(user_id, {})
    users[user_id]["preferred_firewall"] = selection
    save_data(users)
    print(f"⚙️ User {user_id} set preferred firewall: {selection}")
    return jsonify({"ok": True, "selection": selection})


# ---------------- USER: GET PREFERRED FIREWALL ----------------
@app.route("/api/user/firewall/selection", methods=["GET"])
def user_get_selection():
    user_id = request.args.get("user_id")
    token = request.args.get("token")
    if not user_id or not token:
        return jsonify({"error": "missing credentials"}), 400
    stored_token = users.get(user_id, {}).get("token")
    if not stored_token or stored_token != token:
        return jsonify({"error": "unauthorized"}), 403
    selection = users.get(user_id, {}).get("preferred_firewall")
    return jsonify({"selection": selection})


# ---------------- USER: GET INSTALLER (returns primary installer script) ----------------
@app.route("/api/user/firewall/download", methods=["GET"])
def user_download_installer():
    user_id = request.args.get("user_id")
    token = request.args.get("token")
    req_os = (request.args.get("os") or '').lower() or None

    if not user_id or not token:
        return jsonify({"error": "missing credentials"}), 400
    stored_token = users.get(user_id, {}).get("token")
    if not stored_token or stored_token != token:
        return jsonify({"error": "unauthorized"}), 403

    pref = users.get(user_id, {}).get("preferred_firewall")
    if req_os and pref and req_os != pref:
        return jsonify({"error": "requested os does not match your selected firewall"}), 400

    # Choose installer based on preference (req_os overrides)
    target = req_os or pref or 'windows'

    if target == 'windows':
        # return existing PowerShell installer file
        try:
            with open('install_firewall_agent.ps1','r', encoding='utf-8') as f:
                content = f.read()
            return content, 200, {
                'Content-Type': 'text/plain; charset=utf-8',
                'Content-Disposition': 'attachment; filename="install_firewall_agent.ps1"'
            }
        except Exception as e:
            return jsonify({"error": f"installer not available: {e}"}), 500

    elif target == 'linux':
        try:
            with open('install_firewall_agent.py','r', encoding='utf-8') as f:
                content = f.read()
            return content, 200, {
                'Content-Type': 'text/plain; charset=utf-8',
                'Content-Disposition': 'attachment; filename="install_firewall_agent.py"'
            }
        except Exception as e:
            return jsonify({"error": f"installer not available: {e}"}), 500

    return jsonify({"error": "unsupported target"}), 400


# ---------------- USER: FETCH INSTALLER FILES (JSON payload of files) ----------------
@app.route("/api/user/firewall/installer", methods=["GET"])
def user_get_installer_files():
    user_id = request.args.get("user_id")
    token = request.args.get("token")
    req_os = (request.args.get("os") or '').lower() or None

    if not user_id or not token:
        return jsonify({"error": "missing credentials"}), 400
    stored_token = users.get(user_id, {}).get("token")
    if not stored_token or stored_token != token:
        return jsonify({"error": "unauthorized"}), 403

    pref = users.get(user_id, {}).get("preferred_firewall")
    target = req_os or pref or 'windows'

    files = {}
    try:
        # Always include the policy JSON and the generic applier
        with open('hybrid_firewall.json', 'r', encoding='utf-8') as f:
            files['hybrid_firewall.json'] = f.read()
        with open('apply_hybrid_rules.py', 'r', encoding='utf-8') as f:
            files['apply_hybrid_rules.py'] = f.read()

        if target == 'windows':
            for name in ('window_agent.ps1', 'windows_firewall.ps1', 'install_firewall_agent_cross.ps1'):
                try:
                    with open(name, 'r', encoding='utf-8') as f:
                        files[name] = f.read()
                except Exception:
                    files[name] = ''
        else:
            # Linux: provide a simple systemd unit template and the installer script
            try:
                with open('install_firewall_agent.py', 'r', encoding='utf-8') as f:
                    files['install_firewall_agent.py'] = f.read()
            except Exception:
                files['install_firewall_agent.py'] = ''

            # Also include cross-platform PowerShell wrapper (useful if PowerShell Core is installed)
            try:
                with open('install_firewall_agent_cross.ps1', 'r', encoding='utf-8') as f:
                    files['install_firewall_agent_cross.ps1'] = f.read()
            except Exception:
                files['install_firewall_agent_cross.ps1'] = ''

            files['systemd.service'] = """[Unit]\nDescription=Hybrid Firewall Agent\nAfter=network.target\n\n[Service]\nType=simple\nExecStart=/usr/bin/python3 /opt/hybrid_firewall/apply_hybrid_rules.py\nRestart=always\nUser=root\n\n[Install]\nWantedBy=multi-user.target"""

        return jsonify({"ok": True, "os": target, "files": files})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ---------------- PUBLIC: FETCH INSTALLER FILES WITHOUT AUTH ----------------
@app.route("/api/public/installer", methods=["GET"])
def public_get_installer_files():
    req_os = (request.args.get("os") or '').lower() or None
    target = req_os or 'windows'

    files = {}
    try:
        with open('hybrid_firewall.json', 'r', encoding='utf-8') as f:
            files['hybrid_firewall.json'] = f.read()
        with open('apply_hybrid_rules.py', 'r', encoding='utf-8') as f:
            files['apply_hybrid_rules.py'] = f.read()

        if target == 'windows':
            for name in ('install_firewall_agent_cross.ps1', 'install_firewall_agent.ps1'):
                try:
                    with open(name, 'r', encoding='utf-8') as f:
                        files[name] = f.read()
                except Exception:
                    files[name] = ''
        else:
            try:
                with open('install_firewall_agent.py', 'r', encoding='utf-8') as f:
                    files['install_firewall_agent.py'] = f.read()
            except Exception:
                files['install_firewall_agent.py'] = ''
            try:
                with open('install_firewall_agent_cross.ps1', 'r', encoding='utf-8') as f:
                    files['install_firewall_agent_cross.ps1'] = f.read()
            except Exception:
                files['install_firewall_agent_cross.ps1'] = ''
            files['systemd.service'] = """[Unit]\nDescription=Hybrid Firewall Agent\nAfter=network.target\n\n[Service]\nType=simple\nExecStart=/usr/bin/python3 /opt/hybrid_firewall/apply_hybrid_rules.py\nRestart=always\nUser=root\n\n[Install]\nWantedBy=multi-user.target"""

        return jsonify({"ok": True, "os": target, "files": files})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ---------------- PUBLIC: DOWNLOAD PREPACKAGED ZIP INSTALLER ----------------
@app.route("/api/public/installer/zip", methods=["GET"])
def public_get_installer_zip():
    req_os = (request.args.get("os") or '').lower() or None
    target = req_os or 'windows'

    # Build in-memory zip
    mem = io.BytesIO()
    with zipfile.ZipFile(mem, mode='w', compression=zipfile.ZIP_DEFLATED) as z:
        # common files
        try:
            z.writestr('hybrid_firewall.json', open('hybrid_firewall.json', 'r', encoding='utf-8').read())
        except Exception:
            pass
        try:
            z.writestr('apply_hybrid_rules.py', open('apply_hybrid_rules.py', 'r', encoding='utf-8').read())
        except Exception:
            pass

        if target == 'windows':
            for name in ('install_firewall_agent_cross.ps1', 'install_firewall_agent.ps1', 'window_agent.ps1', 'windows_firewall.ps1'):
                try:
                    z.writestr(name, open(name, 'r', encoding='utf-8').read())
                except Exception:
                    pass
        else:
            for name in ('install_firewall_agent.py', 'install_firewall_agent_cross.ps1'):
                try:
                    z.writestr(name, open(name, 'r', encoding='utf-8').read())
                except Exception:
                    pass
            z.writestr('systemd.service', """[Unit]\nDescription=Hybrid Firewall Agent\nAfter=network.target\n\n[Service]\nType=simple\nExecStart=/usr/bin/python3 /opt/hybrid_firewall/apply_hybrid_rules.py\nRestart=always\nUser=root\n\n[Install]\nWantedBy=multi-user.target""")

    mem.seek(0)
    filename = f"hybrid_installer_{target}.zip"
    return send_file(mem, mimetype='application/zip', as_attachment=True, download_name=filename)


# ---------------- ADMIN: LIST USERS ----------------
@app.route("/api/admin/users", methods=["GET"])
def admin_list_users():
    user_id = request.args.get("user_id")
    token = request.args.get("token")
    # Only admin may call this endpoint
    if user_id != "admin":
        return jsonify({"error": "admin only"}), 403

    stored_token = users.get("admin", {}).get("token")
    if not stored_token or stored_token != token:
        return jsonify({"error": "unauthorized"}), 403

    out = []
    for uid, u in users.items():
        # Expose minimal summary per user
        out.append({
            "user_id": uid,
            "last_action": u.get("last_action"),
            "last_activated": u.get("last_activated")
        })
    return jsonify(out)


# ---------------- ADMIN: LIST AGENTS FOR A USER ----------------
@app.route("/api/admin/user/agents", methods=["GET"])
def admin_user_agents():
    user_id = request.args.get("user_id")
    token = request.args.get("token")
    target = request.args.get("target_user")
    # Only admin may call this endpoint
    if user_id != "admin":
        return jsonify({"error": "admin only"}), 403

    stored_token = users.get("admin", {}).get("token")
    if not stored_token or stored_token != token:
        return jsonify({"error": "unauthorized"}), 403

    if not target:
        return jsonify({"error": "missing target_user"}), 400
    if target not in users:
        return jsonify({"error": "target user not found"}), 404

    agents = users.get(target, {}).get("agents", {})
    result = []
    for aid, a in agents.items():
        result.append({
            "agent_id": aid,
            "os": a.get("os"),
            "connected": a.get("connected", False),
            "firewall": a.get("firewall", "UNKNOWN"),
            "last_heartbeat": a.get("last_heartbeat"),
            "last_toggle": a.get("last_toggle"),
            "last_actor": a.get("last_actor")
        })
    return jsonify(result)


# ---------------- ADMIN: DELETE USER ----------------
@app.route("/api/admin/users/delete", methods=["POST"])
def admin_delete_user():
    d = request.json or {}
    user_id = d.get("user_id")
    token = d.get("token")
    target = d.get("target_user")

    if user_id != "admin":
        return jsonify({"error": "admin only"}), 403
    stored_token = users.get("admin", {}).get("token")
    if not stored_token or stored_token != token:
        return jsonify({"error": "unauthorized"}), 403

    if not target:
        return jsonify({"error": "missing target_user"}), 400
    if target == "admin":
        return jsonify({"error": "cannot delete admin"}), 400

    if target in users:
        del users[target]
        save_data(users)
        print(f"🗑️ Admin {user_id} deleted user {target}")
        return jsonify({"ok": True})
    return jsonify({"error": "user not found"}), 404


# ---------------- USER: DELETE AGENT (user-triggered) ----------------
@app.route("/api/user/agent/delete", methods=["POST"])
def user_delete_agent():
    d = request.json or {}
    user_id = d.get("user_id")
    token = d.get("token")
    agent_id = d.get("agent_id")

    if not user_id or not token or not agent_id:
        return jsonify({"error": "missing fields"}), 400
    stored_token = users.get(user_id, {}).get("token")
    if not stored_token or stored_token != token:
        return jsonify({"error": "unauthorized"}), 403

    agents = users.get(user_id, {}).get("agents", {})
    if agent_id not in agents:
        return jsonify({"error": "agent not found"}), 404

    del agents[agent_id]
    # If no agents remain, remove the user entirely
    if not agents:
        del users[user_id]
        save_data(users)
        print(f"🗑️ User {user_id} deleted themselves (no agents remain)")
        return jsonify({"ok": True, "user_deleted": True})

    save_data(users)
    print(f"🗑️ User {user_id} deleted agent {agent_id}")
    return jsonify({"ok": True, "user_deleted": False})


# ---------------- ADMIN: DELETE AGENT (admin-triggered) ----------------
@app.route("/api/admin/agent/delete", methods=["POST"])
def admin_delete_agent():
    d = request.json or {}
    user_id = d.get("user_id")
    token = d.get("token")
    target = d.get("target_user")
    agent_id = d.get("agent_id")

    if user_id != "admin":
        return jsonify({"error": "admin only"}), 403
    stored_token = users.get("admin", {}).get("token")
    if not stored_token or stored_token != token:
        return jsonify({"error": "unauthorized"}), 403

    if not target or not agent_id:
        return jsonify({"error": "missing fields"}), 400
    if target not in users:
        return jsonify({"error": "target user not found"}), 404

    agents = users[target].get("agents", {})
    if agent_id not in agents:
        return jsonify({"error": "agent not found"}), 404

    del agents[agent_id]
    # If no agents remain, remove the user entirely
    if not agents:
        del users[target]
        save_data(users)
        print(f"🗑️ Admin {user_id} deleted agent {agent_id} and removed user {target} (no agents)")
        return jsonify({"ok": True, "user_deleted": True})

    save_data(users)
    print(f"🗑️ Admin {user_id} deleted agent {agent_id} for user {target}")
    return jsonify({"ok": True, "user_deleted": False})

# ---------------- AGENT POLL FOR COMMAND ----------------
@app.route("/api/agent/command", methods=["POST"])
def poll():
    d = request.get_json(silent=True) or {}

    user_id = d.get("user_id")
    agent_id = d.get("agent_id")

    if not user_id or not agent_id:
        return jsonify({"error": "missing user_id or agent_id"}), 400

    agent = users.get(user_id, {}).get("agents", {}).get(agent_id)
    if not agent or not agent.get("pending_cmd"):
        return jsonify({"cmd": None})

    cmd = agent["pending_cmd"]
    agent["pending_cmd"] = None
    save_data(users)

    payload = f"{agent_id}|{cmd}"
    sig = sign(agent["secret"], payload)

    print(f"📦 Agent {user_id}/{agent_id} received command: {cmd}")

    return jsonify({"cmd": cmd, "sig": sig})


if __name__ == "__main__":
    # Ensure an admin token exists for initial setup (print it once on startup).
    admin_token = ensure_user_token('admin')
    print(f"\n🚀 Firewall Backend Started")
    print(f"📍 Visit: http://10.65.42.253:5000")
    print(f"👤 Admin token: {admin_token}\n")
    app.run(host="0.0.0.0", port=5000, debug=True, threaded=True)