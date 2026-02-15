# param(
#     [ValidateSet("ACTIVATE","DEACTIVATE")]
#     [string]$Mode = "ACTIVATE"
# )

# # ============================================================
# # ENTERPRISE WINDOWS FIREWALL v5 (JSON-DRIVEN)
# # Loads firewall rules from hybrid_firewall.json instead of hardcoding
# # ============================================================

# $BaseDir = "C:\Users\Public\Documents\firewall_1"
# $JsonPath = Join-Path $BaseDir "hybrid_firewall.json"
# $ConverterScript = Join-Path $BaseDir "json_to_windows_rules.ps1"
# $RuleGroup = "Enterprise-Hardening"
# $EventSource = "Firewall-Escalation"
# $StateFile = "$env:ProgramData\fw_state.json"

# # Validate JSON exists
# if (-not (Test-Path $JsonPath)) {
#     Write-Error "Firewall policy file not found: $JsonPath"
#     Write-EventLog -LogName Application -Source $EventSource -EventId 5001 -EntryType Error -Message "Firewall policy JSON not found"
#     exit 1
# }

# # Validate converter script exists
# if (-not (Test-Path $ConverterScript)) {
#     Write-Error "Converter script not found: $ConverterScript"
#     Write-EventLog -LogName Application -Source $EventSource -EventId 5001 -EntryType Error -Message "JSON converter script not found"
#     exit 1
# }

# # Ensure event source exists
# if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
#     New-EventLog -LogName Application -Source $EventSource
# }

# # Initialize state file
# if (!(Test-Path $StateFile)) {
#     @{ counters=@{}; blacklist=@{}; active_rules=@() } | ConvertTo-Json | Out-File $StateFile
# }

# $State = Get-Content $StateFile | ConvertFrom-Json
# $Now = Get-Date

# # ────────────────────────────────────────────────
# #  DEACTIVATE Logic
# # ────────────────────────────────────────────────

# if ($Mode -eq "DEACTIVATE") {
#     Get-NetFirewallRule -Group $RuleGroup -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
#     $State.active_rules = @()
#     $State | ConvertTo-Json | Out-File $StateFile
    
#     Write-EventLog -LogName Application -Source $EventSource -EventId 5002 -EntryType Information -Message "Enterprise firewall DEACTIVATED"
#     Write-Output "Firewall deactivated"
#     exit 0
# }

# # ────────────────────────────────────────────────
# #  ACTIVATE Logic - Load rules from JSON
# # ────────────────────────────────────────────────

# try {
#     # Load and parse JSON policy
#     $policy = Get-Content $JsonPath -Raw | ConvertFrom-Json
#     Write-Host "✓ Loaded hybrid firewall policy (v$($policy.version))" -ForegroundColor Cyan

#     # Extract L3/L4 rules (Windows only supports these via NetFirewallRule)
#     $applicableRules = $policy.rules | Where-Object { $_.enabled -and $_.layer -in @("L3", "L4") }
    
#     Write-Host "Found $($applicableRules.Count) applicable rules for Windows" -ForegroundColor Cyan

#     # Remove old rules
#     Get-NetFirewallRule -Group $RuleGroup -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue

#     $activeRules = @()

#     foreach ($rule in ($applicableRules | Sort-Object -Property priority -Descending)) {
        
#         $ruleParams = @{
#             DisplayName = "$($rule.description) [$($rule.id)]"
#             Direction   = if ($rule.direction -eq "egress") { "Outbound" } else { "Inbound" }
#             Action      = if ($rule.action -eq "allow") { "Allow" } else { "Block" }
#             Profile     = "Any"
#             Group       = $RuleGroup
#             Enabled     = $true
#             ErrorAction = "Continue"
#         }

#         # Parse match criteria
#         if ($rule.match) {
#             $match = $rule.match

#             # Protocol
#             if ($match.protocol) {
#                 $proto = switch ($match.protocol) {
#                     "tcp" { "TCP" }
#                     "udp" { "UDP" }
#                     "icmp" { "ICMP" }
#                     default { "TCP" }
#                 }
#                 $ruleParams["Protocol"] = $proto
#             }

#             # Destination ports
#             if ($match.dport) {
#                 if ($match.dport -is [array]) {
#                     $ruleParams["LocalPort"] = $match.dport -join ","
#                 } else {
#                     $ruleParams["LocalPort"] = $match.dport
#                 }
#             }

#             # Connection state (established connections)
#             if ($match.conntrack_state -and $match.conntrack_state -contains "ESTABLISHED") {
#                 $ruleParams["Direction"] = "Inbound"
#                 $ruleParams["Action"] = "Allow"
#             }
#         }

#         try {
#             New-NetFirewallRule @ruleParams | Out-Null
#             $activeRules += $rule.id
#             Write-Host "  ✓ $($rule.id): $($rule.description)" -ForegroundColor Green
#         } catch {
#             Write-Warning "  ✗ Failed to create rule '$($rule.id)': $($_.Exception.Message)"
#         }
#     }

#     $State.active_rules = $activeRules
#     $State | ConvertTo-Json | Out-File $StateFile

#     Write-EventLog -LogName Application -Source $EventSource -EventId 5000 -EntryType Information `
#         -Message "Enterprise firewall ACTIVATED with $($activeRules.Count) rules from JSON policy"
    
#     Write-Output "Firewall activated with $($activeRules.Count) rules"

# } catch {
#     Write-Error "Failed to activate firewall: $($_.Exception.Message)"
#     Write-EventLog -LogName Application -Source $EventSource -EventId 5001 -EntryType Error -Message "Firewall activation failed: $($_.Exception.Message)"
#     exit 1
# }
# param(
#     [ValidateSet("ACTIVATE","DEACTIVATE")]
#     [string]$Mode = "ACTIVATE"
# )

# $BaseDir = "C:\Users\Public\Documents\firewall_1"
# $JsonPath = Join-Path $BaseDir "hybrid_firewall.json"
# $RuleGroup = "Enterprise-Hardening"
# $EventSource = "Firewall-Escalation"
# $StateFile = "$env:ProgramData\fw_state.json"

# if (-not (Test-Path $JsonPath)) {
#     Write-Error "Firewall policy file not found: $JsonPath"
#     exit 1
# }

# if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
#     New-EventLog -LogName Application -Source $EventSource -ErrorAction SilentlyContinue
# }

# if (!(Test-Path $StateFile)) {
#     @{ active_rules=@() } | ConvertTo-Json | Out-File $StateFile -Force
# }

# $State = Get-Content $StateFile | ConvertFrom-Json

# if ($Mode -eq "DEACTIVATE") {
#     Write-Host "[DEACTIVATE] Starting firewall deactivation..." -ForegroundColor Yellow
    
#     try {
#         $rules = Get-NetFirewallRule -Group $RuleGroup -ErrorAction SilentlyContinue
        
#         if ($null -ne $rules -and $rules.Count -gt 0) {
#             Write-Host "[DEACTIVATE] Found $($rules.Count) rules to remove" -ForegroundColor Yellow
#             $rules | Remove-NetFirewallRule -ErrorAction Continue
#             Write-Host "[DEACTIVATE] All rules removed successfully" -ForegroundColor Green
#         } else {
#             Write-Host "[DEACTIVATE] No rules found (already deactivated)" -ForegroundColor Gray
#         }
        
#         $State.active_rules = @()
#         $State | ConvertTo-Json | Out-File $StateFile -Force
        
#         Write-Host "[DEACTIVATE] Firewall deactivated successfully" -ForegroundColor Green
#         exit 0
        
#     } catch {
#         Write-Host "[DEACTIVATE] ERROR: $($_.Exception.Message)" -ForegroundColor Red
#         exit 1
#     }
# }

# if ($Mode -eq "ACTIVATE") {
#     Write-Host "[ACTIVATE] Starting firewall activation..." -ForegroundColor Cyan
    
#     try {
#         $policy = Get-Content $JsonPath -Raw | ConvertFrom-Json
#         Write-Host "[ACTIVATE] Loaded policy version $($policy.version)" -ForegroundColor Cyan

#         $applicableRules = $policy.rules | Where-Object { $_.enabled -and $_.layer -in @("L3", "L4") }
        
#         Write-Host "[ACTIVATE] Found $($applicableRules.Count) rules to apply" -ForegroundColor Cyan

#         Get-NetFirewallRule -Group $RuleGroup -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue

#         $activeRules = @()

#         foreach ($rule in ($applicableRules | Sort-Object -Property priority -Descending)) {
            
#             $ruleParams = @{
#                 DisplayName = "$($rule.description) [$($rule.id)]"
#                 Direction   = if ($rule.direction -eq "egress") { "Outbound" } else { "Inbound" }
#                 Action      = if ($rule.action -eq "allow") { "Allow" } else { "Block" }
#                 Profile     = "Any"
#                 Group       = $RuleGroup
#                 Enabled     = $true
#                 ErrorAction = "Continue"
#             }

#             if ($rule.match) {
#                 $match = $rule.match

#                 if ($match.protocol) {
#                     $proto = switch ($match.protocol) {
#                         "tcp" { "TCP" }
#                         "udp" { "UDP" }
#                         "icmp" { "ICMP" }
#                         default { "TCP" }
#                     }
#                     $ruleParams["Protocol"] = $proto
#                 }

#                 if ($match.dport) {
#                     if ($match.dport -is [array]) {
#                         $ruleParams["LocalPort"] = $match.dport -join ","
#                     } else {
#                         $ruleParams["LocalPort"] = $match.dport
#                     }
#                 }
#             }

#             try {
#                 New-NetFirewallRule @ruleParams | Out-Null
#                 $activeRules += $rule.id
#                 Write-Host "[+] $($rule.id)" -ForegroundColor Green
#             } catch {
#                 Write-Warning "[-] Failed to create rule '$($rule.id)': $($_.Exception.Message)"
#             }
#         }

#         $State.active_rules = $activeRules
#         $State | ConvertTo-Json | Out-File $StateFile -Force

#         Write-Host "[ACTIVATE] Firewall activated with $($activeRules.Count) rules" -ForegroundColor Green
#         exit 0

#     } catch {
#         Write-Error "[ACTIVATE] Failed: $($_.Exception.Message)"
#         exit 1
#     }
# }


param(
    [ValidateSet("ACTIVATE","DEACTIVATE")]
    [string]$Mode = "ACTIVATE"
)

$BaseDir     = "C:\Users\Public\Documents\firewall_1"
$JsonPath    = Join-Path $BaseDir "hybrid_firewall.json"
$RuleGroup   = "Enterprise-Hardening"
$EventSource = "Firewall-Escalation"
$StateFile   = "$env:ProgramData\fw_state.json"

# -------------------------
# Validate JSON file
# -------------------------
if (-not (Test-Path $JsonPath)) {
    Write-Error "Firewall policy file not found: $JsonPath"
    exit 1
}

# -------------------------
# Ensure Event Source
# -------------------------
if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    New-EventLog -LogName Application -Source $EventSource -ErrorAction SilentlyContinue
}

# -------------------------
# Ensure State File Exists
# -------------------------
if (!(Test-Path $StateFile)) {
    @{ active_rules=@() } | ConvertTo-Json | Out-File $StateFile -Force
}

$State = Get-Content $StateFile -Raw | ConvertFrom-Json

# ==========================================================
# DEACTIVATE
# ==========================================================
if ($Mode -eq "DEACTIVATE") {

    Write-Host "[DEACTIVATE] Starting firewall deactivation..." -ForegroundColor Yellow

    try {
        $rules = Get-NetFirewallRule -Group $RuleGroup -ErrorAction SilentlyContinue

        if ($rules) {
            Write-Host "[DEACTIVATE] Removing $($rules.Count) rules..." -ForegroundColor Yellow
            $rules | Remove-NetFirewallRule -ErrorAction Continue
        }

        $State.active_rules = @()
        $State | ConvertTo-Json | Out-File $StateFile -Force

        Write-Host "[DEACTIVATE] Firewall deactivated successfully" -ForegroundColor Green
        exit 0
    }
    catch {
        Write-Error "[DEACTIVATE] ERROR: $($_.Exception.Message)"
        exit 1
    }
}

# ==========================================================
# ACTIVATE
# ==========================================================
if ($Mode -eq "ACTIVATE") {

    Write-Host "[ACTIVATE] Starting firewall activation..." -ForegroundColor Cyan

    try {
        $policy = Get-Content $JsonPath -Raw | ConvertFrom-Json

        # Support BOTH JSON formats:
        # 1. { "rules": [ ... ] }
        # 2. [ ... ]
        if ($policy.rules) {
            $rules = $policy.rules
        } else {
            $rules = $policy
        }

        $applicableRules = $rules | Where-Object {
            $_.enabled -eq $true -and $_.layer -in @("L3","L4")
        }

        Write-Host "[ACTIVATE] Found $($applicableRules.Count) rules to apply" -ForegroundColor Cyan

        # Remove previous rules
        Get-NetFirewallRule -Group $RuleGroup -ErrorAction SilentlyContinue |
            Remove-NetFirewallRule -ErrorAction SilentlyContinue

        $activeRules = @()

        foreach ($rule in ($applicableRules | Sort-Object priority -Descending)) {

            $ruleParams = @{
                DisplayName = "$($rule.description) [$($rule.id)]"
                Direction   = if ($rule.direction -eq "egress") { "Outbound" } else { "Inbound" }
                Action      = if ($rule.action -eq "allow") { "Allow" } else { "Block" }
                Profile     = "Any"
                Group       = $RuleGroup
                ErrorAction = "Stop"
            }

            # -------------------------
            # Protocol Handling
            # -------------------------
            if ($rule.match.protocol) {
                $ruleParams["Protocol"] = $rule.match.protocol.ToUpper()
            }

            # -------------------------
            # Port Handling (dport OR dst_port)
            # -------------------------
            if ($rule.match.dport) {
                $ruleParams["LocalPort"] = ($rule.match.dport -join ",")
            }
            elseif ($rule.match.dst_port) {
                $ruleParams["LocalPort"] = $rule.match.dst_port
            }

            try {
                # IMPORTANT: Removed -Enabled parameter (fix)
                New-NetFirewallRule @ruleParams | Out-Null

                $activeRules += $rule.id
                Write-Host "[+] Applied: $($rule.id)" -ForegroundColor Green
            }
            catch {
                Write-Warning "[-] Failed to create rule '$($rule.id)': $($_.Exception.Message)"
            }
        }

        # Update state safely
        $State.active_rules = $activeRules
        $State | ConvertTo-Json | Out-File $StateFile -Force

        Write-Host "[ACTIVATE] Firewall activated with $($activeRules.Count) rules" -ForegroundColor Green
        exit 0
    }
    catch {
        Write-Error "[ACTIVATE] Failed: $($_.Exception.Message)"
        exit 1
    }
}
