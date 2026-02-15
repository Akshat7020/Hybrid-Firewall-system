# =============================================================================
#  Hybrid Firewall Rules Applier for Windows
#  Converts hybrid_firewall.json rules to Windows firewall format
# =============================================================================

import json
import sys
import os

def load_policy(json_path):
    """Load the hybrid firewall policy from JSON"""
    try:
        with open(json_path, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"Error: Policy file not found at {json_path}")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error parsing JSON: {e}")
        sys.exit(1)

def convert_rules_to_windows(policy):
    """
    Convert hybrid JSON rules to Windows firewall format.
    Returns a list of New-NetFirewallRule PowerShell commands.
    """
    commands = []
    
    print(f"Policy version: {policy.get('version', 'unknown')}")
    print(f"Total rules: {len(policy.get('rules', []))}")
    print("\n" + "="*70)
    
    for rule in policy.get('rules', []):
        # Skip disabled rules
        if not rule.get('enabled', False):
            continue
        
        # Skip L2 rules (need ebtables on Linux, not applicable to Windows in this context)
        if rule.get('layer') == 'L2':
            print(f"⊘ Skipping L2 rule: {rule.get('id')} (requires L2 handling)")
            continue
        
        # Skip non-L3/L4 rules
        if rule.get('layer') not in ('L3', 'L4'):
            continue
        
        rule_id = rule.get('id', 'unknown')
        action = rule.get('action', 'deny')
        direction = rule.get('direction', 'ingress')
        description = rule.get('description', '')
        priority = rule.get('priority', 100)
        
        # Start building the rule
        ps_command = ['New-NetFirewallRule']
        params = {
            'DisplayName': f'"{description} [{rule_id}]"',
            'Direction': 'Inbound' if direction != 'egress' else 'Outbound',
            'Action': 'Allow' if action == 'allow' else 'Block',
            'Profile': 'Any',
            'Group': "'Enterprise-Hardening'",
            'Enabled': '$true'
        }
        
        # Parse match criteria
        match = rule.get('match', {})
        
        # Protocol
        if match.get('protocol'):
            proto_map = {'tcp': 'TCP', 'udp': 'UDP', 'icmp': 'ICMP'}
            params['Protocol'] = proto_map.get(match['protocol'], 'TCP')
        
        # Ports
        if match.get('dport'):
            ports = match['dport']
            if isinstance(ports, list):
                params['LocalPort'] = ','.join(map(str, ports))
            else:
                params['LocalPort'] = str(ports)
        
        # Build command
        param_list = ' '.join([f"-{k} {v}" for k, v in params.items()])
        commands.append(f"  {' '.join(ps_command)} {param_list}")
        
        print(f"✓ Rule: {rule_id}")
        print(f"  Action: {action} | Direction: {direction} | Protocol: {match.get('protocol', 'any')}")
        if 'LocalPort' in params:
            print(f"  Ports: {params['LocalPort']}")
        print(f"  Description: {description}\n")
    
    return commands

def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    json_path = os.path.join(base_dir, 'hybrid_firewall.json')
    
    print("\n╔════════════════════════════════════════════════════════════════════╗")
    print("║  Hybrid Firewall Rules to Windows Converter                        ║")
    print("╚════════════════════════════════════════════════════════════════════╝\n")
    
    policy = load_policy(json_path)
    commands = convert_rules_to_windows(policy)
    
    print("="*70)
    print(f"\nGenerated {len(commands)} PowerShell commands for Windows firewall:\n")
    
    if commands:
        print("\n# Copy these commands into PowerShell (as Administrator):\n")
        for cmd in commands:
            print(cmd)
    else:
        print("No applicable rules found to convert.")
    
    print("\n" + "="*70 + "\n")

if __name__ == '__main__':
    main()
