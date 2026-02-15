# Windows Firewall Agent with JSON-Driven Rules

## Overview

This Windows firewall agent now uses the **`hybrid_firewall.json`** configuration file to load firewall rules instead of hardcoding them. This allows centralized rule management and consistency between Windows and Linux agents.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Web UI (window_backend.py)                             │
│  - User sends ACTIVATE/DEACTIVATE command               │
│  - Stores pending_cmd in firewall_agents.json          │
└──────────────────┬──────────────────────────────────────┘
                   │ /api/agent/command
                   ▼
┌─────────────────────────────────────────────────────────┐
│  Window Agent (window_agent.ps1)                        │
│  - Polls backend for commands                          │
│  - Executes windows_firewall.ps1 with ACTIVATE/DEACTIVATE
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│  Windows Firewall Script (windows_firewall.ps1)         │
│  - Reads hybrid_firewall.json                           │
│  - Parses ACTIVATE/DEACTIVATE mode                      │
│  - Converts JSON rules to New-NetFirewallRule commands │
│  - Applies rules to Windows Firewall                   │
└─────────────────────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│  Windows Firewall (NetFirewallRule)                     │
│  - Rules grouped under "Enterprise-Hardening"          │
│  - Rules sorted by priority                            │
└─────────────────────────────────────────────────────────┘
```

## Files Modified/Created

| File | Purpose |
|------|---------|
| `windows_firewall.ps1` | **UPDATED**: Now reads from `hybrid_firewall.json` instead of hardcoding rules |
| `json_to_windows_rules.ps1` | **NEW**: PowerShell module to convert JSON rules to Windows firewall format |
| `windows_rule_converter.py` | **NEW**: Python script to preview rule conversions |
| `install_firewall_agent.ps1` | **UPDATED**: Copies JSON and converter scripts during installation |
| `hybrid_firewall.json` | JSON policy file with all firewall rules (not modified) |

## How It Works

### 1. Rule Loading
When the firewall agent receives an `ACTIVATE` command:
1. Reads `hybrid_firewall.json`
2. Filters for enabled rules with L3/L4 layers (Windows doesn't support L2 rules via NetFirewallRule)
3. Skips L2 rules (those would need specialized drivers or ebtables)

### 2. Rule Conversion
For each applicable rule, it converts:

| JSON Field | Windows Interpretation |
|------------|----------------------|
| `action: "allow"` | `-Action Allow` |
| `action: "deny"` | `-Action Block` |
| `direction: "ingress"` | `-Direction Inbound` |
| `direction: "egress"` | `-Direction Outbound` |
| `protocol: "tcp"` | `-Protocol TCP` |
| `dport: [22, 80, 443]` | `-LocalPort "22,80,443"` |
| `match.conntrack_state: ["ESTABLISHED"]` | `-Direction Inbound -Action Allow` |

### 3. Rule Application
```powershell
# Removes old rules
Get-NetFirewallRule -Group "Enterprise-Hardening" | Remove-NetFirewallRule

# Creates new rules sorted by priority
foreach ($rule in $applicableRules | Sort-Object priority -Descending) {
    New-NetFirewallRule @params -Group "Enterprise-Hardening"
}
```

### 4. Web UI Control
From the web UI at `http://10.65.42.253:5000`:
1. **ACTIVATE button** → Sets `pending_cmd = "ACTIVATE"`
2. **DEACTIVATE button** → Sets `pending_cmd = "DEACTIVATE"`
3. Agent polls `/api/agent/command` and receives the command
4. Executes: `powershell -NoProfile -ExecutionPolicy Bypass -File windows_firewall.ps1 -Mode ACTIVATE`

## Rule Mapping Examples

### Example 1: Allow SSH
```json
{
  "id": "allow_tcp_well_known_ports",
  "enabled": true,
  "action": "allow",
  "layer": "L3",
  "direction": "ingress",
  "match": { "protocol": "tcp", "dport": [22, 80, 443] },
  "description": "Allow SSH (22), HTTP (80) and HTTPS (443)",
  "priority": 180
}
```
↓ Converts to ↓
```powershell
New-NetFirewallRule -DisplayName "Allow SSH (22), HTTP (80) and HTTPS (443) [allow_tcp_well_known_ports]" `
    -Direction Inbound -Action Allow -Protocol TCP -LocalPort "22,80,443" `
    -Group "Enterprise-Hardening" -Profile Any -Enabled $true
```

### Example 2: Block ICMP
```json
{
  "id": "drop_icmp_echo",
  "enabled": true,
  "action": "deny",
  "layer": "L3",
  "direction": "ingress",
  "match": { "protocol": "icmp", "icmp_type": "echo-request" },
  "description": "Drop ICMP echo requests (ping)",
  "priority": 170
}
```
↓ Converts to ↓
```powershell
New-NetFirewallRule -DisplayName "Drop ICMP echo requests (ping) [drop_icmp_echo]" `
    -Direction Inbound -Action Block -Protocol ICMP `
    -Group "Enterprise-Hardening" -Profile Any -Enabled $true
```

## Installation

The installer (`install_firewall_agent.ps1`) now:
1. Copies `hybrid_firewall.json` to the install directory
2. Copies `json_to_windows_rules.ps1` to the install directory
3. Creates the updated `windows_firewall.ps1` with JSON support
4. Sets up scheduled tasks for automatic activation

```powershell
.\install_firewall_agent.ps1 -UserId "corp\admin" -BackendUrl "http://10.65.42.253:5000"
```

## Activation Flow from Web UI

1. **User clicks "ACTIVATE" button** in web UI
   - Sends: `POST /api/user/firewall` with `cmd: "ACTIVATE"`
   
2. **Backend stores command**
   ```python
   agent["pending_cmd"] = "ACTIVATE"
   agent["last_toggle"] = time.time()
   ```

3. **Windows agent polls**
   ```powershell
   $resp = Invoke-RestMethod "$Backend/api/agent/command" -Method Post
   # Receives: { "cmd": "ACTIVATE" }
   ```

4. **Agent executes firewall script**
   ```powershell
   & powershell -NoProfile -ExecutionPolicy Bypass -File windows_firewall.ps1 -Mode ACTIVATE
   ```

5. **Firewall script loads JSON and applies rules**
   - Reads `hybrid_firewall.json`
   - Converts rules to `New-NetFirewallRule` commands
   - Group all rules under "Enterprise-Hardening"
   - Returns firewall state: `ACTIVE`

6. **Agent reports back to backend**
   ```powershell
   $state = Get-NetFirewallState  # Check if rules are present
   Invoke-RestMethod "$Backend/api/agent/heartbeat" `
       -Body @{ firewall = "ACTIVE" }
   ```

7. **Web UI updates**
   - Shows firewall status: ✓ ACTIVE
   - Button state changes accordingly

## Verification

### Check if rules are applied:
```powershell
# List all firewall rules in the Enterprise-Hardening group
Get-NetFirewallRule -Group "Enterprise-Hardening" | Select-Object DisplayName, Direction, Action

# Check state file
Get-Content "C:\ProgramData\fw_state.json" | ConvertFrom-Json | Select-Object active_rules
```

### View logs:
```powershell
# Agent log
Get-Content "C:\Users\Public\Documents\firewall_1\agent.log" -Tail 20

# Windows Event Viewer
Get-EventLog -LogName Application -Source "Firewall-Escalation" -Newest 10
```

## How to Modify Rules

1. **Edit the JSON file**
   ```json
   {
     "id": "my_custom_rule",
     "enabled": true,
     "action": "allow",
     "layer": "L4",
     "direction": "ingress",
     "match": { "protocol": "tcp", "dport": 8080 },
     "description": "Allow custom app on port 8080",
     "priority": 175
   }
   ```

2. **Push to agents** via web UI (ACTIVATE/DEACTIVATE)
   - No need to reinstall agents
   - Rules update automatically on next activation

## Supported Rule Types

✅ **Supported (Convert to Windows rules)**
- L3 rules (IP-based filtering)
- L4 rules (Port-based filtering)
- TCP/UDP/ICMP protocols
- Destination port ranges
- Connection state tracking (ESTABLISHED)
- Ingress/Egress directions

❌ **Not Supported (Skipped by Windows agent)**
- L2 rules (MAC filtering, ARP inspection) - requires specialized drivers
- VLAN filtering - requires advanced Windows firewall configuration
- Rate limiting - Windows firewall doesn't support this natively
- Escalation rules - handled by Linux agents with ebtables/automation

## Troubleshooting

### Problem: Rules not applying
```powershell
# Check if JSON file exists
Test-Path "C:\Users\Public\Documents\firewall_1\hybrid_firewall.json"

# Check agent logs
Get-Content "C:\Users\Public\Documents\firewall_1\agent.log" -Tail 50

# Check event logs
Get-EventLog -LogName Application -Source "Firewall-Escalation" -Newest 20
```

### Problem: Only some rules created
- Check that rules have `"enabled": true` in JSON
- Check `"layer"` is `"L3"` or `"L4"` (not `L2`)
- Verify `"action"` is `"allow"`, `"deny"`, or `"rate-limit"`

### Problem: Firewall state shows INACTIVE when it should be ACTIVE
```powershell
# Check if rules exist
Get-NetFirewallRule -Group "Enterprise-Hardening" | Measure-Object

# If 0 rules, the activation failed - check logs
Get-Content "C:\Users\Public\Documents\firewall_1\agent.log" | Select-String "ERROR|Failed"
```

## Converting to Python (Optional)

For testing or advanced rule manipulation:
```bash
python windows_rule_converter.py
```

This shows what rules would be converted to Windows format.

## Security Notes

1. **Rule Group**: All rules are grouped under `Enterprise-Hardening`
   - Easy to remove all rules: `Get-NetFirewallRule -Group Enterprise-Hardening | Remove-NetFirewallRule`
   - Prevents conflicts with user rules

2. **Priority Ordering**: Rules are applied in descending priority order
   - Higher priority rules take precedence

3. **State Tracking**: Active rule IDs stored in `$env:ProgramData\fw_state.json`
   - Used to track which rules are currently active
   - Cleared on DEACTIVATE

4. **Logging**: All firewall changes logged to Windows Event Log
   - Event ID 5000: ACTIVATE
   - Event ID 5001: ERROR
   - Event ID 5002: DEACTIVATE
