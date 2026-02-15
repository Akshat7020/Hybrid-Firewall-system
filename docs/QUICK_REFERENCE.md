# Quick Reference Card

## One-Minute Setup

```bash
# 1. Test
python test_windows_policy.py

# 2. Install
.\install_firewall_agent.ps1 -UserId "username" -BackendUrl "http://10.65.42.253:5000"

# 3. Activate via Web UI (or manually)
.\firewall_control.ps1 -Action ACTIVATE
```

## Command Reference

| Task | Command |
|---|---|
| Check status | `.\firewall_control.ps1 -Action STATUS` |
| Activate firewall | `.\firewall_control.ps1 -Action ACTIVATE` |
| Deactivate firewall | `.\firewall_control.ps1 -Action DEACTIVATE` |
| List rules | `Get-NetFirewallRule -Group "Enterprise-Hardening"` |
| Count rules | `(Get-NetFirewallRule -Group "Enterprise-Hardening").Count` |
| View logs | `Get-Content C:\Users\Public\Documents\firewall_1\agent.log -Tail 20` |
| View events | `Get-EventLog -LogName Application -Source Firewall-Escalation -Newest 10` |
| View state | `Get-Content C:\ProgramData\fw_state.json \| ConvertFrom-Json` |
| Preview rules | `python windows_rule_converter.py` |
| Validate policy | `python test_windows_policy.py` |
| Remove all rules | `Get-NetFirewallRule -Group "Enterprise-Hardening" \| Remove-NetFirewallRule` |

## JSON Rule Structure

```json
{
  "id": "unique_rule_id",
  "enabled": true,
  "action": "allow",           // allow | deny | rate-limit | log
  "layer": "L4",               // L3 | L4 (L2 skipped on Windows)
  "direction": "ingress",      // ingress | egress | both
  "match": {
    "protocol": "tcp",         // tcp | udp | icmp
    "dport": [22, 80, 443]     // single port or array
  },
  "description": "Allow SSH and HTTP",
  "priority": 180              // higher = runs first
}
```

## Flow at a Glance

```
Web UI [ACTIVATE]
   ↓↓↓↓↓↓↓↓
Backend: pending_cmd = "ACTIVATE"
   ↓↓↓↓↓↓↓↓
Agent polls /api/agent/command
   ↓↓↓↓↓↓↓↓
windows_firewall.ps1 executes
   ↓↓↓↓↓↓↓↓
Reads hybrid_firewall.json
   ↓↓↓↓↓↓↓↓
Converts & applies rules
   ↓↓↓↓↓↓↓↓
Windows Firewall updated
   ↓↓↓↓↓↓↓↓
Agent reports: firewall = "ACTIVE"
   ↓↓↓↓↓↓↓↓
Web UI: ✓ ACTIVE
```

## File Locations

| Item | Location |
|---|---|
| JSON Rules | `C:\Users\Public\Documents\firewall_1\hybrid_firewall.json` |
| Main Script | `C:\Users\Public\Documents\firewall_1\windows_firewall.ps1` |
| Agent Script | `C:\Users\Public\Documents\firewall_1\window_agent.ps1` |
| Control Tool | `C:\Users\Public\Documents\firewall_1\firewall_control.ps1` |
| State File | `C:\ProgramData\fw_state.json` |
| Agent Log | `C:\Users\Public\Documents\firewall_1\agent.log` |
| Events | Event Viewer → Application → Firewall-Escalation |

## Rule Actions → Windows Mapping

| JSON Action | Windows Result |
|---|---|
| `allow` | `-Action Allow` ✓ |
| `deny` | `-Action Block` ✗ |
| `rate-limit` | `-Action Allow` (note: no native rate limiting) |

## Protocols Supported

| Protocol | Example |
|---|---|
| `tcp` | SSH (22), HTTP (80), HTTPS (443) |
| `udp` | DNS (53), NTP (123) |
| `icmp` | Ping |

## Directions

| Direction | Meaning |
|---|---|
| `ingress` | Incoming ← |
| `egress` | Outgoing → |
| `both` | Both ← → |

## Common Troubleshooting

**Rules not applying?**
```powershell
# Check JSON validity
python test_windows_policy.py

# Check if rules exist
Get-NetFirewallRule -Group "Enterprise-Hardening" | Measure-Object
```

**Firewall shows INACTIVE?**
```powershell
# Check logs
Get-Content C:\Users\Public\Documents\firewall_1\agent.log | Select-String ERROR

# Check events
Get-EventLog -LogName Application -Source Firewall-Escalation
```

**Agent not responding?**
```powershell
# Check backend connectivity
Test-NetConnection 10.65.42.253 -Port 5000

# Check agent registration
Get-Content C:\Users\Public\Documents\firewall_1\agent.log | Select-String "Registered"
```

## Emergency: Kill All Rules

```powershell
Get-NetFirewallRule -Group "Enterprise-Hardening" | Remove-NetFirewallRule -Force
```

## Configuration Locations

| Config | File |
|---|---|
| User ID | `C:\Users\Public\Documents\firewall_1\user_id.txt` |
| Agent ID | `C:\Users\Public\Documents\firewall_1\agent_id.txt` |
| User Token | `C:\Users\Public\Documents\firewall_1\user_token.txt` |
| Backend URL | Configured in scheduled task |

## Priority Reference

```
Priority 200 ← Loopback (runs first)
Priority 190 ← Established connections
Priority 180 ← Well-known ports (SSH, HTTP, HTTPS)
Priority 170 ← Block ICMP (ping)
Priority 160 ← Block suspicious TCP flags
Priority 150 ← Block UDP
Priority 100 ← Log drops
...
Priority 50  ← Custom rules
```

Higher priority = runs first and takes precedence

## Desktop Shortcuts (Optional)

Create these for quick access:

**Activate.lnk** (PowerShell shortcut)
```
Target: powershell -Command "cd 'C:\Users\Public\Documents\firewall_1'; .\firewall_control.ps1 -Action ACTIVATE"
```

**Deactivate.lnk** (PowerShell shortcut)
```
Target: powershell -Command "cd 'C:\Users\Public\Documents\firewall_1'; .\firewall_control.ps1 -Action DEACTIVATE"
```

**Status.lnk** (PowerShell shortcut)
```
Target: powershell -Command "cd 'C:\Users\Public\Documents\firewall_1'; .\firewall_control.ps1 -Action STATUS"
```

## Help & Docs

- **Quick Start**: `QUICKSTART.md`
- **What Changed**: `INTEGRATION_SUMMARY.md`
- **Technical Deep Dive**: `WINDOWS_FIREWALL_README.md`
- **File Overview**: `FILE_STRUCTURE_SUMMARY.md`
- **Status**: `IMPLEMENTATION_COMPLETE.md` ← You are here

---

**Remember**: Always run `python test_windows_policy.py` after editing JSON files!

**Key Principle**: Edit JSON → Click ACTIVATE → Profit 🚀
