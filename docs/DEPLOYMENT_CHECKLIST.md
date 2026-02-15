# Deployment Checklist

## Pre-Deployment Validation

### Step 1: Verify All Files Exist
- [ ] `hybrid_firewall.json` - Rule definitions
- [ ] `windows_firewall.ps1` - Updated main script
- [ ] `install_firewall_agent.ps1` - Updated installer
- [ ] `json_to_windows_rules.ps1` - Converter module (NEW)
- [ ] `firewall_control.ps1` - Manual control tool (NEW)
- [ ] `window_backend.py` - Backend API
- [ ] `window_agent.ps1` - Should exist after installation

### Step 2: Test JSON Policy
```powershell
python test_windows_policy.py
```
- [ ] Policy structure valid
- [ ] All ports valid (0-65535)
- [ ] All priorities valid
- [ ] Windows-applicable rules > 0
- [ ] No conversion errors

Expected output: `All tests passed!`

### Step 3: Preview Rule Conversion
```powershell
python windows_rule_converter.py
```
- [ ] Shows expected rule count
- [ ] All rules convert correctly
- [ ] No unexpected skipped rules
- [ ] Protocol mappings correct

### Step 4: Validate Installer
```powershell
# Check installer reads JSON
Get-Content install_firewall_agent.ps1 | Select-String "JsonPolicyPath"
```
- [ ] Installer copies JSON file
- [ ] Installer copies converter script
- [ ] Updated firewall script is embedded

## Test Environment (Single Machine)

### Step 5: Test Fresh Installation
```powershell
.\install_firewall_agent.ps1 -UserId "test_user" `
  -BackendUrl "http://10.65.42.253:5000"
```
- [ ] Installation completes without errors
- [ ] Copies JSON to install directory
- [ ] Copies converter script
- [ ] Creates scheduled task
- [ ] Starts scheduled task

### Step 6: Verify Installation
```powershell
# Check files copied
Test-Path C:\Users\Public\Documents\firewall_1\hybrid_firewall.json
Test-Path C:\Users\Public\Documents\firewall_1\json_to_windows_rules.ps1

# Check task created
Get-ScheduledTask -TaskName "*EnterpriseFirewall*"

# Check task is running
Get-ScheduledTask -TaskName "*EnterpriseFirewall*" | Select State
```
- [ ] JSON file exists in install directory
- [ ] Converter script exists in install directory
- [ ] Scheduled task exists
- [ ] Scheduled task state is Running

### Step 7: Check Agent Registration
```powershell
# Wait 10 seconds, then check logs
Start-Sleep -Seconds 10
Get-Content C:\Users\Public\Documents\firewall_1\agent.log | Select-String "Registered"
```
- [ ] Agent registered with backend
- [ ] No connection errors in log
- [ ] Agent ID logged
- [ ] User ID logged

### Step 8: Test Manual Activation
```powershell
.\firewall_control.ps1 -Action ACTIVATE
```
- [ ] Script executes without errors
- [ ] Rules are created
- [ ] Count > 0: `(Get-NetFirewallRule -Group "Enterprise-Hardening").Count`

```powershell
Get-EventLog -LogName Application -Source "Firewall-Escalation" -Newest 1
```
- [ ] Event ID 5000 (ACTIVATED) in event log
- [ ] Message shows rule count

### Step 9: Test Web UI Activation
From web UI:
- [ ] Login successful
- [ ] Agent appears in list with status "connected"
- [ ] Click "DEACTIVATE" → Rules removed
- [ ] Check: `(Get-NetFirewallRule -Group "Enterprise-Hardening").Count` = 0
- [ ] Click "ACTIVATE" → Rules reapplied
- [ ] Check: `(Get-NetFirewallRule -Group "Enterprise-Hardening").Count` > 0
- [ ] Web UI shows ✓ ACTIVE

### Step 10: Test Manual Deactivation
```powershell
.\firewall_control.ps1 -Action DEACTIVATE
```
- [ ] Script executes
- [ ] Rules are removed
- [ ] Count = 0: `(Get-NetFirewallRule -Group "Enterprise-Hardening").Count`

```powershell
Get-EventLog -LogName Application -Source "Firewall-Escalation" -Newest 1
```
- [ ] Event ID 5002 (DEACTIVATED) in event log

## Beta Deployment (Multiple Machines)

### Step 11: Deploy to 3-5 Test Machines
For each test machine:
- [ ] Run installer script
- [ ] Verify agent registers
- [ ] Test ACTIVATE/DEACTIVATE
- [ ] Verify event logging
- [ ] Monitor logs for 5 minutes
- [ ] Document any issues

### Step 12: Monitor Test Environment
- [ ] All agents connecting
- [ ] No errors in logs after 1 hour
- [ ] Rules staying active after ACTIVATE
- [ ] Rules removed cleanly after DEACTIVATE
- [ ] No event viewer errors

### Step 13: Test Policy Update Cycle
1. [ ] Edit `hybrid_firewall.json` (add/remove a rule)
2. [ ] Copy updated JSON to test machines
3. [ ] Click DEACTIVATE in web UI
4. [ ] Click ACTIVATE in web UI
5. [ ] Verify new rule appears
6. [ ] Check rule count increased/decreased

## Production Deployment

### Step 14: Prepare Deployment Package
- [ ] Create installer package with all files
- [ ] Create deployment documentation
- [ ] Create rollback procedure
- [ ] Notify stakeholders
- [ ] Schedule deployment window

### Step 15: Pre-Deployment Checklist
- [ ] All test environments passing
- [ ] No outstanding issues in test logs
- [ ] Rollback procedure tested
- [ ] Admin approval obtained
- [ ] Monitoring enabled (Event Viewer access)
- [ ] Support team trained

### Step 16: Deploy to Production (Phase 1)
- [ ] Select small subset (5-10% of machines)
- [ ] Deploy installer
- [ ] Monitor for 30 minutes minimum
- [ ] Check:
  - [ ] All agents registered
  - [ ] No error events
  - [ ] Logs normal
  - [ ] Rules applied correctly

### Step 17: Deploy to Production (Phase 2)
- [ ] Deploy to next batch (25% total)
- [ ] Monitor for 1 hour
- [ ] Check same items as Phase 1

### Step 18: Deploy to Production (Phase 3)
- [ ] Deploy to remaining machines (100%)
- [ ] Continuous monitoring for 24 hours
- [ ] Prepare incident response if issues arise

## Post-Deployment

### Step 19: Verification Run
```powershell
# Run validation across sample of machines
for endpoint in @(sample of machines) {
    $rules = (Get-NetFirewallRule -Group "Enterprise-Hardening").Count
    if ($rules -eq 0) {
        Write-Host "WARNING: $endpoint has 0 rules"
    }
}
```
- [ ] All machines have rule count > 0
- [ ] No machines showing INACTIVE
- [ ] No error events in event log

### Step 20: Documentation Update
- [ ] Update deployment runbook
- [ ] Document any custom configurations
- [ ] Add troubleshooting guides for new issues
- [ ] Archive this checklist with deployment date

### Step 21: Training & Handoff
- [ ] Train ops team on manual controls
- [ ] Share documentation
- [ ] Practice emergency procedures
- [ ] Set up monitoring alerts

### Step 22: Long-Term Monitoring
- [ ] Monitor event logs for 1 week
- [ ] Monitor for any performance impact
- [ ] Collect feedback from users
- [ ] Prepare for next phase (Linux parity, more rules, etc.)

## Rollback Plan (If Needed)

### Emergency Disable
```powershell
# On each machine
Get-NetFirewallRule -Group "Enterprise-Hardening" | Remove-NetFirewallRule -Force

# Or via web UI
Click DEACTIVATE button
```
- [ ] Takes ~30 seconds per machine
- [ ] All rules removed
- [ ] System access restored
- [ ] No data loss

### Full Rollback
If installer has issues:
```powershell
# Stop scheduled task
Stop-ScheduledTask -TaskName "*EnterpriseFirewall*"

# Remove JSON files
Remove-Item C:\Users\Public\Documents\firewall_1\*.json

# Restore from backup if needed
```

## Sign-Off

| Role | Approval | Date |
|---|---|---|
| Test Lead | [ ] Approved | _____ |
| Infrastructure Manager | [ ] Approved | _____ |
| Security Officer | [ ] Approved | _____ |
| Project Manager | [ ] Approved | _____ |

## Deployment Notes

**Date Deployed**: __________

**Deployed By**: __________

**Machines Count**: __________

**Issues Encountered**: 
```
_______________________________________________
_______________________________________________
_______________________________________________
```

**Resolution Applied**:
```
_______________________________________________
_______________________________________________
_______________________________________________
```

**Post-Deployment Notes**:
```
_______________________________________________
_______________________________________________
_______________________________________________
```

---

## Quick Reference During Deployment

**Fast Activation Test**:
```powershell
.\firewall_control.ps1 -Action ACTIVATE
(Get-NetFirewallRule -Group "Enterprise-Hardening").Count
```

**Fast Deactivation Test**:
```powershell
.\firewall_control.ps1 -Action DEACTIVATE
(Get-NetFirewallRule -Group "Enterprise-Hardening").Count
```

**Emergency Disable All**:
```powershell
Get-NetFirewallRule -Group "Enterprise-Hardening" | Remove-NetFirewallRule -Force
```

**Check Status**:
```powershell
.\firewall_control.ps1 -Action STATUS
```

---

**Status**: ✓ Ready for deployment

**Total Effort**: ~4-6 hours (single machine test → production)

**Risk Level**: Low (no production systems affected during test phase)

Good luck with deployment! 🚀
