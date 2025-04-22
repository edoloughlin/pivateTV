# Blocking Surveillance Traffic: Taking Back Control

Once I had dynamic packet inspection working and could reliably identify the endpoints my LG TV was talking to—especially those it tried to hide—I turned to the most satisfying phase of this whole exercise: blocking them.

At this point, I had visibility into DNS lookups, direct IP connections, and context around each endpoint (including ownership and network names). The TV’s behaviour had been laid bare, and the next logical step was to start actively refusing its attempts to phone home. This was about more than just analysis—it was about digital sovereignty.

## The Power and Philosophy of Blocking

Blocking is simple in concept but profound in its implications. It’s a rare moment in modern tech usage where you, the user, get to say: “No.”

When I saw the TV try to contact advertising networks, tracking infrastructure, and obscure AWS nodes with no apparent reason, I realised this wasn’t just telemetry—it was surveillance. So I chose to treat it like a hostile actor.

There are many ways to block outbound traffic:

- At the firewall (e.g. using `iptables`, `nftables`, or `ufw`)
- Via DNS (returning 0.0.0.0 or `NXDOMAIN` for specific domains)
- At the routing layer (blackholing routes to IPs)

In my setup, I focused on the firewall and DNS methods.

## Using `iptables` to Block IPs

The first technique I used was direct IP blocking with `iptables`. This gave me immediate control over traffic at the packet level.

Here’s a script snippet that blocks a list of known surveillance IPs:

```bash
for ip in $(cat /etc/tv-blocklist.txt); do
    iptables -A OUTPUT -d $ip -j REJECT
    iptables -A FORWARD -d $ip -j REJECT
done
```

This blocks traffic from the Pi itself and also prevents the TV (routed through `eth1`) from reaching those IPs.

I created a simple pipeline:

- Extract hard-coded IPs from logs
- Classify them
- Automatically add any matching `amazonaws.com` or sketchy hostnames to the blocklist

This was controlled via a nightly cron job.

### Why Use IP Blocking?

- **DNS can be bypassed.** Many of these devices use hard-coded IPs or DOH (DNS over HTTPS).
- **Immediate enforcement.** IP blocking is fast and reliable.
- **Protocol-agnostic.** It doesn’t matter whether the traffic is HTTP, HTTPS, or custom binary—if it goes to a known bad IP, it gets blocked.

## DNS Sinkholing for Fallback

For domains that still went through traditional DNS, I ran a local DNS resolver (dnsmasq) that allowed domain-level blacklisting.

Example config (`/etc/dnsmasq.d/blocklist.conf`):

```
address=/tracking.lgtv.com/0.0.0.0
address=/ads.lgappstv.com/0.0.0.0
```

This returned `0.0.0.0` for any lookup of those domains, effectively null-routing them.

I also wrote a script to parse the DNS logs and look for new suspicious domains, checking for patterns like “ads”, “track”, “log”, “beacon”, etc., and adding them to the blacklist automatically.

## Making It Stick: Persistence and Automation

All block rules were saved and reloaded on boot:

```bash
iptables-save > /etc/iptables/rules.v4
```

I also created a `systemd` unit and timer that runs every few hours, re-generating the blocklist from the latest classification results and reapplying it.

## Unexpected Side Effects

Blocking traffic had some interesting effects:

- Some apps on the TV took noticeably longer to load, suggesting retry loops.
- Others displayed vague error messages or refused to run.
- The TV never complained explicitly about the lack of telemetry—it just failed silently.

This is an important point: modern devices are often built to fail gracefully when surveillance is blocked, because manufacturers don’t want to reveal just how dependent the product is on tracking infrastructure.

## Was It Worth It?

Absolutely.

Blocking gave me measurable peace of mind. Not only was I seeing less unsolicited traffic, but the logs showed that the TV had stopped reaching out to dozens of endpoints entirely.

This was a line in the sand. It was proof that we don’t have to accept surveillance as the default. With a little effort, curiosity, and technical knowledge, we can push back.

## What’s Next

The final post in this series will reflect on the broader implications of this journey—what it taught me about modern tech, privacy, and what we can all do to reclaim a bit more autonomy in an increasingly surveilled world.


