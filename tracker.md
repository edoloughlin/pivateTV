# pivateTV Project Task Tracker (Revised for dnsmasq)

**Note:** This plan assumes the setup described in the project documentation (README, blog posts), using `dnsmasq` for DNS/blocking and `isc-dhcp-server` for DHCP. Scripts and configs are assumed to be managed within a git repo on the Pi (e.g., `/home/pi/pivpi-tv/`).

---

## Task 1: Bad-domain Sinkholing

*   **Description:** Automate fetching blocklists (e.g., Firebog), formatting domains as `address=/domain.com/0.0.0.0`, writing to a `dnsmasq` config file (e.g., `99-auto-blocklist.conf`), and reloading `dnsmasq`.
*   **Status:** Implemented
*   **Next Steps:** Ensure `scripts/update-dnsmasq-blocklist.sh` is executable (`chmod +x`). Copy `cron/pivpi-tv.cron` to `/etc/cron.d/pivpi-tv` on the target Pi, making sure to set the correct absolute path to the script within the cron file. Monitor `/var/log/pivpi-tv-cron.log` for successful execution.
*   **Related Docs/Files:** `docs/README.md` (Sec 5), `docs/blog/part6.md`, `config/dnsmasq.d/blocklist.conf` (manual list), `cron/pivpi-tv.cron`, `scripts/update-dnsmasq-blocklist.sh`

---

## Task 2: Domain Vetting Enrichment

*   **Description:** (Optional) Vet newly blocked domains (by comparing generated lists) against reputation APIs (VirusTotal/AbuseIPDB) and promote high-confidence blocks to a separate, persistent `dnsmasq` list.
*   **Status:** Planned
*   **Next Steps:** Write enrichment script using `dnsmasq` files as input/output. Obtain API keys.
*   **Related Docs/Files:** `config/dnsmasq.d/`

---

## Task 3: Unmatched IP Detection

*   **Description:** Cross-reference IPs from connection logs (PCAPs) against IPs resolved via `dnsmasq` logs (requires `log-queries` enabled in `dnsmasq.conf`, likely logging to syslog). Flag IPs connected to directly without prior DNS lookup.
*   **Status:** Planned
*   **Next Steps:** **Adapt `scripts/find-hardcoded-ips.py`** to parse `dnsmasq` logs (from syslog/daemon.log or `/var/log/dnsmasq.log` if configured) instead of PCAP DNS responses. Ensure `dnsmasq` logging is enabled (`log-queries` in `dnsmasq.conf`).
*   **Related Docs/Files:** `scripts/find-hardcoded-ips.py`, `docs/blog/part4.md`, `IP-REPORTING.md`, `config/dnsmasq.conf` (system file, not in repo), `/var/log/syslog` or `/var/log/dnsmasq.log`

---

## Task 4: Active IP Reporting

*   **Description:** Generate daily text list of unique source/destination IPs seen in connection logs (PCAPs).
*   **Status:** Planned
*   **Next Steps:** Create/review script (`active-ip-report.sh`) to parse PCAPs (e.g., `/var/log/tv-connections.pcap` or `/var/log/pcaps/tv.pcap`). Schedule via cron.
*   **Related Docs/Files:** `docs/blog/part3.md` (log paths), `config/systemd/tv-connections.service` or `tv-cap.service` (capture details), `scripts/active-ip-report.sh` (to be created)

---

## Task 5: PCAP Rotation & Offload

*   **Description:** Rotate and compress PCAP files (`tv-dns.pcap`, `tv-connections.pcap`, `tv.pcap`) using `logrotate`. Mirror logs to a collector machine using `rsync` via systemd timer (`logsync.timer`).
*   **Status:** Planned
*   **Next Steps:** Configure `logrotate` (e.g., `/etc/logrotate.d/tv-logs` based on `config/logrotate/tv-logs`). Configure and enable `logsync.service` and `logsync.timer`.
*   **Related Docs/Files:** `docs/blog/part3.md`, `config/logrotate/tv-logs`, `config/systemd/logsync.service`, `config/systemd/logsync.timer`

---

## Task 6: Reporting to Collector

*   **Description:** Aggregate metrics (e.g., count of blocked domains from `dnsmasq` files, unmatched IPs list, active IPs count, PCAP metadata) into JSON and POST/send to collector API/endpoint.
*   **Status:** Planned
*   **Next Steps:** **Create/adapt reporting script** (`report-to-collector.sh`) to gather metrics from `dnsmasq` files, Task 3 output, Task 4 output, and PCAP metadata. Schedule via cron.
*   **Related Docs/Files:** `IP-REPORTING.md`, `config/collector-api-schema.json`, `scripts/report-to-collector.sh` (to be created)

---

## Task 7: Collector-side Reporting

*   **Description:** Extend collector machine to receive, process, store, and visualize incoming reports from the Pi. Implement dashboards, alerting, etc.
*   **Status:** Planned
*   **Next Steps:** Define collector ingestion schema, processing logic, and dashboard components.
*   **Related Docs/Files:** `IP-REPORTING.md`, `config/collector-api-schema.json`

---

## Task 8: Git Repository Setup

*   **Description:** Initialize and maintain a git repository on the Pi to manage scripts, configurations, and documentation.
*   **Status:** Implemented
*   **Next Steps:** Maintain repo structure, commit changes, manage branches.
*   **Related Docs/Files:** `.gitignore`, `README.md`

---

## Task 9: Dynamic BPF Filter Gen

*   **Description:** Generate BPF filter file (`filter.bpf`) based on classified IPs (e.g., from `classify-ips.py`) for use with `tcpdump` (`tv-cap.service`).
*   **Status:** Planned
*   **Next Steps:** Ensure `classify-ips.py` correctly generates `config/tv-cap/tv-cap/filter.bpf`. Configure and enable `tv-cap.service` to use it.
*   **Related Docs/Files:** `docs/blog/part5.md`, `IP-REPORTING.md`, `scripts/classfy-ips.py`, `config/tv-cap/tv-cap/filter.bpf`, `config/systemd/tv-cap.service`

---

## Task 10: Firewall IP Blocking

*   **Description:** Use `iptables` to directly block specific IPs identified as problematic (potentially populated from `classify-ips.py` output or manual list).
*   **Status:** Planned
*   **Next Steps:** Populate `config/iptables/iptables/rules.v4` with blocking rules. Ensure rules are loaded persistently (e.g., via `iptables-persistent`).
*   **Related Docs/Files:** `docs/blog/part6.md`, `config/iptables/iptables/rules.v4`, `scripts/classfy-ips.py` (potential source of IPs)

---

## Task 11: DHCP Configuration

*   **Description:** Configure `isc-dhcp-server` to assign IPs to the TV and provide the Pi's IP (`192.168.2.1`) as the DNS server.
*   **Status:** Planned
*   **Next Steps:** Populate `config/dhcp/dhcp/dhcpd.conf` based on `docs/README.md`. Configure `/etc/default/isc-dhcp-server`. Ensure service runs correctly.
*   **Related Docs/Files:** `docs/README.md` (Sec 1, 4), `docs/blog/part2.md`, `config/dhcp/dhcp/dhcpd.conf`

---

## Task 12: Network/NAT Configuration

*   **Description:** Configure IP forwarding, NAT (`iptables`), and static IP for the Pi's TV-facing interface (`eth1` or `enx...`).
*   **Status:** Planned
*   **Next Steps:** Configure IP forwarding (`sysctl.conf`). Populate `config/iptables/iptables/rules.v4` with NAT/forwarding rules. Configure static IP (e.g., `dhcpcd.conf`). Ensure persistence.
*   **Related Docs/Files:** `docs/README.md` (Sec 1, 3), `docs/blog/part2.md`, `config/iptables/iptables/rules.v4`

---

## Task 13: Packet Capture Services

*   **Description:** Use `systemd` services (`tv-dns.service`, `tv-connections.service`, `tv-cap.service`) to run `tshark` or `tcpdump` for capturing traffic.
*   **Status:** Planned
*   **Next Steps:** Define/configure systemd units for desired captures (e.g., `tv-cap.service` from `config/systemd/tv-cap.service`). Enable and start services.
*   **Related Docs/Files:** `docs/README.md` (Sec 2), `docs/blog/part2.md`, `docs/blog/part5.md`, `config/systemd/tv-cap.service`, (potentially others for DNS/connections if used)

---

## Revised Cron Job Plan (`cron/pivpi-tv.cron`)

```cron
# pivateTV Project Cron Jobs (Revised for dnsmasq)
# Assumes scripts are in /home/pi/pivpi-tv/scripts/ or similar

# Run daily at 02:00 - Update dnsmasq blocklists
# Use nice/ionice as recommended
# !!! IMPORTANT: Replace /path/to/repo/ below with the actual absolute path !!!
0 2 * * * root nice -n 10 ionice -c2 -n7 /path/to/repo/scripts/update-dnsmasq-blocklist.sh >> /var/log/pivpi-tv-cron.log 2>&1

# Placeholder for Task 2: Enrich new domains (02:30)
# 30 2 * * * root nice -n10 /path/to/repo/scripts/enrich-new-domains.py >> /var/log/pivpi-tv-cron.log 2>&1

# Placeholder for Task 3: Find unmatched IPs (03:00) - Requires adapted script
# 0 3 * * * root nice -n10 /path/to/repo/scripts/find-hardcoded-ips.py >> /var/log/pivpi-tv-cron.log 2>&1

# Placeholder for Task 4: Active IP report (04:00)
# 0 4 * * * root nice -n10 /path/to/repo/scripts/active-ip-report.sh >> /var/log/pivpi-tv-cron.log 2>&1

# Placeholder for Task 6: Report to collector (05:00) - Requires adapted script
# 0 5 * * * root nice -n10 ionice -c2 -n7 /path/to/repo/scripts/report-to-collector.sh >> /var/log/pivpi-tv-cron.log 2>&1

# Note: Task 5 (PCAP Rotation/Mirroring) handled by logrotate and systemd timer.
# Note: Tasks 8-13 are primarily configuration/service management, not cron jobs.
```

---
