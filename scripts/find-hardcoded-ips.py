#!/usr/bin/env python3
"""
find_hardcoded_ips.py

Identify hard-coded IP addresses in tv-connections.log that were not
resolved via DNS (i.e., never appeared in tv-dns.log). Handles both IPv4 and IPv6,
and filters out private, unspecified, multicast, and known DNS-server addresses.
"""

import argparse
import csv
from ipaddress import ip_address, AddressValueError, IPv4Address, IPv6Address

# IPs to explicitly ignore
IGNORE_IPS = {
    ip_address("8.8.8.8"),
    ip_address("8.8.4.4"),
}

def parse_resolved_ips(dns_log_path):
    resolved_ips = set()
    with open(dns_log_path, newline='') as csvfile:
        reader = csv.reader(csvfile)
        for row in reader:
            # dns.a is index 2, dns.aaaa is index 3
            for field in row[2:4]:
                if not field:
                    continue
                for ip_str in field.split(','):
                    ip_str = ip_str.strip()
                    try:
                        resolved_ips.add(ip_address(ip_str))
                    except (AddressValueError, ValueError):
                        continue
    return resolved_ips

def parse_connection_ips(connections_log_path):
    conn_ips = set()
    with open(connections_log_path, newline='') as csvfile:
        reader = csv.reader(csvfile)
        for row in reader:
            # ip.src is index 1, ip.dst is index 2
            for ip_str in row[1:3]:
                if not ip_str:
                    continue
                try:
                    conn_ips.add(ip_address(ip_str.strip()))
                except (AddressValueError, ValueError):
                    continue
    return conn_ips

def filter_ips(ip_set):
    filtered = set()
    for ip in ip_set:
        # Exclude unspecified (0.0.0.0), private networks (e.g., 192.168.x.x),
        # multicast (224/4), and our explicit ignore list
        if ip.is_unspecified or ip.is_multicast or ip.is_private or ip in IGNORE_IPS:
            continue
        filtered.add(ip)
    return filtered

def find_hardcoded_ips(dns_log_path, connections_log_path):
    resolved = parse_resolved_ips(dns_log_path)
    connections = parse_connection_ips(connections_log_path)
    hardcoded = connections - resolved
    hardcoded_filtered = filter_ips(hardcoded)
    # Sort numerically, IPv4 before IPv6
    return sorted(hardcoded_filtered, key=lambda ip: (ip.version, int(ip)))

def main():
    parser = argparse.ArgumentParser(
        description="List non-DNS IPs in tv-connections.log (filters out private, multicast, unspecified, and DNS servers)."
    )
    parser.add_argument("dns_log", help="Path to tv-dns.log")
    parser.add_argument("connections_log", help="Path to tv-connections.log")
    args = parser.parse_args()

    result = find_hardcoded_ips(args.dns_log, args.connections_log)
    if result:
        print("Hard‑coded IPs (filtered):")
        for ip in result:
            print(ip)
    else:
        print("No hard‑coded IPs detected after filtering.")

if __name__ == "__main__":
    main()

