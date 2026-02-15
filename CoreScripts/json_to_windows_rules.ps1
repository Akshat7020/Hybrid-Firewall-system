# =============================================================================
#  JSON to Windows Firewall Rules Converter
#  Converts hybrid_firewall.json rules to Windows NetFirewallRule format
# =============================================================================

param(
    [string]$JsonPath = "C:\Users\Public\Documents\firewall_1\hybrid_firewall.json",
    [string]$RuleGroup = "Enterprise-Hardening"
)

function Convert-JsonRulesToWindows {
    <#
    .SYNOPSIS
    Converts hybrid firewall JSON rules to Windows firewall rules
    #>
    
    if (-not (Test-Path $JsonPath)) {
        Write-Warning "JSON file not found: $JsonPath"
        return @()
    }

    try {
        $policy = Get-Content $JsonPath -Raw | ConvertFrom-Json
    } catch {
        Write-Error "Failed to parse JSON: $($_.Exception.Message)"
        return @()
    }

    $windowsRules = @()

    # Process each rule from the JSON
    foreach ($rule in $policy.rules) {
        
        # Skip if not enabled
        if (-not $rule.enabled) { continue }
        
        # Skip L2-specific rules (they need ebtables, not netsh)
        if ($rule.layer -eq "L2") { continue }
        
        $ruleObject = @{
            Id          = $rule.id
            DisplayName = "$($RuleGroup) - $($rule.description)"
            Group       = $RuleGroup
            Direction   = "Inbound"
            Action      = "Block"
            Profile     = "Any"
            Protocol    = "TCP"
            RemotePort  = $null
            Priority    = $rule.priority
            Description = $rule.description
        }

        # Map generic action to Windows action
        switch ($rule.action) {
            "allow" { $ruleObject.Action = "Allow" }
            "deny"  { $ruleObject.Action = "Block" }
            "rate-limit" { $ruleObject.Action = "Allow"; $ruleObject.RateLimit = $rule.rate_limit }
            default { $ruleObject.Action = "Block" }
        }

        # Map direction
        switch ($rule.direction) {
            "ingress" { $ruleObject.Direction = "Inbound" }
            "egress"  { $ruleObject.Direction = "Outbound" }
            "both"    { $ruleObject.Direction = "Inbound" }
        }

        # Parse match criteria
        if ($rule.match) {
            $match = $rule.match

            # Protocol mapping
            if ($match.protocol) {
                switch ($match.protocol) {
                    "tcp" { $ruleObject.Protocol = "TCP" }
                    "udp" { $ruleObject.Protocol = "UDP" }
                    "icmp" { $ruleObject.Protocol = "ICMP" }
                    default { $ruleObject.Protocol = "TCP" }
                }
            }

            # Destination ports
            if ($match.dport) {
                if ($match.dport -is [array]) {
                    $ruleObject.RemotePort = $match.dport -join ","
                } else {
                    $ruleObject.RemotePort = $match.dport
                }
            }

            # Interface-based rules (loopback, etc.)
            if ($match.interface -eq "lo") {
                $ruleObject.DisplayName = "Allow Loopback"
                $ruleObject.Action = "Allow"
                $ruleObject.InterfaceType = "Loopback"
            }

            # Connection state
            if ($match.conntrack_state) {
                if ($match.conntrack_state -contains "ESTABLISHED") {
                    $ruleObject.DisplayName = "Allow Established Connections"
                    $ruleObject.Description = "Allow established and related connections"
                }
            }
        }

        $windowsRules += $ruleObject
    }

    return $windowsRules
}

function Invoke-WindowsRules {
    <#
    .SYNOPSIS
    Invokes the converted rules to Windows Firewall
    #>
    param(
        [array]$Rules
    )

    # Remove existing rules in the group
    Get-NetFirewallRule -Group $RuleGroup -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue

    foreach ($rule in $Rules) {
        try {
            $params = @{
                DisplayName = $rule.DisplayName
                Direction   = $rule.Direction
                Action      = $rule.Action
                Profile     = $rule.Profile
                Group       = $RuleGroup
                Enabled     = $true
            }

            if ($rule.RemotePort) {
                $params["RemotePort"] = $rule.RemotePort
            }

            if ($rule.Protocol) {
                $params["Protocol"] = $rule.Protocol
            }

            New-NetFirewallRule @params -ErrorAction Stop | Out-Null
            Write-Host "✓ Created rule: $($rule.DisplayName)" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to create rule '$($rule.DisplayName)': $($_.Exception.Message)"
        }
    }
}

function Get-WindowsRulesFromJson {
    <#
    .SYNOPSIS
    Returns converted rules without applying them (for inspection)
    #>
    return Convert-JsonRulesToWindows
}

# Export functions
Export-ModuleMember -Function Invoke-WindowsRules, Get-WindowsRulesFromJson, Convert-JsonRulesToWindows

# If run directly (not imported), apply the rules
if ($MyInvocation.InvocationName -eq "&" -or [string]::IsNullOrEmpty($MyInvocation.PSCommandPath) -eq $false -and $MyInvocation.PSCommandPath.EndsWith("json_to_windows_rules.ps1")) {
    $rules = Convert-JsonRulesToWindows
    if ($rules.Count -gt 0) {
        Write-Host "Converting $($rules.Count) rules from JSON..." -ForegroundColor Cyan
        Invoke-WindowsRules -Rules $rules
        Write-Host "Firewall rules applied successfully!" -ForegroundColor Green
    } else {
        Write-Warning "No valid rules found in JSON"
    }
}
