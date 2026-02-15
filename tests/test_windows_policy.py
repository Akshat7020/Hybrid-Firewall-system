#!/usr/bin/env python3
"""
Test script to verify the hybrid firewall JSON-to-Windows conversion
Run this before deploying to agents
"""

import json
import os
import sys

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
JSON_PATH = os.path.join(BASE_DIR, "hybrid_firewall.json")

def load_json():
    """Load and validate the firewall policy JSON"""
    try:
        with open(JSON_PATH, 'r') as f:
            policy = json.load(f)
        return policy
    except FileNotFoundError:
        print(f"❌ ERROR: {JSON_PATH} not found")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"❌ ERROR: Invalid JSON - {e}")
        sys.exit(1)

def test_policy_structure(policy):
    """Validate the policy structure"""
    print("\n✓ Testing policy structure...")
    
    required_fields = ["version", "description", "default_policy", "rules"]
    for field in required_fields:
        if field not in policy:
            print(f"  ❌ Missing required field: {field}")
            return False
        print(f"  ✓ {field}: present")
    
    print(f"  ✓ Policy version: {policy['version']}")
    return True

def test_windows_applicability(policy):
    """Check which rules are applicable to Windows"""
    print("\n✓ Testing Windows applicability...")
    
    all_rules = policy.get("rules", [])
    enabled_rules = [r for r in all_rules if r.get("enabled", False)]
    l3_l4_rules = [r for r in enabled_rules if r.get("layer") in ("L3", "L4")]
    l2_rules = [r for r in enabled_rules if r.get("layer") == "L2"]
    
    print(f"  Total rules: {len(all_rules)}")
    print(f"  Enabled rules: {len(enabled_rules)}")
    print(f"  Applicable to Windows (L3/L4): {len(l3_l4_rules)}")
    print(f"  Will be skipped (L2): {len(l2_rules)}")
    
    if len(l3_l4_rules) == 0:
        print("  ⚠ WARNING: No Windows-applicable rules found!")
        return False
    
    return True

def test_rule_conversion(policy):
    """Test converting rules to Windows format"""
    print("\n✓ Testing rule conversion...")
    
    proto_map = {"tcp": "TCP", "udp": "UDP", "icmp": "ICMP"}
    conversion_errors = []
    
    applicable_rules = [
        r for r in policy.get("rules", [])
        if r.get("enabled") and r.get("layer") in ("L3", "L4")
    ]
    
    for rule in applicable_rules[:5]:  # Test first 5 rules
        try:
            rule_id = rule.get("id")
            match = rule.get("match", {})
            
            # Test protocol conversion
            if match.get("protocol"):
                proto = proto_map.get(match["protocol"])
                if not proto:
                    conversion_errors.append(f"{rule_id}: Unknown protocol {match['protocol']}")
            
            # Test action conversion
            action = rule.get("action")
            if action not in ("allow", "deny", "rate-limit", "log", "escalate", "inspect"):
                conversion_errors.append(f"{rule_id}: Unknown action {action}")
            
            print(f"  ✓ {rule_id}")
            
        except Exception as e:
            conversion_errors.append(f"{rule_id}: {str(e)}")
    
    if conversion_errors:
        print("  ❌ Conversion errors found:")
        for err in conversion_errors:
            print(f"     - {err}")
        return False
    
    return True

def test_port_ranges(policy):
    """Test if port ranges are properly defined"""
    print("\n✓ Testing port range definitions...")
    
    port_issues = []
    for rule in policy.get("rules", []):
        if not rule.get("enabled"):
            continue
        
        match = rule.get("match", {})
        if "dport" in match:
            dport = match["dport"]
            if isinstance(dport, list):
                for p in dport:
                    if not (0 < p < 65536):
                        port_issues.append(f"{rule['id']}: Invalid port {p}")
            elif isinstance(dport, int):
                if not (0 < dport < 65536):
                    port_issues.append(f"{rule['id']}: Invalid port {dport}")
    
    if port_issues:
        print("  ❌ Port range issues found:")
        for issue in port_issues:
            print(f"     - {issue}")
        return False
    
    print("  ✓ All port ranges valid")
    return True

def test_rule_priorities(policy):
    """Test if rules have proper priority values"""
    print("\n✓ Testing rule priorities...")
    
    for rule in policy.get("rules", []):
        if not rule.get("enabled"):
            continue
        
        if "priority" not in rule:
            print(f"  ⚠ {rule['id']}: Missing priority field")
        else:
            priority = rule["priority"]
            if not isinstance(priority, int) or priority < 0:
                print(f"  ❌ {rule['id']}: Invalid priority {priority}")
                return False
    
    print("  ✓ All priorities valid")
    return True

def main():
    print("╔════════════════════════════════════════════════════════════════════╗")
    print("║  Windows Firewall Policy Validation Test                          ║")
    print("╚════════════════════════════════════════════════════════════════════╝")
    
    print(f"\nLoading policy from: {JSON_PATH}")
    policy = load_json()
    print("✓ JSON loaded successfully")
    
    tests = [
        test_policy_structure,
        test_windows_applicability,
        test_port_ranges,
        test_rule_priorities,
        test_rule_conversion,
    ]
    
    results = []
    for test in tests:
        try:
            result = test(policy)
            results.append(result)
        except Exception as e:
            print(f"  ❌ Test failed with exception: {e}")
            results.append(False)
    
    print("\n" + "="*70)
    print(f"Test Results: {sum(results)}/{len(results)} passed")
    
    if all(results):
        print("✓ All tests passed! Policy is ready for deployment.")
        print("\nNext steps:")
        print("  1. Run: .\\install_firewall_agent.ps1 -UserId 'your_user'")
        print("  2. Access web UI: http://10.65.42.253:5000")
        print("  3. Click 'ACTIVATE' to apply firewall rules")
        sys.exit(0)
    else:
        print("❌ Some tests failed. Review the errors above.")
        sys.exit(1)

if __name__ == "__main__":
    main()
