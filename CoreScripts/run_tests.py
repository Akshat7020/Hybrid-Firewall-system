#!/usr/bin/env python3
import sys
sys.path.insert(0, '.')

from tests.test_apply_hybrid_rules import test_generate_iptables_cmd_basic, test_generate_ebtables_cmd_mac_and_vlan, test_arp_inspection_check

try:
    test_generate_iptables_cmd_basic()
    print("✓ test_generate_iptables_cmd_basic PASSED")
except AssertionError as e:
    print(f"✗ test_generate_iptables_cmd_basic FAILED: {e}")
    sys.exit(1)

try:
    test_generate_ebtables_cmd_mac_and_vlan()
    print("✓ test_generate_ebtables_cmd_mac_and_vlan PASSED")
except AssertionError as e:
    print(f"✗ test_generate_ebtables_cmd_mac_and_vlan FAILED: {e}")
    sys.exit(1)

try:
    test_arp_inspection_check()
    print("✓ test_arp_inspection_check PASSED")
except AssertionError as e:
    print(f"✗ test_arp_inspection_check FAILED: {e}")
    sys.exit(1)

print("\n✓ All tests passed successfully!")
