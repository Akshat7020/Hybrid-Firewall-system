# How to Run the Firewall System

## 📋 Quick Start

### 1. Start Backend Server
```powershell
# Run on your server machine
cd C:\Users\Public\Documents\firewall_1
python window_backend.py
```
Server starts at: **http://10.65.42.253:5000**

---

## 2. Install Agents on Target Machines

### Windows Agent Installation
```powershell
# On Windows machine (as Administrator):
Set-ExecutionPolicy Bypass -Scope Process -Force
cd <download_folder>
.\install_firewall_agent_cross.ps1 -BackendUrl "http://10.65.42.253:5000"
```

**Auto-generated credentials will be saved to:**
- `C:\Users\Public\Documents\firewall_1\user_id.txt`
- `C:\Users\Public\Documents\firewall_1\user_token.txt`

### Linux Agent Installation
```bash
# On Linux machine:
python3 install_firewall_agent.py --backend "http://10.65.42.253:5000"
```

**Credentials generated in:**
- `~/firewall_agent/user_id.txt`
- `~/firewall_agent/user_token.txt`

---

## 3. Access Web UI

1. Open browser to: **http://10.65.42.253:5000**
2. Go to **Installation tab** → Download installer for your OS
3. Run installer on target machine
4. Go to **Agents tab** → Sign in with generated credentials
5. Click **ACTIVATE** or **DEACTIVATE** to control firewall

---

## 4. Manage Firewall Rules

Edit: **`hybrid_firewall.json`**

Example rule:
```json
{
  "rules": [
    {
      "id": "rule_123",
      "description": "Block SSH from untrusted",
      "layer": "L3",
      "action": "deny",
      "protocol": "tcp",
      "direction": "ingress",
      "priority": 100,
      "enabled": true,
      "match": {
        "src_cidr": "192.168.1.0/24",
        "dst_port": "22"
      }
    }
  ]
}
```

**Changes apply automatically** to all connected agents within 5 seconds.

---

## 5. Run Tests

```powershell
# Test hybrid rule application logic
cd C:\Users\Public\Documents\firewall_1
python run_tests.py
```

Expected output:
```
✓ test_generate_iptables_cmd_basic PASSED
✓ test_generate_ebtables_cmd_mac_and_vlan PASSED
✓ test_arp_inspection_check PASSED
✓ All tests passed!
```

---

## 📁 File Structure Reference

```
firewall_1/
├── window_backend.py              ← Start here (backend server)
├── install_firewall_agent.ps1     ← Install on Windows
├── install_firewall_agent.py      ← Install on Linux
├── install_firewall_agent_cross.ps1
├── windows_firewall.ps1           ← Applied on Windows agents
├── window_agent.ps1               ← Windows agent poller
├── hybrid_firewall.json           ← Edit to change rules
├── static/index.html              ← Web UI
├── run_tests.py                   ← Run tests
├── tests/
│   ├── test_apply_hybrid_rules.py
│   └── test_windows_policy.py
└── docs/                          ← Documentation
    ├── 00_START_HERE.md
    ├── QUICKSTART.md
    └── ...
```

---

## 🔄 Typical Workflow

1. **Setup**: Start `window_backend.py` on server
2. **Deploy**: Run `install_firewall_agent_*.ps1` or `.py` on target machines
3. **Monitor**: View agents in web UI (Agents tab)
4. **Control**: Click ACTIVATE/DEACTIVATE on agent cards
5. **Manage**: Edit `hybrid_firewall.json` for rule changes
6. **Verify**: Run `python run_tests.py` to validate logic

---

## ⚡ Admin Commands

### View all agents connected
- Go to Admin tab → Load All Users

### Check agent logs
**Windows:**
```powershell
Get-Content "C:\Users\Public\Documents\firewall_1\agent.log"
```

**Linux:**
```bash
tail -f ~/firewall_agent/agent.log
```

### Manually activate firewall on agent
**Windows:**
```powershell
cd C:\Users\Public\Documents\firewall_1
.\windows_firewall.ps1 -Mode ACTIVATE
```

**Linux:**
```bash
python3 apply_hybrid_rules.py
```

---

## 🆘 Troubleshooting

| Issue | Solution |
|-------|----------|
| Agent doesn't connect | Check backend is running on correct IP/port |
| Firewall rules not applying | Verify rules are `enabled: true` in hybrid_firewall.json |
| Tests fail | Run `pip install pytest` first |
| Permission denied | Run installers as Administrator (Windows) or with sudo (Linux) |

