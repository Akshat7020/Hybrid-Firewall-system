$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Backend = 'http://10.144.164.253:5000'
$BaseDir   = "C:\Users\Public\Documents\firewall_1"
$UserId  = (Get-Content "$BaseDir\user_id.txt" -Raw -ErrorAction SilentlyContinue).Trim()
if (-not $UserId) {
    # fallback to machine/user name (best-effort) or a GUID if missing
    if (aksha -and LAPTOP-I1LQJ02D) {
        $UserId = "aksha@LAPTOP-I1LQJ02D"
    } else {
        $UserId = [guid]::NewGuid().ToString()
    }
}

$IdFile    = "$BaseDir\agent_id.txt"
$LogFile   = "$BaseDir\agent.log"
$FwScript  = "$BaseDir\windows_firewall.ps1"

function Log($msg) {
    Add-Content -Path $LogFile -Value "$(Get-Date -Format o) $msg" -Encoding UTF8
}

if (!(Test-Path $BaseDir)) { New-Item -ItemType Directory $BaseDir -Force | Out-Null }

$AgentId = (Get-Content $IdFile -Raw -ErrorAction SilentlyContinue).Trim()
if (!$AgentId) {
    $AgentId = [guid]::NewGuid().ToString()
    Set-Content $IdFile $AgentId
    Log "Generated new agent ID: $AgentId"
}

function Get-FirewallState {
    try {
        # Consider the firewall "ACTIVE" only if our rule group exists
        $rules = Get-NetFirewallRule -Group "Enterprise-Hardening" -ErrorAction SilentlyContinue
        if ($null -eq $rules -or $rules.Count -eq 0) { return "INACTIVE" }
        return "ACTIVE"
    } catch {
        return "UNKNOWN"
    }
}

Log "Agent starting - ID: $AgentId   User: $UserId   Path: $BaseDir"

while ($true) {
    try {
        # Register
        $null = Invoke-RestMethod "$Backend/api/agent/register" -Method Post -ContentType "application/json" -Body (@{
            user_id  = $UserId
            agent_id = $AgentId
            os_type  = "windows"
        } | ConvertTo-Json -Compress)

        Log "Registered / re-registered successfully"

        # Main loop
        while ($true) {
            try {
                $resp = Invoke-RestMethod "$Backend/api/agent/command" -Method Post -ContentType "application/json" -Body (@{
                    user_id  = $UserId
                    agent_id = $AgentId
                } | ConvertTo-Json -Compress)

                if ($resp.cmd) {
                    Log "Received command: $($resp.cmd)"
                    & powershell -NoProfile -ExecutionPolicy Bypass -File $FwScript -Mode $resp.cmd
                    Log "Command $($resp.cmd) executed"
                }

                $state = Get-FirewallState
                $null = Invoke-RestMethod "$Backend/api/agent/heartbeat" -Method Post -ContentType "application/json" -Body (@{
                    user_id  = $UserId
                    agent_id = $AgentId
                    firewall = $state
                } | ConvertTo-Json -Compress)

            } catch {
                Log "Loop error: $($_.Exception.Message)"
            }
            Start-Sleep -Seconds 5
        }
    } catch {
        Log "Supervisor restart: $($_.Exception.Message)"
        Start-Sleep -Seconds 10
    }
}
