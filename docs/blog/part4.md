# Analyzing Captured Logs: Discovering Hidden Surveillance Endpoints

Having captured and securely mirrored my LG TV's network traffic logs, the next critical step was to analyze this data. My primary goal was to identify IP addresses that the TV was communicating with, especially those it accessed without using DNS lookups—a tactic often employed to conceal tracking or telemetry endpoints.

## Why Identifying Hard-Coded IPs Matters

Usually, devices resolve hostnames to IP addresses through DNS queries, a transparent process that allows visibility into the services being accessed. However, when devices use direct, hard-coded IP addresses (i.e., skipping DNS lookups), it typically indicates deliberate obfuscation of their activities.

By isolating these "hard-coded" IPs, I could uncover hidden surveillance or telemetry activities my TV was attempting without my consent.

## Extracting Hard-Coded IPs

To find hard-coded IPs, I compared the IP addresses recorded in the TV’s connection logs (`tv-connections.pcap`) against the IP addresses recorded in the DNS resolution logs (`tv-dns.pcap`).

I wrote a Python script, `find_hardcoded_ips.py`, that automated this comparison:

- Extracted IPs from DNS response packets (`dns.a` and `dns.aaaa` records).
- Extracted all IPs from the connection log.
- Computed the difference between the two sets, revealing IP addresses used without prior DNS resolution.

Example Python snippet:

```python
dns_ips = parse_dns_responses('tv-dns.pcap')
connection_ips = parse_connection_ips('tv-connections.pcap')

hardcoded_ips = connection_ips - dns_ips
```

## Classifying Discovered IP Addresses

Once I identified these suspicious IPs, I wanted to understand their context. To achieve this, I performed reverse DNS (PTR) lookups and WHOIS queries, helping reveal which organizations operated these IPs and their possible purposes.

I developed another Python script, `classify_ips.py`, to automatically handle this:

- **PTR Lookup:** Identifies hostname associated with each IP address.
- **WHOIS Query:** Provides details like organization name (`OrgName`) and network name (`NetName`).

Example classification output:

```csv
ip,ptr,orgname,netname
3.254.236.135,ec2-3-254-236-135.eu-west-1.compute.amazonaws.com,Amazon Technologies Inc.,EC2
45.57.12.134,ipv4-c055-dub001-ix.1.oca.nflxvideo.net,Netflix Streaming Services Inc.,NFLXVIDEO
```

These results were revealing—my LG TV was connecting directly to Amazon AWS, among other services, without any transparent DNS activity.

## Understanding the Results

The presence of direct AWS connections wasn't inherently alarming—services often use direct IPs for efficiency and reliability. However, the lack of transparency raised significant privacy concerns. I wondered exactly what data was being transferred and why it was hidden from normal DNS monitoring.

## What's Next

In the next post, I will detail how I configured dynamic filtering to inspect traffic to these suspicious endpoints more closely. Additionally, I'll outline the methods I used to block unwanted communications, effectively neutralizing the TV's invasive surveillance tactics.


