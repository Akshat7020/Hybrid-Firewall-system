# Integration Summary: JSON-Driven Windows Firewall

## What Changed

Your Windows firewall agent now reads firewall rules from `hybrid_firewall.json` instead of having them hardcoded. This brings Windows in alignment with your Linux agent approach.

## Files Created

1. **`json_to_windows_rules.ps1`** (NEW)
   - PowerShell module to convert JSON rules to Windows firewall format
   - Can be imported or run standalone
   - Functions: `Apply-WindowsRules`, `Get-WindowsRulesFromJson`, `Convert-JsonRulesToWindows`

2. **`windows_rule_converter.py`** (NEW)
   - Python script to preview rule conversions before deployment
   - Use: `python windows_rule_converter.py`

3. **`test_windows_policy.py`** (NEW)
   - Validates the `hybrid_firewall.json` policy structure
   - Tests rule applicability, port ranges, priorities
   - Use: `python test_windows_policy.py`

4. **`firewall_control.ps1`** (NEW)
   - Manual firewall control script for testing/emergencies
   - Commands: `STATUS`, `ACTIVATE`, `DEACTIVATE`
   - Use: `.\firewall_control.ps1 -Action ACTIVATE`

5. **`WINDOWS_FIREWALL_README.md`** (NEW)
   - Complete documentation of the new system
   - Architecture diagrams, troubleshooting, examples

## Files Updated

1. **`windows_firewall.ps1`** (MODIFIED)
   - Now reads from `hybrid_firewall.json` instead of hardcoding rules
   - Still accepts `-Mode ACTIVATE/DEACTIVATE` parameter
   - Converts L3/L4 rules to Windows `New-NetFirewallRule` commands
   - Skips L2 rules (not supported by Windows via NetFirewall API)

2. **`install_firewall_agent.ps1`** (MODIFIED)
   - Added paths for JSON and converter script
   - Copies `hybrid_firewall.json` during installation
   - Copies `json_to_windows_rules.ps1` during installation

## How It Works

### From Web UI (Windows)
```
1. User clicks "ACTIVATE" button in web UI
   ↓
2. Backend stores: agent["pending_cmd"] = "ACTIVATE"
   ↓
3. Agent script polls: GET /api/agent/command
   ↓
4. Agent receives command and executes:
   powershell -File windows_firewall.ps1 -Mode ACTIVATE
   ↓
5. Firewall script:
   - Loads hybrid_firewall.json
   - Filters for enabled L3/L4 rules
   - Converts each rule to New-NetFirewallRule parameters
   - Applies rules with group "Enterprise-Hardening"
   ↓
6. Agent reports back: firewall = "ACTIVE"
   ↓
7. Web UI updates status: ✓ ACTIVE
```

### Rule Conversion Example

**JSON rule:**
```json
{
  "id": "allow_tcp_well_known_ports",
  "enabled": true,
  "action": "allow",
  "layer": "L4",
  "direction": "ingress",
  "match": { "protocol": "tcp", "dport": [22, 80, 443] },
  "description": "Allow SSH, HTTP, HTTPS",
  "priority": 180
}
```

**Becomes:**
```powershell
New-NetFirewallRule `
  -DisplayName "Allow SSH, HTTP, HTTPS [allow_tcp_well_known_ports]" `
  -Direction Inbound `
  -Action Allow `
  -Protocol TCP `
  -LocalPort "22,80,443" `
  -Group "Enterprise-Hardening" `
  -Profile Any `
  -Enabled $true
```

## Installation & Testing

### Step 1: Validate the Policy
```powershell
python test_windows_policy.py
```
Expected output: All tests pass ✓

### Step 2: Preview Rule Conversion
```powershell
python windows_rule_converter.py
```
Shows what rules will be created on Windows

### Step 3: Install the Agent
```powershell
.\install_firewall_agent.ps1 -UserId "corp\admin" `
  -BackendUrl "http://10.65.42.253:5000"
```

### Step 4: Test Manual Activation
```powershell
# Check status
.\firewall_control.ps1 -Action STATUS

# Manually activate (for testing)
.\firewall_control.ps1 -Action ACTIVATE

# Manually deactivate
.\firewall_control.ps1 -Action DEACTIVATE
```

### Step 5: Activate via Web UI
1. Open your web UI: `http://10.65.42.253:5000`
2. Login with your user credentials
3. Find your Windows agent
4. Click "ACTIVATE" button
5. See rules applied within seconds

## Supported JSON Rule Features (Windows)

| Feature | Supported | Notes |
|---------|-----------|-------|
| L3 rules | ✓ Yes | IP-based filtering |
| L4 rules | ✓ Yes | Port-based filtering |
| TCP/UDP/ICMP | ✓ Yes | Protocol matching |
| Destination ports | ✓ Yes | Single or ranges |
| Ingress/Egress | ✓ Yes | Direction handling |
| Priority sorting | ✓ Yes | Higher priority first |
| Action: allow/deny | ✓ Yes | Maps to Allow/Block |
| Enabled flag | ✓ Yes | Filters disabled rules |
| L2 rules | ✗ No | Skipped (requires drivers) |
| Rate limiting | ✗ No | Windows has no native support |
| ARP inspection | ✗ No | L2, not supported |
| VLAN filtering | ✗ No | Requires advanced config |

## Verification

### Check if rules are applied:
```powershell
# List rules
Get-NetFirewallRule -Group "Enterprise-Hardening" | Select DisplayName, Direction, Action

# Count rules
(Get-NetFirewallRule -Group "Enterprise-Hardening").Count
```

### Check state:
```powershell
# View logged rule IDs
Get-Content C:\ProgramData\fw_state.json | ConvertFrom-Json

# View events
Get-EventLog -LogName Application -Source "Firewall-Escalation" -Newest 10
```

### View logs:
```powershell
# Agent log
Get-Content C:\Users\Public\Documents\firewall_1\agent.log -Tail 50
```

## Updating Firewall Rules

**No reinstallation needed!**

1. Edit `hybrid_firewall.json` on your backend/repo
2. Ensure the file is in `C:\Users\Public\Documents\firewall_1\`
3. Click "DEACTIVATE" then "ACTIVATE" from web UI
4. New rules are loaded and applied immediately

## Troubleshooting

### Problem: Firewall shows INACTIVE when it should be ACTIVE
```powershell
# Check if JSON exists
Test-Path C:\Users\Public\Documents\firewall_1\hybrid_firewall.json

# Check if rules in group
Get-NetFirewallRule -Group "Enterprise-Hardening" | Measure-Object

# Review logs
Get-Content C:\Users\Public\Documents\firewall_1\agent.log | tail -30
```

### Problem: Only some rules created
- Check JSON syntax: `python test_windows_policy.py`
- Verify rules have `"enabled": true`
- Verify `"layer"` is `L3` or `L4` (not `L2`)

### Problem: Rules not responding to ACTIVATE/DEACTIVATE
```powershell
# Test manually
.\firewall_control.ps1 -Action ACTIVATE

# Check agent is running
Get-Process | grep powershell

# Check backend connectivity
Test-NetConnection 10.65.42.253 -Port 5000
```

## Key Differences from Old System

| Old (Hardcoded) | New (JSON-Driven) |
|---|---|
| Ports hardcoded in script | Read from `hybrid_firewall.json` |
| IP blocking logic embedded | Rule-based filtering |
| Manual code changes to modify | Edit JSON, click ACTIVATE |
| No rule priority tracking | Rules sorted by priority |
| No rule state tracking | Active rules logged in state file |
| Windows-specific only | Shares rules with Linux via JSON |

## Architecture Benefits

1. **Centralized Management**: One JSON file for all agent types (Windows/Linux)
2. **Consistency**: Same rules enforced across Mac, Windows, Linux
3. **Flexibility**: Modify rules without code changes
4. **Reusability**: Converter can be adapted to other platforms
5. **Auditability**: All rules tracked in JSON with descriptions
6. **Scalability**: Apply 100+ rules to 1000+ agents instantly

## Next Steps

1. ✓ Validate policy with `test_windows_policy.py`
2. ✓ Test manual control with `firewall_control.ps1`
3. ✓ Activate from web UI to confirm integration
4. ✓ Document any custom rules your organization needs
5. ✓ Deploy to production agents

## Questions or Issues?

Refer to:
- `WINDOWS_FIREWALL_README.md` - Complete technical documentation
- `test_windows_policy.py` - Policy validation and debugging
- `windows_rule_converter.py` - See rule translations
- Windows Event Viewer - `Application > Firewall-Escalation` source

---

**Version**: 1.0  
**Created**: February 13, 2026  
**Component**: Windows Firewall Agent v5 (JSON-Driven)
