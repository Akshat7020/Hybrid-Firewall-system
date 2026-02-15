# =============================================================================
#  Manual Firewall Control Script (for testing/emergency)
#  Use this to manually activate/deactivate firewall without going through the web UI
# =============================================================================

param(
    [ValidateSet("ACTIVATE","DEACTIVATE","STATUS")]
    [string]$Action = "STATUS"
)

$BaseDir = "C:\Users\Public\Documents\firewall_1"
$FirewallScript = Join-Path $BaseDir "windows_firewall.ps1"
$StateFile = "$env:ProgramData\fw_state.json"
$RuleGroup = "Enterprise-Hardening"

Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Manual Windows Firewall Control                              ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

function Get-FirewallStatus {
    <#
    .SYNOPSIS
    Check if firewall is currently active
    #>
    try {
        $rules = Get-NetFirewallRule -Group $RuleGroup -ErrorAction SilentlyContinue
        $ruleCount = if ($rules -is [array]) { $rules.Count } else { if ($null -eq $rules) { 0 } else { 1 } }
        
        if ($ruleCount -gt 0) {
            Write-Host "  Status: ✓ ACTIVE" -ForegroundColor Green
            Write-Host "  Rules applied: $ruleCount" -ForegroundColor Green
            
            if (Test-Path $StateFile) {
                $state = Get-Content $StateFile | ConvertFrom-Json
                if ($state.active_rules) {
                    Write-Host "  Active rule IDs:" -ForegroundColor Cyan
                    $state.active_rules | ForEach-Object {
                        Write-Host "    - $_" -ForegroundColor Green
                    }
                }
            }
            return $true
        } else {
            Write-Host "  Status: ✗ INACTIVE" -ForegroundColor Yellow
            Write-Host "  Rules applied: 0" -ForegroundColor Yellow
            return $false
        }
    } catch {
        Write-Host "  Status: ? UNKNOWN" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Invoke-FirewallAction {
    <#
    .SYNOPSIS
    Execute firewall activation or deactivation
    #>
    param(
        [ValidateSet("ACTIVATE","DEACTIVATE")]
        [string]$Mode
    )
    
    if (-not (Test-Path $FirewallScript)) {
        Write-Host "❌ Firewall script not found: $FirewallScript" -ForegroundColor Red
        return $false
    }
    
    Write-Host "  Executing: $Mode" -ForegroundColor Cyan
    
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $FirewallScript -Mode $Mode
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ $Mode completed successfully" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  ❌ $Mode failed with exit code $LASTEXITCODE" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "  ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# ────────────────────────────────────────────────
#  Main Logic
# ────────────────────────────────────────────────

switch ($Action) {
    "STATUS" {
        Write-Host "Checking firewall status..." -ForegroundColor Cyan
        Get-FirewallStatus | Out-Null
    }
    
    "ACTIVATE" {
        Write-Host "Activating firewall..." -ForegroundColor Cyan
        $success = Invoke-FirewallAction -Mode "ACTIVATE"
        
        if ($success) {
            Write-Host "`nVerifying activation..." -ForegroundColor Cyan
            Get-FirewallStatus | Out-Null
        }
    }
    
    "DEACTIVATE" {
        Write-Host "Deactivating firewall..." -ForegroundColor Cyan
        Write-Host "⚠ WARNING: Removing all Enterprise-Hardening firewall rules!" -ForegroundColor Yellow
        
        $response = Read-Host "Continue? [y/N]"
        if ($response -eq "y" -or $response -eq "Y") {
            $success = Invoke-FirewallAction -Mode "DEACTIVATE"
            
            if ($success) {
                Write-Host "`nVerifying deactivation..." -ForegroundColor Cyan
                Get-FirewallStatus | Out-Null
            }
        } else {
            Write-Host "  Cancelled" -ForegroundColor Yellow
        }
    }
}

Write-Host "`n" -ForegroundColor Cyan

# ────────────────────────────────────────────────
#  Show Recent Events
# ────────────────────────────────────────────────

Write-Host "Recent firewall events:" -ForegroundColor Cyan
try {
    $events = Get-EventLog -LogName Application -Source "Firewall-Escalation" -Newest 5 -ErrorAction Stop
    if ($events) {
        $events | Format-Table -Property @(
            @{Label="Time"; Expression={$_.TimeGenerated}},
            @{Label="Type"; Expression={$_.EntryType}},
            @{Label="Message"; Expression={$_.Message}}
        ) | Out-String | Write-Host
    } else {
        Write-Host "  (No events yet)" -ForegroundColor Gray
    }
} catch {
    Write-Host "  Could not read event log: $($_.Exception.Message)" -ForegroundColor Gray
}

Write-Host ""
