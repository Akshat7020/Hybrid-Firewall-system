#!/usr/bin/env python3
"""
Installer for Hybrid Firewall Agent
- Usage: python install_firewall_agent.py --backend http://10.144.164.253:5000--user-id <user> --token <token>
- Detects local OS and ensures it matches user's selection on backend
- Downloads installer files and policy, registers the agent, and optionally sets up a service
"""

import os
import sys
import argparse
import platform
import json
import uuid
import subprocess
from pathlib import Path
from typing import Any, cast

requests: Any = None
try:
    import requests as _requests
    requests = _requests
except Exception:
    requests = None


def ensure_requests():
    global requests
    if requests:
        return True
    try:
        import pip
        subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'requests'])
        import requests as r
        requests = r
        return True
    except Exception as e:
        print('ERROR: "requests" library is required. Install it manually (pip install requests)')
        return False


def guess_local_os():
    p = platform.system().lower()
    if 'windows' in p:
        return 'windows'
    if 'linux' in p or 'darwin' in p:
        # treat macOS as linux-target for installer mismatch purposes
        return 'linux'
    return p


def get_selection(backend, user_id, token):
    url = f"{backend.rstrip('/')}/api/user/firewall/selection"
    r = requests.get(url, params={'user_id': user_id, 'token': token}, timeout=8)
    r.raise_for_status()
    return r.json().get('selection')


def fetch_installer_files(backend, user_id, token, os_type):
    url = f"{backend.rstrip('/')}/api/user/firewall/installer"
    r = requests.get(url, params={'user_id': user_id, 'token': token, 'os': os_type}, timeout=15)
    r.raise_for_status()
    return r.json()


def register_agent(backend, user_id, agent_id, os_type):
    url = f"{backend.rstrip('/')}/api/agent/register"
    r = requests.post(url, json={'user_id': user_id, 'agent_id': agent_id, 'os_type': os_type}, timeout=8)
    r.raise_for_status()
    return r.json()


def write_files(out_dir: Path, files: dict):
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, content in files.items():
        if not content:
            continue
        p = out_dir / name
        p.parent.mkdir(parents=True, exist_ok=True)
        with open(p, 'w', encoding='utf-8') as f:
            f.write(content)
        # Make executables executable on POSIX
        if os.name != 'nt' and p.suffix in ('.sh', '.py'):
            p.chmod(0o755)


def setup_systemd_service(out_dir: Path):
    unit = f"""[Unit]
Description=Hybrid Firewall Agent
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 {out_dir}/apply_hybrid_rules.py --daemon
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
"""
    unit_path = Path('/etc/systemd/system/hybrid-firewall.service')
    try:
        with open(unit_path, 'w', encoding='utf-8') as f:
            f.write(unit)
        subprocess.run(['systemctl', 'daemon-reload'], check=True)
        subprocess.run(['systemctl', 'enable', '--now', 'hybrid-firewall'], check=True)
        print('Systemd service created and started: hybrid-firewall (daemon mode)')
    except Exception as e:
        print('Could not create systemd service automatically:', e)
        print('You can create a systemd unit with the following content and enable it manually:')
        print(unit)

def setup_windows_schtask(out_dir: Path):
    # Use schtasks to create a task to run the agent on startup
    script = str(out_dir / 'window_agent.ps1')
    if not (out_dir / 'window_agent.ps1').exists():
        print('No window_agent.ps1 present; skipping scheduled task creation')
        return
    task_name = 'HybridFirewallAgent'
    cmd = f'schtasks /Create /SC ONSTART /RL HIGHEST /TN {task_name} /TR "powershell -ExecutionPolicy Bypass -File \"{script}\"" /F'
    try:
        subprocess.run(cmd, shell=True, check=True)
        print('Scheduled task created: HybridFirewallAgent')
    except Exception as e:
        print('Failed to create scheduled task automatically:', e)
        print('You can create a task manually to execute: powershell -ExecutionPolicy Bypass -File "{}"'.format(script))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--backend', default=None, help='Backend URL (default: http://10.144.164.253:5000 or env BACKEND)')
    parser.add_argument('--user-id', default=None, help='User ID (default: read from user_id.txt)')
    parser.add_argument('--token', default=None, help='User token (default: read from user_token.txt)')
    parser.add_argument('--base-dir', default=None, help='Optional output directory')
    parser.add_argument('--yes', action='store_true', help='Skip interactive prompts')
    args = parser.parse_args()

    # Convenience fallbacks when flags are omitted
    if not args.backend:
        args.backend = os.environ.get('BACKEND') or 'http://10.144.164.253:5000'
        print(f'Using backend: {args.backend}')

    script_dir = Path(__file__).parent

    # Try to read user_id from disk if not provided (try current dir, script dir, home)
    if not args.user_id:
        tried = []
        # 1) current working dir
        tried.append(('cwd', Path('user_id.txt')))
        # 2) script directory
        tried.append(('script', script_dir / 'user_id.txt'))
        # 3) home path
        tried.append(('home', Path.home() / '.hybrid' / 'user_id.txt'))
        found = None
        for label, p in tried:
            try:
                if p.exists():
                    args.user_id = p.read_text(encoding='utf-8').strip()
                    print(f'Using user id from {label} file: {p}')
                    found = p
                    break
            except Exception:
                continue

    # Environment fallback for user id
    if not args.user_id:
        args.user_id = os.environ.get('USER_ID') or os.environ.get('USER')
        if args.user_id:
            print('Using user id from environment variable')

    # Prompt interactively if still missing and terminal is interactive
    if not args.user_id and not args.yes and sys.stdin.isatty():
        try:
            ui = input('Enter user id (or press Enter to abort): ').strip()
            if ui:
                args.user_id = ui
        except Exception:
            pass

    # Try to read token from disk if not provided (script dir then cwd then home)
    if not args.token:
        tried_t = []
        tried_t.append(('cwd', Path('user_token.txt')))
        tried_t.append(('script', script_dir / 'user_token.txt'))
        tried_t.append(('home', Path.home() / '.hybrid' / 'user_token.txt'))
        for label, p in tried_t:
            try:
                if p.exists():
                    args.token = p.read_text(encoding='utf-8').strip()
                    print(f'Using user token from {label} file: {p}')
                    break
            except Exception:
                continue

    # Token environment fallback
    if not args.token:
        args.token = os.environ.get('USER_TOKEN') or os.environ.get('TOKEN')
        if args.token:
            print('Using user token from environment variable')

    # Require user_id at minimum; token is optional (script can request it from backend)
    if not args.user_id:
        print('ERROR: --user-id is required (provide with --user-id, set USER_ID env, or place a user_id.txt in the repo)')
        sys.exit(2)

    if not ensure_requests():
        sys.exit(1)
    # Ensure type checkers know requests is available after ensure_requests()
    assert requests is not None

    # If no token provided, try to obtain one now so selection/installer requests have it.
    if not args.token:
        try:
            print('Requesting token from backend (early)...')
            r = requests.post(f"{args.backend.rstrip('/')}/api/user/init", json={'user_id': args.user_id}, timeout=8)
            r.raise_for_status()
            token = r.json().get('token')
            if token:
                args.token = token
                try:
                    with open(script_dir / 'user_token.txt', 'w', encoding='utf-8') as f:
                        f.write(args.token)
                    print(f'Received user token and saved to {script_dir / "user_token.txt"}')
                except Exception:
                    pass
            else:
                print('Backend did not return a token (early). Continuing without token...')
        except Exception as e:
            print('Failed to obtain token from backend (early):', e)
            print('Continuing without token — selection/installer requests may fail if token is required.')

    local_os = guess_local_os()
    print(f'Detected local OS: {local_os}')

    try:
        selection = get_selection(args.backend, args.user_id, args.token)
    except Exception as e:
        print('Failed to query backend selection:', e)
        selection = None

    if selection and selection != local_os:
        print(f"ERROR: Your account's selected firewall is '{selection}' but this machine is '{local_os}'. Aborting.")
        sys.exit(2)

    target = selection or local_os
    print(f'Installing files for target: {target}')

    try:
        payload = fetch_installer_files(args.backend, args.user_id, args.token, target)
    except Exception as e:
        print('Failed to fetch installer files:', e)
        sys.exit(1)

    if not payload.get('ok'):
        print('Backend did not provide installer files:', payload)
        sys.exit(1)

    files = payload.get('files', {})

    # Choose destination dir
    if args.base_dir:
        out_dir = Path(args.base_dir)
    else:
        if local_os == 'windows':
            out_dir = Path(r'C:\Users\Public\Documents\firewall_1')
        else:
            out_dir = Path('/opt/hybrid_firewall')

    write_files(out_dir, files)
    print(f'Wrote {len(files)} files to {out_dir}')

    # Persist user_id locally
    try:
        with open(out_dir / 'user_id.txt', 'w', encoding='utf-8') as f: f.write(args.user_id)
    except Exception as e:
        print('Warning: could not write user_id file:', e)

    # Ensure we have a token; try to obtain if missing, otherwise persist token to install dir
    if not args.token:
        try:
            print('Requesting token from backend...')
            r = requests.post(f"{args.backend.rstrip('/')}/api/user/init", json={'user_id': args.user_id}, timeout=8)
            r.raise_for_status()
            token = r.json().get('token')
            if not token:
                print('Backend did not return a token; aborting')
                sys.exit(1)
            args.token = token
            with open(out_dir / 'user_token.txt', 'w', encoding='utf-8') as f: f.write(args.token)
            print(f'Received user token and saved to {out_dir / "user_token.txt"}')
            print('Keep this token private; use it to sign in to the web UI.')
        except Exception as e:
            print('Failed to obtain token from backend:', e)
            print('You can still register an agent without a token but you will not be able to use the web UI until you obtain token for your user id.')
    else:
        # Persist token that we may have obtained earlier
        try:
            with open(out_dir / 'user_token.txt', 'w', encoding='utf-8') as f:
                f.write(args.token)
            print(f'Saved user token to {out_dir / "user_token.txt"}')
        except Exception as e:
            print('Warning: could not save user token to install dir:', e)
    # Register agent
    agent_id = str(uuid.uuid4())
    try:
        register_agent(args.backend, args.user_id, agent_id, local_os)
        with open(out_dir / 'agent_id.txt', 'w', encoding='utf-8') as f: f.write(agent_id)
        print(f'Agent registered: {agent_id}')
    except Exception as e:
        print('Failed to register agent with backend:', e)

    # Attempt to create service/task if running with sufficient privileges
    if local_os == 'linux':
        if hasattr(os, 'geteuid') and cast(Any, os).geteuid() == 0:
            setup_systemd_service(out_dir)
        else:
            print('Not running as root: skipping systemd service creation. Run the following as root to enable:')
            print('sudo cp {out}/apply_hybrid_rules.py /opt/hybrid_firewall/ && sudo systemctl enable --now hybrid-firewall'.format(out=out_dir))
    elif local_os == 'windows':
        try:
            # Attempt schtasks; may require admin
            setup_windows_schtask(out_dir)
        except Exception as e:
            print('Scheduled task creation failed or requires admin:', e)
            print('Run the following in an elevated PowerShell to create the task:')
            print(f'schtasks /Create /SC ONSTART /RL HIGHEST /TN HybridFirewallAgent /TR "powershell -ExecutionPolicy Bypass -File \"{out_dir}\\window_agent.ps1\"" /F')

    print('Installation complete. Start the agent or reboot to have it run at startup.')


if __name__ == '__main__':
    main()
