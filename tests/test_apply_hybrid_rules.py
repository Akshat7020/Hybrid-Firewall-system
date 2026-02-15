import pytest
from apply_hybrid_rules import generate_iptables_cmd, generate_ebtables_cmd, arp_inspection_check


def test_generate_iptables_cmd_basic():
    rule = {
        'id': 'r1',
        'action': 'deny',
        'protocol': 'tcp',
        'match': {
            'src_cidr': '192.168.1.0/24',
            'dst_cidr': '10.0.0.5',
            'dst_port': '22'
        }
    }
    cmd = generate_iptables_cmd(rule, chain='HYBRID_INPUT')
    assert '-p tcp' in cmd
    assert '-s 192.168.1.0/24' in cmd
    assert '-d 10.0.0.5' in cmd
    assert '--dport 22' in cmd
    assert cmd.strip().endswith('-j DROP')


def test_generate_ebtables_cmd_mac_and_vlan():
    rule = {
        'id': 'r2',
        'action': 'deny',
        'match': {
            'src_mac': '00:11:22:33:44:55',
            'dst_mac_prefix': ['01:00:5e'],
            'vlan_id_list': [10, 20]
        }
    }
    cmds = generate_ebtables_cmd(rule)
    # Expect a src mac drop cmd
    assert any('00:11:22:33:44:55' in c for c in cmds)
    # Expect placeholder for dst_mac_prefix handling
    assert any('L2PREFIX' in c or 'dst_mac_prefix' for c in cmds)


def test_arp_inspection_check():
    trusted = {'192.168.1.1': 'aa:bb:cc:dd:ee:ff', '192.168.1.2': '00:11:22:33:44:55'}
    arp_table = {'192.168.1.1': 'aa:bb:cc:dd:ee:ff', '192.168.1.2': '00:11:22:33:44:66'}
    violations = arp_inspection_check(trusted, arp_table)
    assert len(violations) == 1
    assert violations[0]['ip'] == '192.168.1.2'
    assert violations[0]['expected'] == '00:11:22:33:44:55'
