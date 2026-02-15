$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Backend = "http://10.65.42.253:5000"
$BaseDir = "C:\Users\Public\Documents\firewall_1"
$IdFile  = "$BaseDir\agent_id.txt"
$LogFile = "$BaseDir\agent.log"
$FwScript = "$BaseDir\windows_firewall.ps1"

if (!(Test-Path $BaseDir)) {
    New-Item -ItemType Directory $BaseDir -Force | Out-Null
}

function Log($msg) {
    Add-Content -Path $LogFile -Value "$(Get-Date -Format o) $msg" -Encoding UTF8
}

if (!(Test-Path $FwScript)) {
    Log "CRITICAL: Firewall script missing at $FwScript"
    exit 1
}

$AgentId = (Get-Content $IdFile -Raw -ErrorAction SilentlyContinue).Trim()
if (!$AgentId) {
    $AgentId = [guid]::NewGuid().ToString()
    Set-Content $IdFile $AgentId
    Log "Generated Agent ID: $AgentId"
}

function Get-FirewallState {
    try {
        $rules = Get-NetFirewallRule -Group "Enterprise-Hardening" -ErrorAction SilentlyContinue
        if ($rules -and $rules.Count -gt 0) { return "ACTIVE" }
        return "INACTIVE"
    } catch {
        return "UNKNOWN"
    }
}

Log "Agent started | ID: $AgentId | Backend: $Backend"

while ($true) {
    try {
        # REGISTER
        Invoke-RestMethod "$Backend/api/agent/register" -Method Post -ContentType "application/json" -Body (@{
            agent_id = $AgentId
            os_type  = "windows"
        } | ConvertTo-Json -Compress)

        Log "Registered"

        while ($true) {

            $resp = Invoke-RestMethod "$Backend/api/agent/command" -Method Post -ContentType "application/json" -Body (@{
                agent_id = $AgentId
            } | ConvertTo-Json -Compress)

            if ($resp.cmd -in @("ACTIVATE","DEACTIVATE")) {

                Log "Executing $($resp.cmd)"

                try {
                    & powershell -NoProfile -ExecutionPolicy Bypass -File $FwScript -Mode $resp.cmd -LogFile $LogFile
                    Log "Firewall command executed successfully"
                }
                catch {
                    Log "Firewall execution failed: $($_.Exception.Message)"
                }
            }

            $state = Get-FirewallState

            Invoke-RestMethod "$Backend/api/agent/heartbeat" -Method Post -ContentType "application/json" -Body (@{
                agent_id = $AgentId
                firewall = $state
            } | ConvertTo-Json -Compress)

            Start-Sleep -Seconds 5
        }

    } catch {
        Log "Connection error: $($_.Exception.Message)"
        Start-Sleep -Seconds 10
    }
}
