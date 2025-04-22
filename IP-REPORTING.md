# IP Reporting & Dynamic BPF Filter Automation

This README describes the complete workflow for **discovering**, **classifying**, and **filtering** network endpoints used by your LG webOS TV. It explains:

1. **Why** you need to identify "hard‑coded" IPs (those not resolved via DNS) to see exactly which services the TV is contacting.
2. **How** those IPs are extracted by comparing your connection logs against DNS query logs.
3. **How** we classify each IP with PTR and WHOIS lookups to understand its purpose.
4. **How** we automatically generate a BPF filter for capturing only the traffic to selected endpoints (e.g. AWS).
5. **How** to integrate the filter into a systemd‑managed `tcpdump` service.

---

## 1. Motivation & Approach

Smart TVs often connect directly to cloud services via IP addresses, bypassing DNS for certain telemetry or content streams. To fully monitor and audit your TV’s traffic, you need to:

- **Capture DNS lookups** (`tv-dns.log`) to see which hostnames the TV resolves.
- **Capture raw connections** (`tv-connections.log`) to record every source→destination IP pair.

Then you can **identify hard‑coded IPs** by taking all observed IPs in `tv-connections.log` and subtracting those that appeared as answers in `tv-dns.log`. These missing IPs represent endpoints the TV used without a DNS resolution—often critical services or telemetry backends.

---

## 2. Identifying Hard‑Coded IP Addresses

1. **Extract resolved IPs** from `tv-dns.log`: pull the `dns.a` and `dns.aaaa` fields (IPv4 and IPv6 answers).
2. **Extract connection IPs** from `tv-connections.log`: pull the `ip.src` and `ip.dst` fields.
3. **Compute the set difference**: `connections_ips \ resolved_ips` → these are the IPs never seen via DNS.
4. **Filter out** local, multicast, or known DNS servers to focus on public endpoints.

A simple Python script (`find_hardcoded_ips.py`) automates these steps and generates a list of hard‑coded public IPs.

---

## 3. Classifying IPs

Once you have a shortlist of suspect IPs, use the classification script (`classify_ips.py`) to enrich each address with:

- **PTR Record**: reverse‑DNS lookup to reveal hostnames (e.g. `ec2-52-49-115-58.eu-west-1.compute.amazonaws.com`).
- **OrgName & NetName**: WHOIS fields identifying the operator (e.g. Amazon, Netflix, Google).

The script outputs a **CSV report**:

```csv
ip,ptr,orgname,netname
52.49.115.58,ec2-52-49-115-58.eu-west-1.compute.amazonaws.com,Amazon Technologies Inc.,EC2
45.57.12.134,ipv4-c055-dub001-ix.1.oca.nflxvideo.net,Netflix Streaming Services Inc.,NFLXVIDEO
...etc...
```

It also applies simple rules—by default, any IP whose PTR ends with `amazonaws.com` is selected for deeper packet capture.

---

## 4. Generating the BPF Filter

The classified script automatically rebuilds a **BPF filter file** (e.g. `/etc/tv-cap/filter.bpf`) containing an expression like:

```
host 3.254.236.135 or host 34.241.46.32 or host 52.49.115.58
```

This filter can be loaded directly into `tcpdump` or `tshark` with minimal kernel‑level overhead, ensuring you capture only the traffic to your endpoints of interest.

---

## 5. Systemd Service Integration

Use a `systemd` unit to run `tcpdump` with the generated filter and a rotating ring buffer:

```ini
# /etc/systemd/system/tv-cap.service
[Unit]
Description=Capture TV traffic to selected IPs
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/sbin/tcpdump \
  -n -i enx34298f71b8bd \
  -F /etc/tv-cap/filter.bpf \
  -C 100 -W 10 \
  -w /var/log/pcaps/tv.pcap
Restart=always

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now tv-cap.service
```

This will maintain ten 100 MiB pcap files, always retaining the most recent 1 GiB of traffic for your selected services.

---

## 6. Customization & Maintenance

- **Adjust hard‑coded detection**: tweak `find_hardcoded_ips.py` to exclude additional ranges or include IPv6.
- **Change selection rules**: pass `--suffix` to `classify_ips.py` or add OrgName-based filtering.
- **Expand BPF filter**: group addresses into CIDR blocks (e.g. `net 34.240.0.0/12`) to shorten expressions.
- **Schedule updates**: run classification & filter regeneration via cron or a systemd timer daily to capture new endpoints.

---

By following this workflow, you gain full visibility into the network services your TV uses—capturing both its DNS‑resolved lookups and any direct IP connections, classifying them for context, and focusing your packet captures where it matters.

