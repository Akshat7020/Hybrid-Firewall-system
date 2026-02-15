param(
    [string]$BackendUrl = "http://10.144.164.253:5000",
    [string]$UserId = "",
    [string]$Token = "",
    [string]$BaseDir = ""
)

$ErrorActionPreference = "Continue"

# -------------------------------
# Ensure PSScriptRoot works in PS 5.1
# -------------------------------
$ScriptRoot = $PSScriptRoot

if (-not $ScriptRoot -or $ScriptRoot -eq "") {
    if ($MyInvocation.MyCommand.Path) {
        $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    } else {
        $ScriptRoot = Get-Location
    }
}

# -------------------------------
# OS Detection (PS 5.1 Safe)
# -------------------------------
function Get-LocalOS {

    if ($env:OS -eq "Windows_NT") {
        return "windows"
    }

    try {
        if (Test-Path "/proc/version" -ErrorAction SilentlyContinue) {
            return "linux"
        }
    } catch {
        # Ignore
    }

    return "unknown"
}

$LocalOS = Get-LocalOS
Write-Host "Detected OS: $LocalOS" -ForegroundColor Cyan

# -------------------------------
# Auto-detect UserId if not provided
# -------------------------------
if (-not $UserId -or $UserId.Trim() -eq "") {

    $possible = @(
        "C:\Users\Public\Documents\firewall_1\user_id.txt",
        "/opt/hybrid_firewall/user_id.txt"
    )

    foreach ($p in $possible) {
        try {
            if (Test-Path "$p") {
                $UserId = (Get-Content "$p" -Raw).Trim()
                break
            }
        } catch {
            # Continue
        }
    }
}

# -------------------------------
# WINDOWS INSTALLATION
# -------------------------------
if ($LocalOS -eq "windows") {

    Write-Host "Installing Windows firewall agent..." -ForegroundColor Yellow

    $script = Join-Path "$PSScriptRoot" "install_firewall_agent.ps1"

    if (-not (Test-Path "$script")) {
        Write-Host "ERROR: Windows installer not found: $script" -ForegroundColor Red
        exit 1
    }

    # Use hashtable splatting for reliable parameter passing (not array splatting)
    $scriptParams = @{
        BackendUrl = $BackendUrl
    }

    if ($UserId -and $UserId.Trim() -ne "") {
        $scriptParams["UserId"] = $UserId
    }

    if ($BaseDir -and $BaseDir.Trim() -ne "") {
        $scriptParams["InstallDirectory"] = $BaseDir
    }

    & "$script" @scriptParams

    if ($LASTEXITCODE) {
        exit $LASTEXITCODE
    } else {
        exit 0
    }
}

# -------------------------------
# LINUX INSTALLATION
# -------------------------------
if ($LocalOS -eq "linux") {

    Write-Host "Installing Linux firewall agent..." -ForegroundColor Yellow

    $python = $null

    try {
        $pyCmd = Get-Command python3 -ErrorAction SilentlyContinue
        if ($pyCmd) { $python = $pyCmd.Source }
    } catch {}

    if (-not $python) {
        try {
            $pyCmd = Get-Command python -ErrorAction SilentlyContinue
            if ($pyCmd) { $python = $pyCmd.Source }
        } catch {}
    }

    if (-not $python) {
        Write-Host "ERROR: Python3 not found. Please install Python3." -ForegroundColor Red
        exit 3
    }

    $script = Join-Path "$PSScriptRoot" "install_firewall_agent.py"

    if (-not (Test-Path "$script")) {
        Write-Host "ERROR: Python installer not found: $script" -ForegroundColor Red
        exit 1
    }

    $proc = Start-Process `
        -FilePath $python `
        -ArgumentList @($script, "--backend", $BackendUrl) `
        -NoNewWindow `
        -Wait `
        -PassThru

    if ($proc -and $proc.ExitCode) {
        exit $proc.ExitCode
    } else {
        exit 0
    }
}

# -------------------------------
# UNKNOWN OS
# -------------------------------
Write-Host "ERROR: Unsupported OS: $LocalOS" -ForegroundColor Red
exit 1
