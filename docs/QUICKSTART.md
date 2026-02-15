# Quick Start Guide - Windows Firewall with JSON Rules

## TL;DR - 3 Easy Steps

### 1. Validate Your Setup
```powershell
python test_windows_policy.py
```
✓ Should show: "All tests passed!"

### 2. Install the Agent
```powershell
.\install_firewall_agent.ps1 -UserId "your_username" `
  -BackendUrl "http://10.65.42.253:5000"
```
✓ Copies JSON file, converter script, creates scheduled task

### 3. Activate from Web UI
- Open: `http://10.65.42.253:5000`
- Click "ACTIVATE" button
- ✓ Firewall is now active with rules from JSON

## What Happens When You Click ACTIVATE?

```
Web UI [ACTIVATE Button]
   ↓
Backend: agent["pending_cmd"] = "ACTIVATE"
   ↓
Windows Agent: polls /api/agent/command
   ↓
Agent runs: windows_firewall.ps1 -Mode ACTIVATE
   ↓
Script reads: hybrid_firewall.json
   ↓
Converts rules: New-NetFirewallRule commands
   ↓
Applies: All rules to "Enterprise-Hardening" group
   ↓
Reports back: firewall = "ACTIVE"
   ↓
Web UI: Shows ✓ ACTIVE
```

## Files You Need to Know

| File | Purpose | When You Need It |
|------|---------|--|
| `hybrid_firewall.json` | Your firewall rules (don't edit lightly!) | To understand what rules are applied |
| `windows_firewall.ps1` | Main firewall script | Never touch - it's auto-generated |
| `window_agent.ps1` | Polling loop script | Auto-generated during install |
| `firewall_control.ps1` | Manual control tool | For testing/emergencies |
| `test_windows_policy.py` | Validation script | Before first deployment |
| `windows_rule_converter.py` | Rule preview tool | To see what rules become |

## Common Tasks

### Check Firewall Status
```powershell
.\firewall_control.ps1 -Action STATUS
```

### List Applied Rules
```powershell
Get-NetFirewallRule -Group "Enterprise-Hardening" | Select DisplayName, Direction, Action
```

### View Logs
```powershell
Get-Content C:\Users\Public\Documents\firewall_1\agent.log -Tail 20
```

### Manually Activate (for testing)
```powershell
.\firewall_control.ps1 -Action ACTIVATE
```

### Manually Deactivate (emergency)
```powershell
.\firewall_control.ps1 -Action DEACTIVATE
```

### Preview Rule Conversion
```powershell
python windows_rule_converter.py
```

## Understanding Rule Priorities

Rules are applied in **descending priority order**. Example:
```json
Priority 200 → Allow Loopback (runs first)
Priority 190 → Allow Established
Priority 180 → Allow SSH/HTTP/HTTPS
Priority 170 → Block ICMP
Priority 160 → Block Suspicious TCP Flags
...more rules...
```

**Higher priority = runs first** and takes precedence.

## Rule Actions in JSON → Windows

| JSON Action | Windows Result |
|---|---|
| `"action": "allow"` | `-Action Allow` (permits traffic) |
| `"action": "deny"` | `-Action Block` (drops traffic) |
| `"action": "rate-limit"` | `-Action Allow` (note: no native rate-limit in Windows) |
| `"action": "log"` | Logged to event viewer |

## Supported Protocols

| Protocol | Example |
|---|---|
| `"tcp"` | SSH, HTTP, HTTPS |
| `"udp"` | DNS, NTP |
| `"icmp"` | Ping |

## Supported Directions

| Direction | Meaning |
|---|---|
| `"ingress"` | Incoming traffic (→ your machine) |
| `"egress"` | Outgoing traffic (← leaving your machine) |
| `"both"` | Both directions |

## Supported Layers (Windows Only)

| Layer | Support | Notes |
|---|---|---|
| `L3` | ✓ Yes | IP-based rules |
| `L4` | ✓ Yes | Port-based rules |
| `L2` | ✗ No | Requires special drivers (skipped) |

## Editing Rules

To add a new rule, edit `hybrid_firewall.json`:

```json
{
  "id": "my_new_rule",
  "enabled": true,
  "action": "allow",
  "layer": "L4",
  "direction": "ingress",
  "match": {
    "protocol": "tcp",
    "dport": [8080]
  },
  "description": "Allow my custom app",
  "priority": 175
}
```

Then:
1. Save the JSON
2. Click "DEACTIVATE" in web UI
3. Click "ACTIVATE" in web UI
4. ✓ New rule is applied!

## Emergency Disable All Rules

```powershell
# Option 1: Via web UI
Click DEACTIVATE button

# Option 2: Manual
.\firewall_control.ps1 -Action DEACTIVATE

# Option 3: PowerShell
Get-NetFirewallRule -Group "Enterprise-Hardening" | Remove-NetFirewallRule
```

## Verify Everything is Working

```powershell
# 1. Check rules exist
Get-NetFirewallRule -Group "Enterprise-Hardening" | Measure-Object
# Output should show Count > 0

# 2. Check state file
Get-Content C:\ProgramData\fw_state.json | ConvertFrom-Json
# Output should show active_rules array

# 3. Check events
Get-EventLog -LogName Application -Source "Firewall-Escalation" -Newest 3
# Should see "ACTIVATED" event

# 4. Check agent is running
Get-ScheduledTask -TaskName *EnterpriseFirewall* | Select State
# State should be "Running"
```

## Troubleshooting 101

**Q: Firewall shows INACTIVE but I clicked ACTIVATE**
```powershell
# Check if JSON exists
Test-Path C:\Users\Public\Documents\firewall_1\hybrid_firewall.json

# Check logs
Get-Content C:\Users\Public\Documents\firewall_1\agent.log | tail -20
```

**Q: Rules aren't being applied**
```powershell
# Validate JSON syntax
python test_windows_policy.py

# Check if rules have "enabled": true
# Check if layer is "L3" or "L4" (not L2)
```

**Q: Can't reach the web UI**
```powershell
# Test backend connection
Test-NetConnection 10.65.42.253 -Port 5000

# Check if agent is connected
Get-Content C:\Users\Public\Documents\firewall_1\agent.log | Select-String "Registered"
```

**Q: Only some rules were created**
```powershell
# Rules with "enabled": false are skipped
# Rules with "layer": "L2" are skipped (Windows limitation)
# Use python windows_rule_converter.py to see what converts
```

## Pro Tips

1. **Test before deploying**: Always run `python test_windows_policy.py` after editing JSON
2. **Monitor events**: Watch `Application > Firewall-Escalation` in Event Viewer
3. **Keep backups**: Save copies of your `hybrid_firewall.json` before major changes
4. **Document priority**: Higher priority = runs first
5. **Use descriptive IDs**: Make rule IDs meaningful (e.g., `allow_app_ports` not `rule_3`)

## Architecture at a Glance

```
┌──────────────────────┐
│   hybrid_firewall.json   │ ← Your rules live here
└──────────┬───────────┘
           │
           ↓
┌──────────────────────┐
│  windows_firewall.ps1   │ ← Reads JSON, converts to Windows
└──────────┬───────────┘
           │
           ↓
┌──────────────────────────────────────┐
│  New-NetFirewallRule (Windows native)│ ← Applied to system
└──────────────────────────────────────┘
           │
           ↓
┌──────────────────────────────────────┐
│  Windows Firewall Rules              │ ← Active protection
│  (Enterprise-Hardening group)        │
└──────────────────────────────────────┘
```

## Next Steps

- [ ] Run `python test_windows_policy.py`
- [ ] Run `.\install_firewall_agent.ps1`
- [ ] Check status with `.\firewall_control.ps1 -Action STATUS`
- [ ] Open web UI and click ACTIVATE
- [ ] Verify rules with `Get-NetFirewallRule -Group "Enterprise-Hardening"`

## Still Questions?

See detailed docs:
- **Full Technical Guide**: `WINDOWS_FIREWALL_README.md`
- **Integration Details**: `INTEGRATION_SUMMARY.md`
- **Rule Validation**: `test_windows_policy.py --help`

---

Good luck! Your Windows agent is now JSON-driven! 🚀
