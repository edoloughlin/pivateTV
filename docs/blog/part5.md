# Automating Deep Packet Inspection with Dynamic Filters

Having identified suspicious IP addresses that my LG TV was communicating with, the next critical step was implementing a system to closely monitor and analyze this specific traffic. To achieve this, I chose to use dynamic Berkeley Packet Filter (BPF) expressions. BPF provides a lightweight, efficient way to capture and inspect network traffic selectively, perfect for resource-constrained devices like my Raspberry Pi.

## Why Use Dynamic Filters?

Dynamic filters were essential because:

- **Precision:** Allows targeted inspection only of suspicious traffic, reducing storage and analysis overhead.
- **Flexibility:** Filters can be easily updated as new suspicious endpoints are discovered.
- **Efficiency:** Minimizes CPU and memory usage on the Pi, critical for maintaining performance.

## Creating Dynamic BPF Filters

To automate filter creation, I used a Python script (`classify_ips.py`) previously developed to classify IP addresses. This script automatically generated a BPF expression file (`filter.bpf`) based on predefined classification rules, such as including any IP whose PTR (reverse DNS) hostname ends with specific domains like `amazonaws.com`.

### Script Operation

- The script performs PTR and WHOIS lookups to classify IP addresses.
- Applies selection criteria (e.g., hostname suffixes, organization names) to identify IPs of interest.
- Writes a BPF filter expression directly into `filter.bpf`, simplifying subsequent packet capture.

Example of a dynamically generated filter:

```
host 3.254.236.135 or host 34.241.46.32 or host 52.49.115.58
```

## Integrating Dynamic Filters into Packet Capture

To utilize the dynamically generated filter, I set up a `tcpdump` service managed by `systemd`. This allowed continuous packet capture focused explicitly on the IP addresses identified as suspicious.

Example systemd service unit file (`/etc/systemd/system/tv-cap.service`):

```ini
[Unit]
Description=Capture TV traffic to selected IPs
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/sbin/tcpdump \
  -n -i eth1 \
  -F /etc/tv-cap/filter.bpf \
  -C 100 -W 10 \
  -w /var/log/pcaps/tv.pcap
Restart=always

[Install]
WantedBy=multi-user.target
```

- **Explanation of tcpdump options:**
  - `-n`: Avoid DNS resolution during capture (to minimize overhead).
  - `-i eth1`: Capture from the ethernet interface connected to the TV.
  - `-F /etc/tv-cap/filter.bpf`: Load the dynamically generated BPF filter.
  - `-C 100 -W 10`: Rotate through ten capture files, each limited to 100 MB, maintaining a rolling buffer of recent traffic.
  - `-w /var/log/pcaps/tv.pcap`: Specifies output file naming pattern.

Enable and start the capture service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now tv-cap.service
```

## Advantages of this Setup

This automated, dynamic approach provided significant benefits:

- **Real-time Monitoring:** Continuously monitors suspicious endpoints without manual intervention.
- **Resource Efficiency:** Minimal resource use on the Raspberry Pi due to targeted capturing.
- **Easy Maintenance:** Filter rules automatically update as new IPs are classified, eliminating the need for manual updates.

## What's Next

With comprehensive packet inspection in place, the next step was proactive blocking of identified surveillance traffic. In the upcoming post, I'll detail how I blocked unwanted communications to regain complete control of my privacy.


