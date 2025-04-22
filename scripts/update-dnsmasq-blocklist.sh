#!/usr/bin/env bash

# update-dnsmasq-blocklist.sh
# Fetches specified blocklists, formats them for dnsmasq (address=/<domain>/0.0.0.0),
# writes them to a dnsmasq configuration file, and reloads dnsmasq.
# Includes a --dry-run option to skip system deployment and reload.

# Exit immediately if a command exits with a non-zero status.
# Exit on unset variables, and propagate exit status through pipes.
set -euo pipefail

# --- Configuration ---
# List of blocklist URLs to fetch
BLOCKLIST_URLS=(
    "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
    "https://raw.githubusercontent.com/PolishFiltersTeam/KADhosts/master/KADhosts.txt"
    "https://raw.githubusercontent.com/FadeMind/hosts.extras/master/add.Spam/hosts"
    "https://v.firebog.net/hosts/static/w3kbl.txt"
    # Add more URLs here if needed
)

# Sinkhole IP address (use 0.0.0.0 for NXDOMAIN-like behavior, or Pi's IP for a local webserver)
SINKHOLE_IP="0.0.0.0"

# Output file for dnsmasq configuration within the repository
# Find the git repo root dynamically
REPO_ROOT=$(git rev-parse --show-toplevel)
OUTPUT_FILE="${REPO_ROOT}/config/dnsmasq.d/99-auto-blocklist.conf"

# Actual system path for dnsmasq configuration (adjust if your dnsmasq config dir is different)
SYSTEM_DNSMASQ_CONFIG_DIR="/etc/dnsmasq.d"
SYSTEM_OUTPUT_FILE="${SYSTEM_DNSMASQ_CONFIG_DIR}/99-auto-blocklist.conf"

# Temporary file for processing
TEMP_LIST=$(mktemp)
# Ensure temp file is removed on exit
trap 'rm -f "$TEMP_LIST"' EXIT

# --- Argument Parsing ---
DRY_RUN=0
# Simple loop to check for --dry-run flag
for arg in "$@"; do
  if [[ "$arg" == "--dry-run" ]]; then
    DRY_RUN=1
    break
  fi
done

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "--- Dry Run Mode Enabled ---"
fi

# --- Main Script ---

echo "Fetching and processing blocklists..."

# Download all lists and extract domains
for url in "${BLOCKLIST_URLS[@]}"; do
    echo "Fetching ${url}..."
    # Use curl: follow redirects (-L), fail silently on server errors (-f), show errors (-sS)
    # Filter comments/empties/localhost, extract domain (usually $2 in hosts files)
    # Handle various formats (IP<space>Domain, Domain only)
    # Remove carriage returns, trim whitespace
    curl -LfsS "$url" | grep -vE '^(#|$|::1|127\.0\.0\.1|localhost)' | awk '{if ($1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ || $1 ~ /^::1$/) print $2; else print $1}' | tr -d '\r' | sed 's/^[ \t]*//;s/[ \t]*$//' >> "$TEMP_LIST" || {
        echo "Warning: Error fetching or processing ${url}. Skipping." >&2
        # Continue with other lists even if one fails
    }
done

echo "Generating dnsmasq blocklist file..."

# Check if temp list has content
if [[ ! -s "$TEMP_LIST" ]]; then
    echo "No domains collected from lists. Exiting." >&2
    exit 1
fi

# Create the output directory in the repo if it doesn't exist
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Process the temporary list: sort unique, remove empty lines, format for dnsmasq
# Overwrite the output file in the repository
sort -u "$TEMP_LIST" | grep -vE '^\s*$' | sed "s|^|address=/|;s|$|/${SINKHOLE_IP}|" > "$OUTPUT_FILE"

echo "Generated blocklist config in repository: ${OUTPUT_FILE}"
echo "Contains $(wc -l < "$OUTPUT_FILE") unique domains."

# --- Deployment / Reload ---
# This part copies the config to the system location and reloads dnsmasq
# Skip this section if --dry-run is specified

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Dry Run: Skipping deployment to system and dnsmasq reload."
else
  # Check if running on the target system where the config needs to be placed
  if [ -d "$SYSTEM_DNSMASQ_CONFIG_DIR" ]; then
      echo "Deploying generated config to ${SYSTEM_OUTPUT_FILE}..."
      # Ensure the target directory exists (requires sudo)
      sudo mkdir -p "$SYSTEM_DNSMASQ_CONFIG_DIR"
      # Copy the file (requires sudo)
      sudo cp "$OUTPUT_FILE" "$SYSTEM_OUTPUT_FILE"
      # Set ownership and permissions (requires sudo)
      sudo chown root:root "$SYSTEM_OUTPUT_FILE"
      sudo chmod 644 "$SYSTEM_OUTPUT_FILE"

      echo "Reloading dnsmasq configuration..."
      # Use systemctl to reload dnsmasq service (requires sudo)
      if sudo systemctl reload dnsmasq; then
          echo "dnsmasq reloaded successfully."
      else
          echo "Error reloading dnsmasq. Check dnsmasq configuration and logs." >&2
          # Optional: Restore previous config? Check systemctl status dnsmasq / journalctl -u dnsmasq
          exit 1
      fi
  else
      echo "System dnsmasq directory (${SYSTEM_DNSMASQ_CONFIG_DIR}) not found."
      echo "Skipping copy to system and dnsmasq reload."
      echo "You may need to manually copy ${OUTPUT_FILE} to your dnsmasq configuration directory and reload dnsmasq."
  fi
fi

echo "Blocklist update complete."

exit 0
