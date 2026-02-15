param(
    [ValidateSet("ACTIVATE","DEACTIVATE")]
    [string]$Mode = "ACTIVATE",
    [string]$LogFile = ""
)

function LogMsg([string]$msg) {
    Write-Host $msg
    if ($LogFile -and (Test-Path (Split-Path $LogFile))) {
        Add-Content -Path $LogFile -Value "$(Get-Date -Format o) [FW] $msg" -Encoding UTF8 -ErrorAction SilentlyContinue
    }
}

# ============================================================
# ENTERPRISE WINDOWS FIREWALL (STABLE JSON VERSION)
# ============================================================

$BaseDir    = "C:\Users\Public\Documents\firewall_1"
$JsonPath   = Join-Path $BaseDir "hybrid_firewall.json"
$RuleGroup  = "Enterprise-Hardening"
$EventSource = "Firewall-Escalation"
$StateFile  = "$env:ProgramData\fw_state.json"

# Ensure event source exists
if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    New-EventLog -LogName Application -Source $EventSource
}

# Ensure state file exists
if (!(Test-Path $StateFile)) {
    @{ active_rules=@() } | ConvertTo-Json | Out-File $StateFile -Encoding UTF8
}

$State = Get-Content $StateFile -Raw | ConvertFrom-Json

# ------------------------------------------------------------
# DEACTIVATE
# ------------------------------------------------------------

if ($Mode -eq "DEACTIVATE") {

    LogMsg "Removing firewall rules from group '$RuleGroup'"

    Get-NetFirewallRule -Group $RuleGroup -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue

    $State.active_rules = @()
    $State | ConvertTo-Json -Depth 3 | Out-File $StateFile -Encoding UTF8

    LogMsg "[OK] Firewall deactivated"

    Write-EventLog -LogName Application -Source $EventSource -EventId 5002 `
        -EntryType Information -Message "Enterprise firewall DEACTIVATED"

    Write-Output "Firewall deactivated"
    exit 0
}

# ------------------------------------------------------------
# ACTIVATE
# ------------------------------------------------------------

if (-not (Test-Path $JsonPath)) {
    Write-Error "Firewall policy file not found: $JsonPath"
    exit 1
}

try {

    $policy = Get-Content $JsonPath -Raw | ConvertFrom-Json
    LogMsg "Loaded firewall policy version $($policy.version)"

    $rules = $policy.rules | Where-Object {
        $_.enabled -and $_.layer -in @("L3","L4")
    }

    LogMsg "Found $($rules.Count) Windows-compatible rules"

    # Remove old rules (prevents stacking)
    Get-NetFirewallRule -Group $RuleGroup -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue

    $activeRules = @()

    foreach ($rule in ($rules | Sort-Object priority -Descending)) {

        # SAFETY: Skip dangerous blanket UDP block
        if ($rule.id -eq "deny_udp_ingress") {
            LogMsg "Skipped deny_udp_ingress (internet safety)"
            continue
        }

        $direction = switch ($rule.direction) {
            "egress"  { "Outbound" }
            "ingress" { "Inbound" }
            "both"    { "Inbound" }
            default   { "Inbound" }
        }

        $action = switch ($rule.action) {
            "allow" { "Allow" }
            "deny"  { "Block" }
            default { continue }
        }

        $params = @{
            DisplayName = "$($rule.description) [$($rule.id)]"
            Direction   = $direction
            Action      = $action
            Profile     = "Any"
            Group       = $RuleGroup
            Enabled     = "True"
        }

        if ($rule.match) {
            $match = $rule.match

            if ($match.protocol) {
                $params["Protocol"] = switch ($match.protocol.ToLower()) {
                    "tcp"  { "TCP" }
                    "udp"  { "UDP" }
                    "icmp" { "ICMPv4" }
                    default { "Any" }
                }
            }

            if ($match.dport) {
                if ($match.dport -is [array]) {
                    $params["LocalPort"] = ($match.dport -join ",")
                } else {
                    $params["LocalPort"] = $match.dport
                }
            }
        }

        try {
            New-NetFirewallRule @params | Out-Null
            $activeRules += $rule.id
            LogMsg "Applied rule $($rule.id)"
        }
        catch {
            LogMsg "Failed rule $($rule.id): $($_.Exception.Message)"
        }
    }

    $State.active_rules = $activeRules
    $State | ConvertTo-Json -Depth 3 | Out-File $StateFile -Encoding UTF8

    LogMsg "Firewall activated with $($activeRules.Count) rules"

    Write-EventLog -LogName Application -Source $EventSource -EventId 5000 `
        -EntryType Information `
        -Message "Enterprise firewall ACTIVATED with $($activeRules.Count) rules"

    Write-Output "Firewall activated with $($activeRules.Count) rules"

}
catch {
    Write-Error "Activation failed: $($_.Exception.Message)"
    exit 1
}
