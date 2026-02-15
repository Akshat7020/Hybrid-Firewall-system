#!/usr/bin/env python3
"""
Cross-platform Hybrid Firewall Rule Applier (L2-L4)
"""

import os
import sys
import json
import platform
import subprocess
import logging
import shlex
import re
from typing import Any, cast

BASE = os.path.dirname(os.path.abspath(__file__))
POLICY_FILE = os.path.join(BASE, 'hybrid_firewall.json')
LOGFILE = os.path.join(BASE, 'hybrid_apply.log')

logging.basicConfig(level=logging.INFO, filename=LOGFILE, format='%(asctime)s %(levelname)s %(message)s')
console = logging.StreamHandler()
console.setLevel(logging.INFO)
logging.getLogger('').addHandler(console)


def load_policy(path=POLICY_FILE):
    with open(path, 'r') as f:
        return json.load(f)


def send_udp_message(ip, port, message):
    import socket
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(3)
        sock.sendto(message.encode('utf-8'), (str(ip), int(port)))
        sock.close()
        logging.info(f"Sent UDP message to {ip}:{port}")
    except Exception as e:
        logging.warning(f"Failed to send UDP message to {ip}:{port}: {e}")


def generate_iptables_cmd(rule, chain='HYBRID_INPUT'):
    """Generate iptables command string from rule dict"""
    parts = []
    proto = rule.get('protocol')
    if proto and proto.lower() != 'any':
        parts.append(f'-p {proto}')
    src = rule.get('match', {}).get('src_cidr')
    dst = rule.get('match', {}).get('dst_cidr')
    dst_port = rule.get('match', {}).get('dst_port') or rule.get('match', {}).get('port')
    if src:
        parts.append(f'-s {src}')
    if dst:
        parts.append(f'-d {dst}')
    if dst_port:
        parts.append(f'--dport {dst_port}')
    j = 'ACCEPT' if rule.get('action') == 'allow' else 'DROP'
    return f"iptables -A {chain} {' '.join(parts)} -j {j}"


def is_valid_mac(mac: str) -> bool:
    """Validate MAC address format"""
    if not isinstance(mac, str):
        return False
    mac = mac.strip()
    if re.fullmatch(r'([0-9A-Fa-f]{2}[:\-]){5}[0-9A-Fa-f]{2}', mac):
        return True
    if re.fullmatch(r'[0-9A-Fa-f]{12}', mac):
        return True
    return False


def generate_ebtables_cmd(rule):
    """Generate ebtables commands from rule dict"""
    cmds = []
    m = rule.get('match', {})
    action = rule.get('action', 'deny')
    target = 'DROP' if action == 'deny' else 'ACCEPT'
    if 'src_mac' in m:
        src = str(m['src_mac']).strip()
        if not is_valid_mac(src):
            logging.warning(f"Skipping invalid src_mac '{src}' in rule {rule.get('id')}")
        else:
            cmds.append(f'ebtables -A HYBRID_BRIDGE -s {shlex.quote(src)} -j {target}')
    if 'dst_mac' in m:
        dst = str(m['dst_mac']).strip()
        if not is_valid_mac(dst):
            logging.warning(f"Skipping invalid dst_mac '{dst}' in rule {rule.get('id')}")
        else:
            cmds.append(f'ebtables -A HYBRID_BRIDGE -d {shlex.quote(dst)} -j {target}')
    if 'dst_mac_prefix' in m:
        for p in m['dst_mac_prefix']:
            cmds.append(f'ebtables -A HYBRID_BRIDGE -p 0x0800 --log --log-prefix "L2PREFIX" ')
    if 'vlan_id_list' in m:
        for vid in m['vlan_id_list']:
            cmds.append(f'ebtables -A HYBRID_BRIDGE -i ! + -j ACCEPT')
    return cmds


def arp_inspection_check(trusted_ip_to_mac, arp_table):
    """
    Compare trusted mapping (ip -> mac) against an arp_table dict (ip -> mac) and return list of violations.
    """
    violations = []
    for ip, expected_mac in trusted_ip_to_mac.items():
        observed = arp_table.get(ip)
        if not observed or observed.lower() != expected_mac.lower():
            violations.append({'ip': ip, 'expected': expected_mac, 'observed': observed})
    return violations


def apply_policy(policy, dry_run=False, arp_table=None):
    """Apply firewall policy"""
    logging.info("Applying policy")
    pass


if __name__ == '__main__':
    logging.info("Hybrid firewall applier started")
