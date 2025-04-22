#!/usr/bin/env python3
"""
classify_ips.py

Read a list of IPs from a file, perform PTR and WHOIS lookups,
output CSV (ip, ptr, orgname, netname), and rebuild a BPF filter file
for any IP whose PTR ends with a given domain suffix (e.g., amazonaws.com).
"""

import argparse
import subprocess
import csv
import shlex
import sys

def ptr_lookup(ip):
    """Return comma-separated PTR records without trailing dots."""
    try:
        out = subprocess.check_output(
            ['dig', '+short', '-x', ip],
            stderr=subprocess.DEVNULL,
            text=True
        ).strip().splitlines()
        # remove trailing dots
        out = [r.rstrip('.') for r in out if r]
        return ','.join(out)
    except subprocess.CalledProcessError:
        return ''

def whois_lookup(ip):
    """Return (orgname, netname) from WHOIS for the given IP."""
    org, net = '', ''
    try:
        p = subprocess.Popen(
            ['whois', ip],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True
        )
        for line in p.stdout:
            parts = line.split(':', 1)
            if len(parts) != 2:
                continue
            key, val = parts[0].strip().lower(), parts[1].strip()
            if key in ('orgname', 'org-name') and not org:
                org = val
            elif key == 'netname' and not net:
                net = val
            if org and net:
                break
        p.wait()
    except Exception:
        pass
    return org, net

def build_bpf(matching_ips):
    """Return a BPF expression string from a list of IPs."""
    if not matching_ips:
        return ''
    parts = [f"host {ip}" for ip in matching_ips]
    return ' or '.join(parts)

def main():
    parser = argparse.ArgumentParser(
        description="Classify IPs and maintain a BPF filter for PTR suffix rules."
    )
    parser.add_argument('ips_file', help='Input file: one IP per line')
    parser.add_argument('bpf_file', help='Path to rewrite with matching hosts filter')
    parser.add_argument('--suffix', default='amazonaws.com',
                        help='PTR suffix to match for BPF inclusion')
    args = parser.parse_args()

    # Read IPs
    ips = [line.strip() for line in open(args.ips_file) if line.strip() and not line.startswith('#')]

    # Prepare CSV output
    writer = csv.writer(sys.stdout)
    writer.writerow(['ip', 'ptr', 'orgname', 'netname'])

    matching = []
    for ip in ips:
        ptr = ptr_lookup(ip)
        org, net = whois_lookup(ip)

        writer.writerow([ip, ptr, org, net])

        if any(ptr_name.endswith(args.suffix) for ptr_name in ptr.split(',')):
            matching.append(ip)

    # Write BPF file
    bpf_expr = build_bpf(matching)
    with open(args.bpf_file, 'w') as bf:
        bf.write(bpf_expr + "\n")

if __name__ == '__main__':
    main()

