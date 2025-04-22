# Capturing and Mirroring TV Network Logs

In my quest to reclaim control over my privacy from my LG TV’s intrusive data collection, setting up my Raspberry Pi as a dedicated router was only the first step. To truly understand and counteract the TV’s surveillance attempts, I needed to reliably capture, store, and analyze the network traffic flowing from the TV. This would allow me to pinpoint exactly what data the TV was sending out and identify suspicious or unwanted communications.

Because the Raspberry Pi has limited storage capacity, managing these logs carefully became essential. It was equally important to maintain backups of the captured logs on another, more robust machine. This ensured data safety, provided additional analysis capabilities, and prevented the Pi from becoming overloaded with data.

## Log Capturing and Management

To efficiently manage log storage, I chose to implement `logrotate`, a standard Linux utility designed specifically to handle the rotation, compression, and archiving of log files:

- **Install logrotate** (if not already installed):

```bash
sudo apt install logrotate
```

- **Configure logrotate** by creating the configuration file `/etc/logrotate.d/tv-logs`:

```bash
/var/log/tv-dns.pcap /var/log/tv-connections.pcap {
    rotate 7
    daily
    compress
    missingok
    notifempty
    create 640 root adm
}
```

This configuration performs daily rotation of the captured logs, retaining one week’s worth of compressed files. This approach ensures sufficient historical data while keeping the Pi’s storage requirements manageable.

## Mirroring Logs to a Collector Machine

Given the limited computing and storage resources of the Pi, I decided to mirror the logs to a more powerful collector machine using `rsync` over SSH. This setup provides secure and efficient transfers, enabling in-depth analysis without taxing the Pi:

- **Set up SSH Key-based Authentication** to allow automatic, secure log transfers without manual intervention or password prompts:

```bash
ssh-keygen -t ed25519
ssh-copy-id user@collector_ip
```

- **Create an automated log synchronization script** (`logsync.sh`) to periodically transfer logs:

```bash
#!/bin/bash
/usr/bin/nice -n19 /usr/bin/rsync -az --delete /var/log/tv-*.pcap user@collector_ip:/path/to/mirror
```

Here, the `nice` command ensures that log synchronization runs with low priority, minimizing the impact on the Pi’s performance. Additionally, I chose `rsync` specifically because it efficiently transfers only differences between files, significantly reducing bandwidth usage and transfer time compared to alternatives like `scp` or manual file copying methods. `rsync` is well-suited for resource-constrained environments like the Raspberry Pi.

- **Schedule the synchronization** using a systemd timer and service:

`/etc/systemd/system/logsync.service`

```ini
[Unit]
Description=Sync TV logs to collector

[Service]
ExecStart=/usr/local/bin/logsync.sh
```

`/etc/systemd/system/logsync.timer`

```ini
[Unit]
Description=Regular sync of TV logs

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
```

Enable and start the timer:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now logsync.timer
```

This scheduling ensures hourly synchronization of log data, significantly reducing the risk of data loss and ensuring continuous availability of fresh data for analysis.

## Importance of Regular Log Mirroring

Regular mirroring is not just about backups—it's about ensuring continuity and reliability in privacy protection. Mirroring:

- **Protects data**: Keeps a secure, secondary copy safe from corruption or accidental deletion.
- **Facilitates detailed analysis**: Provides the computational power needed for thorough inspection of large data sets.
- **Ensures Pi reliability**: Keeps the Pi running efficiently by preventing storage exhaustion.

## What's Next

With capturing and mirroring in place, my next step is to analyze the logs thoroughly. I'll examine precisely what data LG is attempting to collect, identify any hidden endpoints, and subsequently implement effective countermeasures to block unwanted traffic. Stay tuned for the detailed analysis in my next post.


