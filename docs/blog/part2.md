# Turning a Raspberry Pi into a TV Traffic Sniffer and Router

After LG’s betrayal with intrusive data collection practices, I was determined to regain control over my privacy. I decided to leverage the hardware I already had on hand—a Raspberry Pi 4 and a USB ethernet adapter—to build my own custom router capable of monitoring and blocking surveillance traffic from my TV.

## Hardware and Initial Setup

I had the following:

- **Raspberry Pi 4** (4GB RAM model)
- **USB-to-Ethernet adapter** (for providing a second ethernet interface)
- **Standard Ethernet cable** (to connect to the broadband router and TV)

The setup was straightforward:

1. Connect the Pi’s built-in Ethernet port (`eth0`) directly to my broadband router to provide internet access to the Pi.
2. Connect the USB ethernet adapter (`eth1`, though this may vary based on your adapter) directly to the LG TV to isolate and monitor its network traffic.

## Network Configuration

To make the Pi a transparent router that could inspect and forward traffic:

- **Enabled IP forwarding** on the Pi. This allows the Pi to route traffic between its interfaces, effectively acting as a router:

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

- **Configured NAT** (Network Address Translation) to allow devices connected through the Pi (like the TV) to access the internet through `eth0`:

```bash
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
```

- **Made NAT configuration persistent** across reboots so I wouldn't lose the setup each time the Pi restarts:

```bash
sudo apt install iptables-persistent
```

## DHCP Setup

Next, I set up a DHCP server to assign IP addresses to the TV automatically:

- Installed the DHCP server software (`isc-dhcp-server`) so that the Pi can dynamically manage network configurations for connected devices:

```bash
sudo apt install isc-dhcp-server
```

- Configured DHCP server (`/etc/dhcp/dhcpd.conf`) to define a subnet range and provide the necessary gateway and DNS details to connected devices like my TV:

```dhcp
subnet 192.168.2.0 netmask 255.255.255.0 {
    range 192.168.2.10 192.168.2.50;
    option routers 192.168.2.1;
    option domain-name-servers 8.8.8.8, 8.8.4.4;
}
```

- Assigned a static IP address to the Pi’s USB ethernet interface (`eth1`) to ensure consistent network configuration:

```
interface eth1
static ip_address=192.168.2.1/24
```

- Restarted the DHCP server to apply the new configuration:

```bash
sudo systemctl restart isc-dhcp-server
```

## Capturing Traffic

To fully understand and monitor the traffic from my TV, I used `tshark` (a command-line version of Wireshark):

- Installed `tshark` to capture and analyze network traffic directly on the Pi:

```bash
sudo apt install tshark
```

- Set up automated packet captures through systemd, creating dedicated services (`tv-dns.service` and `tv-connections.service`) to capture DNS and general IP traffic:

- Example DNS capture service configuration (`tv-dns.service`):

```ini
[Unit]
Description=Capture TV DNS queries

[Service]
ExecStart=/usr/bin/tshark -i eth1 -f "port 53" -w /var/log/tv-dns.pcap
Restart=always

[Install]
WantedBy=multi-user.target
```

- Enabled and started these services to automatically run at boot, ensuring continuous capture without manual intervention:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now tv-dns.service tv-connections.service
```

## What's Next

With this setup, I now had detailed logs of exactly what my LG TV was attempting to communicate back to its servers. In the following post, I'll detail how I analyzed these logs, identified suspicious endpoints, and blocked unwanted surveillance traffic.


