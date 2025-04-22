**pivateTV Snoop Router & Log Mirror Setup**

This README explains how to configure a Raspberry Pi 4 as a transparent router and packet sniffer for an LG webOS TV, capture its traffic, rotate logs, mirror them to a collector machine, and selectively block domains via DNS sinkholing.

---

## 1. Network Routing & NAT

1. **Interfaces**
   - `eth0`: uplink to broadband router.
   - `enx34298f71b8bd`: USB-Ethernet to TV, static IP `192.168.2.1/24` (configured in `/etc/dhcpcd.conf`).

2. **Enable IP forwarding**
   ```bash
   sudo sh -c 'echo 1 > /proc/sys/net/ipv4/ip_forward'
   sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
   sudo sysctl -p
   ```

3. **Masquerade outbound traffic**
   ```bash
   sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
   sudo iptables -A FORWARD -i eth0 -o enx34298f71b8bd -m state \
     --state RELATED,ESTABLISHED -j ACCEPT
   sudo iptables -A FORWARD -i enx34298f71b8bd -o eth0 -j ACCEPT
   sudo apt install iptables-persistent
   sudo netfilter-persistent save
   ```

4. **DHCP server**
   - Install: `sudo apt install isc-dhcp-server`.
   - Configure interfaces: `/etc/default/isc-dhcp-server` → `INTERFACESv4="enx34298f71b8bd"`.
   - Subnet block: `/etc/dhcp/dhcpd.conf`
     ```conf
     authoritative;
     subnet 192.168.2.0 netmask 255.255.255.0 {
       range 192.168.2.10 192.168.2.50;
       option routers 192.168.2.1;
       option domain-name-servers 192.168.2.1; # Point clients to the Pi for DNS
     }
     ```
   - Delay start until interface up: custom systemd unit `/etc/systemd/system/isc-dhcp-server.service` (with `ExecStartPre` loop).

---

## 2. Packet Capture Services

Two systemd services capture DNS queries and IP connections via tshark:

- **tv-dns.service** captures DNS:
  ```ini
  [Service]
  ExecStart=/usr/bin/tshark -i enx34298f71b8bd -f "udp port 53" \
    -Y "dns.flags.response==1" -T fields -e frame.time_epoch \
    -e dns.qry.name -e dns.a -e dns.aaaa \
    -E separator=, -E quote=d
  StandardOutput=append:/var/log/tv-dns.log
  …
  ```

- **tv-connections.service** captures all IP src→dst:
  ```ini
  [Service]
  ExecStart=/usr/bin/tshark -i enx34298f71b8bd -f "ip" \
    -T fields -e frame.time_epoch -e ip.src -e ip.dst \
    -E separator=,
  StandardOutput=append:/var/log/tv-connections.log
  …
  ```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now tv-dns.service tv-connections.service
```
*(Note: See also Task 9/13 in `tracker.md` regarding `tv-cap.service` for targeted BPF capture)*

---

## 3. Log Rotation & Retention

Use `logrotate` to cap logs at ~7 GB raw:

- Create `/etc/logrotate.d/tv-snoop`:
  ```conf
  /var/log/tv-*.log {
    size 50M
    rotate 140
    compress
    copytruncate
    missingok
    notifempty
  }
  ```
- Run hourly: drop a script in `/etc/cron.hourly/` or rely on default daily.

---

## 4. Log Mirroring to Collector

**On Collector:**
1. Create non-login `logsync` user; lock its password; disable TTY in `/etc/ssh/sshd_config`.
2. Prepare `/mirror` owned by `logsync` (chmod 700).
3. Install SSH server.

**On Pi:**
1. Generate `~/.ssh/id_rsa_pi_logs` and copy to `logsync@collector`.
2. Optional SSH alias in `/home/pi/.ssh/config`:
   ```ini
   Host collector
     HostName 192.168.1.17
     User logsync
     IdentityFile ~/.ssh/id_rsa_pi_logs
     IdentitiesOnly yes
   ```
3. Create `/etc/systemd/system/logsync.service`:
   ```ini
   [Service]
   User=pi
   ExecStart=/usr/bin/flock -n /var/run/logsync.lock \
     /usr/bin/nice -n19 ionice -c3 rsync -az --append-verify \
     /var/log/tv-*.log logsync@collector:/mirror/
   ```
4. Create `/etc/systemd/system/logsync.timer`:
   ```ini
   [Timer]
   OnBootSec=5min
   OnUnitInactiveSec=10min
   Persistent=true
   ```
5. Enable:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now logsync.timer
   ```

---

## 5. DNS Blocking (Sinkholing)

Use `dnsmasq` on the Pi to act as the DNS server for the TV and block unwanted domains.

1. **Install `dnsmasq`**:
   ```bash
   sudo apt update
   sudo apt install dnsmasq
   ```

2. **Configure `dnsmasq`**:
   - Create `/etc/dnsmasq.conf` or edit the existing one. Key settings:
     ```conf
     # Listen only on the TV-facing interface and localhost
     listen-address=127.0.0.1,192.168.2.1
     # Don't read /etc/resolv.conf
     no-resolv
     # Use upstream DNS servers (e.g., Google's)
     server=8.8.8.8
     server=8.8.4.4
     # Load all config files from /etc/dnsmasq.d
     conf-dir=/etc/dnsmasq.d/,*.conf
     # Enable DNS query logging (optional, for Task 3)
     # log-queries
     # log-facility=/var/log/dnsmasq.log
     ```
   - Ensure the DHCP server (Task 1.4) provides `192.168.2.1` as the DNS server to the TV.

3. **Manual Blocklist (Optional)**:
   - Create `/etc/dnsmasq.d/01-manual-blocklist.conf` (or similar) for manually added domains:
     ```conf
     # Manually blocked domains
     address=/manual-example.com/0.0.0.0
     address=/another-manual.net/0.0.0.0
     ```

4. **Automated Blocklist Generation**:
   - The script `scripts/update-dnsmasq-blocklist.sh` fetches domains from public blocklists (e.g., Firebog ticked lists).
   - It processes these lists and generates a `dnsmasq` formatted file at `config/dnsmasq.d/99-auto-blocklist.conf` within this repository.
   - The script then copies this file to `/etc/dnsmasq.d/99-auto-blocklist.conf` on the system.
   - This script is run automatically via a cron job defined in `cron/pivpi-tv.cron` (which needs to be copied to `/etc/cron.d/pivpi-tv`).

5. **Restart `dnsmasq`**:
   ```bash
   sudo systemctl restart dnsmasq
   ```
   *(The automated script uses `systemctl reload dnsmasq` after updating the blocklist)*

---

## 6. Console Customization (Optional)

- **Clear screen before login banner**: drop `/etc/systemd/system/getty@.service.d/clear-screen.conf` with `ExecStartPre=/usr/bin/printf '\033[2J\033[H'`.
- **Font size**: `sudo dpkg-reconfigure console-setup` → choose 16×32.
- **Boot target**: `sudo systemctl set-default multi-user.target` to disable X.

---

## 7. Monitoring & Troubleshooting

- **Check service logs**: `journalctl -u <service> -f` (e.g., `dnsmasq`, `isc-dhcp-server`, `logsync`).
- **Check cron logs**: `/var/log/pivpi-tv-cron.log` (or syslog if not redirected).
- **Memory**: `free -h`.
- **Next timer run**: `systemctl list-timers logsync.timer`.
- **DHCP debug**: `sudo tcpdump -i enx34298f71b8bd port 67 or port 68 -n`.
- **DNS test (from Pi)**: `dig @127.0.0.1 <domain-to-test>`
- **DNS test (from TV/Client)**: Use network tools on the client to query the Pi (`192.168.2.1`).

---

This setup gives you a low‑overhead router+sniffer, automated rotation & offload of logs, automated domain blocking via `dnsmasq`, and a locked‑down collector user for secure log storage.
