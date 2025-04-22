# Implementing DNS Sinkholing with `dnsmasq`

While direct IP blocking using `iptables` (as discussed in Part 6) is effective against hard-coded IP addresses, many tracking and advertising services are still accessed via standard DNS lookups, especially by third-party applications running on the TV. To address this, I implemented DNS sinkholing using `dnsmasq` running on the Raspberry Pi router.

DNS sinkholing works by intercepting DNS queries for unwanted domains and returning a false address (like `0.0.0.0`), effectively preventing the TV from connecting to those services.

## Why `dnsmasq`?

`dnsmasq` is a lightweight DNS forwarder and DHCP server. It's ideal for the Raspberry Pi due to its low resource usage and simple configuration. By configuring the Pi's DHCP server (Task 11) to assign the Pi itself (`192.168.2.1`) as the DNS server for the TV, all DNS queries from the TV are directed to `dnsmasq`.

## Configuring `dnsmasq` for Blocking

1.  **Installation:** `sudo apt install dnsmasq`
2.  **Core Configuration (`/etc/dnsmasq.conf`):**
    *   `listen-address=127.0.0.1,192.168.2.1`: Ensures `dnsmasq` only listens on the necessary interfaces (localhost and the TV-facing network).
    *   `no-resolv`: Prevents `dnsmasq` from reading the system's `/etc/resolv.conf`.
    *   `server=8.8.8.8`, `server=8.8.4.4`: Specifies upstream DNS servers (e.g., Google DNS) for legitimate queries.
    *   `conf-dir=/etc/dnsmasq.d/,*.conf`: Tells `dnsmasq` to load additional configuration files from the `/etc/dnsmasq.d/` directory. This is key for managing blocklists.
    *   `log-queries` (Optional): Can be enabled for detailed logging, useful for Task 3 (Unmatched IP Detection).

3.  **Blocklist Files:** The `conf-dir` directive allows us to add files containing block rules. `dnsmasq` reads files in this directory in alphabetical order. The format for blocking a domain is simple:
    ```
    address=/example-tracker.com/0.0.0.0
    ```
    This tells `dnsmasq` to return `0.0.0.0` whenever `example-tracker.com` (or any subdomain) is queried.

## Manual vs. Automated Blocklists

I used two types of blocklist files in `/etc/dnsmasq.d/`:

1.  **`01-manual-blocklist.conf`:** (Filename starts with `01-` to load early). This file (`config/dnsmasq.d/blocklist.conf` in the repo) is for domains I want to block manually based on specific observations. It's managed directly in the git repository.
    ```conf
    # Manually blocked domains observed during testing
    address=/manual-example.com/0.0.0.0
    address=/another-manual.net/0.0.0.0
    ```

2.  **`99-auto-blocklist.conf`:** (Filename starts with `99-` to load last). This file is generated *automatically* by a script and contains thousands of domains from public blocklists.

## Automating Blocklist Updates (`scripts/update-dnsmasq-blocklist.sh`)

Manually maintaining large blocklists is impractical. I created the `scripts/update-dnsmasq-blocklist.sh` script (Task 1) to automate this:

1.  **Fetch Lists:** The script downloads domain lists from reputable sources (defined in the `BLOCKLIST_URLS` array, e.g., StevenBlack, Firebog ticked lists).
2.  **Process Domains:** It parses these lists (which often come in `hosts` file format), extracts unique domain names, filters out comments and invalid entries, and removes duplicates.
3.  **Format for `dnsmasq`:** Each unique domain is formatted into the required `address=/domain.com/0.0.0.0` syntax.
4.  **Generate Config File:** The formatted lines are written to `config/dnsmasq.d/99-auto-blocklist.conf` within the git repository structure first (for tracking).
5.  **Deploy to System:** The script then copies this generated file to the actual `/etc/dnsmasq.d/99-auto-blocklist.conf` on the Pi (using `sudo`).
6.  **Reload `dnsmasq`:** Finally, it executes `sudo systemctl reload dnsmasq` to apply the new blocklist without interrupting DNS service.

The script also includes a `--dry-run` option to test the fetching and generation steps without deploying the file or reloading the service.

## Scheduling with Cron

To keep the blocklist up-to-date automatically, the `update-dnsmasq-blocklist.sh` script is scheduled to run daily via a cron job defined in `cron/pivpi-tv.cron` (which is deployed to `/etc/cron.d/pivpi-tv`):

```cron
# Run daily at 02:00 - Update dnsmasq blocklists
# Use nice/ionice as recommended
# !!! IMPORTANT: Replace /path/to/repo/ below with the actual absolute path !!!
0 2 * * * root nice -n 10 ionice -c2 -n7 /opt/pivpi-tv/scripts/update-dnsmasq-blocklist.sh >> /var/log/pivpi-tv-cron.log 2>&1
```
*(Note: The path `/opt/pivpi-tv/` assumes the deployment script places files there)*.

## Benefits and Considerations

*   **Broad Coverage:** Automatically blocks thousands of known ad, tracking, and malware domains commonly used by apps and web content.
*   **Low Overhead:** `dnsmasq` is very efficient and handles large lists with minimal impact on Pi performance.
*   **Complements IP Blocking:** Catches unwanted connections that IP blocking might miss (if the service uses standard DNS).
*   **Potential False Positives:** Public blocklists can occasionally block legitimate domains needed for app functionality. If an app breaks, temporarily disabling the `99-auto-blocklist.conf` (e.g., by renaming it and reloading `dnsmasq`) is a quick way to check if the blocklist is the cause.

By combining automated DNS sinkholing with targeted IP blocking, the pivateTV router provides a robust, layered defense against the TV's attempts to track user activity, significantly enhancing privacy.
