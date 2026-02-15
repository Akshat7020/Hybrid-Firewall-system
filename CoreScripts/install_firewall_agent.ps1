# =============================================================================
#  All-in-One Firewall Agent Installer - firewall_1 version
#  Path: C:\Users\Public\Documents\firewall_1
# =============================================================================

param(
    [string]$BackendUrl = "http://10.144.164.253:5000",
    [string]$InstallDirectory = "C:\Users\Public\Documents\firewall_1",
    [string]$UserId = ""
)

$ErrorActionPreference = "Stop"

# ────────────────────────────────────────────────
#  Parameter Validation & Sanitization
# ────────────────────────────────────────────────

# Ensure InstallDirectory defaults properly
if (-not $InstallDirectory -or $InstallDirectory.Trim() -eq '') {
    $InstallDirectory = "C:\Users\Public\Documents\firewall_1"
}

# Only validate parameters if they look suspicious (swapped positional vs named)
# Check if BackendUrl looks like a directory path (indicates parameter swap)
if ($BackendUrl -and ($BackendUrl -match '^[A-Z]:\\' -or $BackendUrl -match '^\\\\')) {
    Write-Host "ERROR: BackendUrl appears to be a directory path, not a URL. Did you swap the parameters?" -ForegroundColor Red
    Write-Host "  Expected: -BackendUrl 'http://...' -InstallDirectory 'C:\path\...'" -ForegroundColor Yellow
    exit 1
}

# Check if InstallDirectory looks like a URL (indicates parameter swap)
if ($InstallDirectory -and ($InstallDirectory -match '^https?://' -or $InstallDirectory -match '^ftp://')) {
    Write-Host "ERROR: InstallDirectory appears to be a URL. Did you swap -BackendUrl and -InstallDirectory?" -ForegroundColor Red
    Write-Host "  Expected: -BackendUrl 'http://...' -InstallDirectory 'C:\path\...'" -ForegroundColor Yellow
    exit 1
}

# ────────────────────────────────────────────────
#  Configuration (parameters override defaults)
# ────────────────────────────────────────────────

$TaskName         = "EnterpriseFirewallAgent_Firewall1"

if (-not $UserId -or $UserId.Trim() -eq '') {
    $UserIdPath = Join-Path "$InstallDirectory" "user_id.txt"
    if (Test-Path "$UserIdPath") {
        $UserId = (Get-Content $UserIdPath -Raw).Trim()
        Write-Host "Using existing user ID: $UserId" -ForegroundColor Cyan
    } else {
        # Prefer a human-friendly ID: username@hostname. Fall back to a GUID if necessary.
        if ($env:USERNAME -and $env:COMPUTERNAME) {
            $UserId = "$($env:USERNAME)@$($env:COMPUTERNAME)"
        } else {
            $UserId = [guid]::NewGuid().ToString()
        }
        if (-not (Test-Path "$InstallDirectory")) { New-Item -ItemType Directory -Path "$InstallDirectory" -Force | Out-Null }
        Set-Content -Path "$UserIdPath" -Value $UserId -Encoding UTF8
        Write-Host "Generated new user ID: $UserId" -ForegroundColor Cyan
    }
} else {
    # persist provided UserId
    if (-not (Test-Path "$InstallDirectory")) { New-Item -ItemType Directory -Path "$InstallDirectory" -Force | Out-Null }
    Set-Content -Path (Join-Path "$InstallDirectory" "user_id.txt") -Value $UserId -Encoding UTF8
    Write-Host "Using provided user ID: $UserId" -ForegroundColor Cyan
}

# ────────────────────────────────────────────────
#  Prepare paths
# ────────────────────────────────────────────────

if (-not (Test-Path "$InstallDirectory")) {
    New-Item -ItemType Directory -Path "$InstallDirectory" -Force | Out-Null
    Write-Host "Created directory: $InstallDirectory" -ForegroundColor Green
}

$AgentScriptPath    = Join-Path "$InstallDirectory" "window_agent.ps1"
$FirewallScriptPath = Join-Path "$InstallDirectory" "windows_firewall.ps1"
$JsonPolicyPath     = Join-Path "$InstallDirectory" "hybrid_firewall.json"
$ConverterPath      = Join-Path "$InstallDirectory" "json_to_windows_rules.ps1"
$AgentIdPath        = Join-Path "$InstallDirectory" "agent_id.txt"
$LogFile            = Join-Path "$InstallDirectory" "agent.log"

# ────────────────────────────────────────────────
#  Agent ID
# ────────────────────────────────────────────────

if (-not (Test-Path "$AgentIdPath")) {
    $AgentId = [guid]::NewGuid().ToString()
    Set-Content -Path "$AgentIdPath" -Value $AgentId -Encoding UTF8
    Write-Host "New agent ID created: $AgentId" -ForegroundColor Cyan
} else {
    $AgentId = (Get-Content $AgentIdPath -Raw).Trim()
    Write-Host "Using existing agent ID: $AgentId" -ForegroundColor Cyan
}

# ────────────────────────────────────────────────
#  Write window_agent.ps1
# ────────────────────────────────────────────────

$agentContent = @"
`$ErrorActionPreference = "Stop"
`$ProgressPreference = "SilentlyContinue"

`$Backend = "$BackendUrl"
`$BaseDir = "C:\Users\Public\Documents\firewall_1"
`$IdFile  = "`$BaseDir\agent_id.txt"
`$LogFile = "`$BaseDir\agent.log"
`$FwScript = "`$BaseDir\windows_firewall.ps1"

if (!(Test-Path `$BaseDir)) {
    New-Item -ItemType Directory `$BaseDir -Force | Out-Null
}

function Log(`$msg) {
    Add-Content -Path `$LogFile -Value "`$(Get-Date -Format o) `$msg" -Encoding UTF8
}

if (!(Test-Path `$FwScript)) {
    Log "CRITICAL: Firewall script missing at `$FwScript"
    exit 1
}

`$AgentId = (Get-Content `$IdFile -Raw -ErrorAction SilentlyContinue).Trim()
if (!`$AgentId) {
    `$AgentId = [guid]::NewGuid().ToString()
    Set-Content `$IdFile `$AgentId
    Log "Generated Agent ID: `$AgentId"
}

function Get-FirewallState {
    try {
        `$rules = Get-NetFirewallRule -Group "Enterprise-Hardening" -ErrorAction SilentlyContinue
        if (`$rules -and `$rules.Count -gt 0) { return "ACTIVE" }
        return "INACTIVE"
    } catch {
        return "UNKNOWN"
    }
}

Log "Agent started | ID: `$AgentId | Backend: `$Backend"

while (`$true) {
    try {
        # REGISTER
        Invoke-RestMethod "`$Backend/api/agent/register" -Method Post -ContentType "application/json" -Body (@{
            agent_id = `$AgentId
            os_type  = "windows"
        } | ConvertTo-Json -Compress)

        Log "Registered"

        while (`$true) {

            `$resp = Invoke-RestMethod "`$Backend/api/agent/command" -Method Post -ContentType "application/json" -Body (@{
                agent_id = `$AgentId
            } | ConvertTo-Json -Compress)

            if (`$resp.cmd -in @("ACTIVATE","DEACTIVATE")) {

                Log "Executing `$(`$resp.cmd)"

                try {
                    & powershell -NoProfile -ExecutionPolicy Bypass -File `$FwScript -Mode `$resp.cmd -LogFile `$LogFile
                    Log "Firewall command executed successfully"
                }
                catch {
                    Log "Firewall execution failed: `$(`$_.Exception.Message)"
                }
            }

            `$state = Get-FirewallState

            Invoke-RestMethod "`$Backend/api/agent/heartbeat" -Method Post -ContentType "application/json" -Body (@{
                agent_id = `$AgentId
                firewall = `$state
            } | ConvertTo-Json -Compress)

            Start-Sleep -Seconds 5
        }

    } catch {
        Log "Connection error: `$(`$_.Exception.Message)"
        Start-Sleep -Seconds 10
    }
}
"@


Set-Content -Path "$AgentScriptPath" -Value $agentContent -Encoding UTF8
Write-Host "Created/updated agent script → $AgentScriptPath" -ForegroundColor Green

# Request / create a per-user token from backend and save it locally
try {
    $resp = Invoke-RestMethod "$BackendUrl/api/user/init" -Method Post -ContentType "application/json" -Body (@{ user_id = $UserId } | ConvertTo-Json -Compress)
    if ($resp -and $resp.token) {
        $UserTokenPath = Join-Path "$InstallDirectory" "user_token.txt"
        Set-Content -Path "$UserTokenPath" -Value $resp.token -Encoding UTF8
        Write-Host "Saved user token to: $UserTokenPath" -ForegroundColor Green
        Write-Host "User token: $($resp.token)" -ForegroundColor Magenta
        Write-Host "Keep this token private. It is required to view and control your agent via the web UI." -ForegroundColor Yellow
    } else {
        Write-Host "Warning: did not receive token from backend" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Warning: failed to request user token: $($_.Exception.Message)" -ForegroundColor Yellow
}

# ────────────────────────────────────────────────
#  Copy JSON policy and converter script
# ────────────────────────────────────────────────

$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

# Copy hybrid_firewall.json
$sourceJson = Join-Path "$ScriptDirectory" "hybrid_firewall.json"
if (Test-Path "$sourceJson") {
    Copy-Item -Path "$sourceJson" -Destination "$JsonPolicyPath" -Force
    Write-Host "Copied firewall policy: $JsonPolicyPath" -ForegroundColor Green
} else {
    # Fallback: try to find it in the workspace Config Files directory
    $workspaceJson = "c:\Users\Public\Documents\firewall_1\Config Files\hybrid_firewall.json"
    if (Test-Path "$workspaceJson") {
        Copy-Item -Path "$workspaceJson" -Destination "$JsonPolicyPath" -Force
        Write-Host "Copied firewall policy from workspace: $JsonPolicyPath" -ForegroundColor Green
    } else {
        Write-Host "Warning: hybrid_firewall.json not found. Place it at: $JsonPolicyPath" -ForegroundColor Yellow
    }
}

# Copy json_to_windows_rules.ps1 converter
$sourceConverter = Join-Path "$ScriptDirectory" "json_to_windows_rules.ps1"
if (Test-Path "$sourceConverter") {
    Copy-Item -Path "$sourceConverter" -Destination "$ConverterPath" -Force
    Write-Host "Copied converter script: $ConverterPath" -ForegroundColor Green
} else {
    Write-Host "Warning: json_to_windows_rules.ps1 not found. Create it or place in $InstallDirectory" -ForegroundColor Yellow
}

# ────────────────────────────────────────────────
#  Write windows_firewall.ps1
# ────────────────────────────────────────────────

$fwContent = @'
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
'@


Set-Content -Path "$FirewallScriptPath" -Value $fwContent -Encoding UTF8
Write-Host "Created/updated firewall helper → $FirewallScriptPath" -ForegroundColor Green

# ────────────────────────────────────────────────
#  Scheduled Task
# ────────────────────────────────────────────────

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Removed old task" -ForegroundColor Yellow
}

$action = New-ScheduledTaskAction `
    -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$AgentScriptPath`""

$triggers = @(
    (New-ScheduledTaskTrigger -AtStartup),
    (New-ScheduledTaskTrigger -AtLogOn -User "SYSTEM"),
    (New-ScheduledTaskTrigger -Daily -At "00:05")
)

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -RestartCount 999 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Hours 0) `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $triggers `
    -Principal $principal `
    -Settings $settings `
    -Force | Out-Null

Write-Host "Scheduled task created: $TaskName" -ForegroundColor Green

try {
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "Task started successfully" -ForegroundColor Green
} catch {
    Write-Host "Task will start after reboot" -ForegroundColor Yellow
}

# ────────────────────────────────────────────────
#  Summary
# ────────────────────────────────────────────────

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Installation finished" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════"
Write-Host ""
Write-Host "  Agent ID     : $AgentId"
Write-Host "  User ID      : $UserId"
Write-Host "  Folder       : $InstallDirectory"
Write-Host "  Log file     : $LogFile"
Write-Host "  Task name    : $TaskName"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Disable Fast Startup (important for auto-start):"
Write-Host "     Control Panel → Power Options → Choose what the power buttons do"
Write-Host "     → Change settings that are currently unavailable"
Write-Host "     → Uncheck 'Turn on fast startup' → Save"
Write-Host "  2. Reboot the computer"
Write-Host "  3. Check Task Scheduler → '$TaskName' should be Running"
Write-Host "  4. Open $LogFile to see registration/heartbeat logs"