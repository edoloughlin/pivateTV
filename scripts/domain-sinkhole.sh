#!/usr/bin/env bash
set -euo pipefail

# domain-sinkhole.sh
# Fetch blocklist URLs from Firebog, download each hosts file,
# extract unique domains, and feed into Pi-hole blacklist.

# 1. Fetch the list of hosts-file URLs
URL_LIST="https://v.firebog.net/hosts/lists.php?type=tick"

# 2. Download each list, extract domains, dedupe
wget -qO- "$URL_LIST" \
  | xargs -n1 wget -qO- \
  | grep -vE '^\s*#' \
  | awk '/\./ { print $1 }' \
  | sort -u \
  | pihole -b -     # Add domains to Pi-hole blacklist

# 3. Rebuild gravity database
pihole -g
