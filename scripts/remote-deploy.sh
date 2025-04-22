#!/usr/bin/env bash
set -euo pipefail

# Standardized project name
PROJECT_NAME="pivateTV"
REPO_DIR="$(cd "$(dirname "$0")/../" && pwd)" # Go up one level from scripts/
CONFIG_FILE="${REPO_DIR}/config/pivateTV.conf"
BACKUP_DIR="/etc/${PROJECT_NAME}-backup-$(date +%F-%H%M%S)" # Standardized backup name
CRON_SOURCE_FILE="${REPO_DIR}/cron/pivpi-tv.cron" # Keep source name for now unless renamed in repo
CRON_TARGET_FILE="/etc/cron.d/${PROJECT_NAME}" # Standardized target name and location
SCRIPTS_TARGET_DIR="/usr/local/bin/${PROJECT_NAME}" # Standardized script dir
COLLECTOR_SCHEMA_TARGET_FILE="/etc/${PROJECT_NAME}/collector-api-schema.json" # Standardized schema path

echo "=== ${PROJECT_NAME} Remote Deployment Script ===" # Standardized name

# --- Configuration Loading ---
if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "✖ ERROR: Configuration file not found at ${CONFIG_FILE}"
  exit 1
fi
echo "1) Loading configuration from ${CONFIG_FILE}"
# Source the config file, handling potential errors
set +o nounset # Temporarily disable nounset for safe sourcing
source "${CONFIG_FILE}"
set -o nounset
# Check if essential variables are set
: "${MAIN_INTERFACE:?ERROR: MAIN_INTERFACE not set in ${CONFIG_FILE}}"
: "${CAPTURE_INTERFACE:?ERROR: CAPTURE_INTERFACE not set in ${CONFIG_FILE}}"
: "${PI_MAIN_IP:?ERROR: PI_MAIN_IP not set in ${CONFIG_FILE}}"
: "${MAIN_SUBNET:?ERROR: MAIN_SUBNET not set in ${CONFIG_FILE}}"
: "${PI_CAPTURE_IP:?ERROR: PI_CAPTURE_IP not set in ${CONFIG_FILE}}"
: "${CAPTURE_SUBNET:?ERROR: CAPTURE_SUBNET not set in ${CONFIG_FILE}}"
: "${CAPTURE_DHCP_RANGE_START:?ERROR: CAPTURE_DHCP_RANGE_START not set in ${CONFIG_FILE}}"
: "${CAPTURE_DHCP_RANGE_END:?ERROR: CAPTURE_DHCP_RANGE_END not set in ${CONFIG_FILE}}"
echo "    ✔ Configuration loaded successfully."

# --- Sanity Checks ---
echo "2) Performing environment sanity checks..."
# Check for root privileges
if [[ "$(id -u)" -ne 0 ]]; then
  echo "✖ ERROR: This script must be run as root."
  exit 1
fi
echo "    ✔ Running as root."

# Check for Raspberry Pi (optional but kept from original)
if grep -qEi 'raspberry pi' /proc/cpuinfo; then
  echo "    ✔ Detected Raspberry Pi hardware."
else
  echo "    ⚠ WARNING: This does not look like a Raspberry Pi (/proc/cpuinfo)."
fi

# Check for required commands
# Added ipcalc dependency for subnet calculation
REQUIRED_COMMANDS=(iptables dnsmasq systemctl tcpdump dhclient ip sed ipcalc) # Add others if needed (e.g., tshark, isc-dhcp-server)
MISSING_COMMANDS=()
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
        MISSING_COMMANDS+=("$cmd")
    fi
done
if [[ ${#MISSING_COMMANDS[@]} -gt 0 ]]; then
    echo "✖ ERROR: Required command(s) not found: ${MISSING_COMMANDS[*]}"
    echo "  Please install them (e.g., using 'apt install <package>', note 'ipcalc' might be in 'ipcalc' or 'debian-goodies' package)."
    exit 1
fi
echo "    ✔ Required commands found (${REQUIRED_COMMANDS[*]})."

# Check network interfaces
if ! ip link show "$MAIN_INTERFACE" > /dev/null 2>&1; then
  echo "✖ ERROR: Main interface '$MAIN_INTERFACE' (from config) not found."
  echo "  Verify configuration in ${CONFIG_FILE} and check 'ip link' output."
  exit 1
fi
echo "    ✔ Main interface '$MAIN_INTERFACE' found."

if ! ip link show "$CAPTURE_INTERFACE" > /dev/null 2>&1; then
  echo "✖ ERROR: Capture interface '$CAPTURE_INTERFACE' (from config) not found."
  echo "  Verify configuration in ${CONFIG_FILE}, check 'ip link' output, and ensure USB adapters are connected."
  exit 1
fi
echo "    ✔ Capture interface '$CAPTURE_INTERFACE' found."
echo "Sanity checks passed."
echo

# --- Show Plan ---
echo "3) The following actions will be performed:"
echo "  • Backup existing files under /etc to: ${BACKUP_DIR}"
echo "  • Deploy config/* → /etc/ using values from ${CONFIG_FILE}"
echo "     - Main Interface:    ${MAIN_INTERFACE}"
echo "     - Capture Interface: ${CAPTURE_INTERFACE}"
echo "     - Main Subnet:       ${MAIN_SUBNET}"
echo "     - Capture Subnet:    ${CAPTURE_SUBNET}"
echo "     - Pi Main IP:        ${PI_MAIN_IP}"
echo "     - Pi Capture IP:     ${PI_CAPTURE_IP}"
echo "  • Deploy collector schema → ${COLLECTOR_SCHEMA_TARGET_FILE}"
echo "  • Enable & restart systemd units: tv-cap, logsync, logsync.timer"
echo "  • Copy scripts/* → ${SCRIPTS_TARGET_DIR}/"
echo "  • Install crontab from ${CRON_SOURCE_FILE} → ${CRON_TARGET_FILE}" # Updated target
echo "  • Restart pihole-FTL if installed"
echo

# --- Confirmation ---
read -rp "Proceed with deployment? [y/N] " REPLY
REPLY=${REPLY,,}   # lowercase
if [[ "$REPLY" != "y" && "$REPLY" != "yes" ]]; then
  echo "Aborted by user."
  exit 0
fi

echo
echo "👉 Starting deployment…"
mkdir -p "${BACKUP_DIR}"

# Function to perform substitution on config files
substitute_vars() {
  local target_file=$1
  echo "    • Substituting variables in ${target_file}"
  # Use pipe and temp file for safety, then rename
  local temp_file
  temp_file=$(mktemp)
  # Ensure temp file is cleaned up on exit
  trap 'rm -f "$temp_file"' EXIT INT TERM

  # Extract network and netmask from CIDR for dhcpd.conf
  local capture_subnet_network capture_subnet_netmask
  # Check if ipcalc exists before using it
  if command -v ipcalc > /dev/null 2>&1; then
      capture_subnet_network=$(ipcalc -n "$CAPTURE_SUBNET" 2>/dev/null | cut -d= -f2)
      capture_subnet_netmask=$(ipcalc -m "$CAPTURE_SUBNET" 2>/dev/null | cut -d= -f2)
      if [[ -z "$capture_subnet_network" || -z "$capture_subnet_netmask" ]]; then
          echo "✖ ERROR: ipcalc failed to parse CAPTURE_SUBNET (${CAPTURE_SUBNET}). Check format (e.g., 192.168.2.0/24)."
          exit 1
      fi
  else
      echo "✖ ERROR: 'ipcalc' command not found, cannot calculate subnet/netmask for dhcpd.conf."
      exit 1
  fi

  # Perform substitution using sed
  # Using | as delimiter in sed to avoid issues with paths/IPs containing /
  < "$target_file" sed \
    -e "s|__MAIN_INTERFACE__|${MAIN_INTERFACE}|g" \
    -e "s|__CAPTURE_INTERFACE__|${CAPTURE_INTERFACE}|g" \
    -e "s|__PI_MAIN_IP__|${PI_MAIN_IP}|g" \
    -e "s|__MAIN_SUBNET__|${MAIN_SUBNET}|g" \
    -e "s|__PI_CAPTURE_IP__|${PI_CAPTURE_IP}|g" \
    -e "s|__CAPTURE_SUBNET__|${CAPTURE_SUBNET}|g" \
    -e "s|__CAPTURE_DHCP_RANGE_START__|${CAPTURE_DHCP_RANGE_START}|g" \
    -e "s|__CAPTURE_DHCP_RANGE_END__|${CAPTURE_DHCP_RANGE_END}|g" \
    -e "s|__CAPTURE_SUBNET_NETWORK__|${capture_subnet_network}|g" \
    -e "s|__CAPTURE_SUBNET_NETMASK__|${capture_subnet_netmask}|g" \
    > "$temp_file"

  # Check if sed command was successful before moving
  if [[ $? -eq 0 ]]; then
      mv "$temp_file" "$target_file"
  else
      echo "✖ ERROR: Substitution failed for ${target_file}"
      rm -f "$temp_file" # Clean up temp file on failure
      exit 1
  fi

  # Disable the trap after successful operation if mv succeeded
  trap - EXIT INT TERM
}

backup_and_copy() {
  local src=$1 dst=$2
  if [ -e "${dst}" ]; then
    echo "    • Backing up ${dst}"
    # Create parent directory for backup destination if it doesn't exist
    mkdir -p "${BACKUP_DIR}/$(dirname "${dst}")"
    # Use rsync for better preservation of attributes if needed, or cp -a
    cp -a "${dst}" "${BACKUP_DIR}/${dst}"
  fi
  echo "    • Installing ${src} → ${dst}"
  mkdir -p "$(dirname "${dst}")"
  cp -a "${src}" "${dst}"

  # Perform substitution if it's one of the known config files
  local filename
  filename=$(basename "$dst")
  case "$filename" in
    rules.v4|tv-cap.service|dhcpd.conf)
      substitute_vars "$dst"
      ;;
  esac
}

# --- Deployment Steps ---
echo "4) Deploying config files..."
while IFS= read -r -d '' file; do
  # Resolve relative paths properly, especially '..'
  abs_file=$(realpath "$file")
  abs_config_file=$(realpath "$CONFIG_FILE")
  abs_repo_dir=$(realpath "$REPO_DIR")

  # Skip the main config file itself
  if [[ "$abs_file" == "$abs_config_file" ]]; then
      echo "    • Skipping $(basename "$abs_file") (main config file)"
      continue
  fi

  # Calculate relative path from config directory base
  rel="${abs_file#${abs_repo_dir}/config/}"

  dest="" # Reset dest
  case "$rel" in
    systemd/*)    dest="/etc/systemd/system/${rel#systemd/}" ;;
    logrotate/*)  dest="/etc/logrotate.d/${rel#logrotate/}" ;;
    dnsmasq.d/*)  dest="/etc/dnsmasq.d/${rel#dnsmasq.d/}" ;;
    sshd/*)       dest="/etc/ssh/${rel#sshd/}" ;;
    dhcp/dhcp/*)  dest="/etc/dhcp/${rel#dhcp/dhcp/}" ;; # Adjusted path
    iptables/iptables/*) dest="/etc/iptables/${rel#iptables/iptables/}" ;; # Adjusted path
    tv-cap/tv-cap/*) dest="/etc/tv-cap/${rel#tv-cap/tv-cap/}" ;; # Adjusted path
    collector-api-schema.json)
                  dest="${COLLECTOR_SCHEMA_TARGET_FILE}" ;;
    *)
      # Avoid skipping directories mistaken as files if find includes them
      if [[ -f "$abs_file" ]]; then
          echo "    • SKIPPING unknown config file path: ${rel}"
      fi
      continue ;;
  esac
  # Ensure we have a destination before proceeding
  if [[ -n "$dest" ]]; then
      backup_and_copy "$abs_file" "$dest"
  fi
done < <(find "${REPO_DIR}/config" -type f -print0) # Ensure only files are processed

echo "5) Reloading systemd & enabling services..."
systemctl daemon-reload
# Ensure the capture log directory exists before starting service
mkdir -p /var/log/tv-capture
chown root:root /var/log/tv-capture

for svc in tv-cap logsync; do
  # Check if the service file exists before trying to manage it
  svc_path="/etc/systemd/system/${svc}.service"
  if [[ -f "$svc_path" ]]; then
      if systemctl list-unit-files | grep -q "^${svc}.service"; then
        echo "    • Enabling & restarting ${svc}.service"
        systemctl enable "${svc}.service"
        # Add check for service restart success?
        if ! systemctl restart "${svc}.service"; then
            echo "    ▲ WARNING: Restarting ${svc}.service failed. Check 'systemctl status ${svc}.service' and 'journalctl -u ${svc}.service'."
        fi
      else
          echo "    • WARNING: ${svc}.service found but not listed by systemctl? Attempting enable/restart."
          systemctl enable "${svc}.service"
          if ! systemctl restart "${svc}.service"; then
              echo "    ▲ WARNING: Restarting ${svc}.service failed. Check 'systemctl status ${svc}.service' and 'journalctl -u ${svc}.service'."
          fi
      fi
  else
      echo "    • INFO: ${svc}.service not deployed, skipping systemd management."
  fi
done

# Handle timer similarly
timer_path="/etc/systemd/system/logsync.timer"
if [[ -f "$timer_path" ]]; then
    if systemctl list-unit-files | grep -q "^logsync.timer"; then
      echo "    • Enabling & starting logsync.timer"
      systemctl enable logsync.timer
      if ! systemctl start logsync.timer; then
          echo "    ▲ WARNING: Starting logsync.timer failed. Check 'systemctl status logsync.timer'."
      fi
    else
        echo "    • WARNING: logsync.timer found but not listed by systemctl? Attempting enable/start."
        systemctl enable logsync.timer
        if ! systemctl start logsync.timer; then
            echo "    ▲ WARNING: Starting logsync.timer failed. Check 'systemctl status logsync.timer'."
        fi
    fi
else
    echo "    • INFO: logsync.timer not deployed, skipping systemd management."
fi

echo "6) Deploying scripts to ${SCRIPTS_TARGET_DIR}/" # Standardized path
mkdir -p "${SCRIPTS_TARGET_DIR}"
# Use rsync for potentially better handling of updates? Or stick to cp
cp -a "${REPO_DIR}/scripts/"* "${SCRIPTS_TARGET_DIR}/"
# Ensure all scripts in target dir are executable
find "${SCRIPTS_TARGET_DIR}" -type f -exec chmod +x {} \;

echo "7) Installing crontab..." # Standardized method
if [ -f "${CRON_SOURCE_FILE}" ]; then
  # Backup existing target file if it exists
  if [ -e "${CRON_TARGET_FILE}" ]; then
      echo "    • Backing up ${CRON_TARGET_FILE}"
      mkdir -p "${BACKUP_DIR}/$(dirname "${CRON_TARGET_FILE}")"
      cp -a "${CRON_TARGET_FILE}" "${BACKUP_DIR}/${CRON_TARGET_FILE}"
  fi
  # Copy the source cron file to the new target name
  echo "    • Installing ${CRON_SOURCE_FILE} → ${CRON_TARGET_FILE}"
  cp -a "${CRON_SOURCE_FILE}" "${CRON_TARGET_FILE}"
  # Set correct ownership and permissions for cron.d file
  chown root:root "${CRON_TARGET_FILE}"
  chmod 644 "${CRON_TARGET_FILE}"
  echo "    • Crontab file deployed to /etc/cron.d/"
else
  echo "    ! WARNING: ${CRON_SOURCE_FILE} not found—skipping crontab install"
fi

# Restart Pi-hole if present (optional)
if command -v pihole >/dev/null 2>&1 && systemctl list-units --full -all | grep -q 'pihole-FTL.service'; then
    if systemctl is-active --quiet pihole-FTL; then
        echo "8) Restarting pihole-FTL"
        if ! systemctl restart pihole-FTL; then
            echo "    ▲ WARNING: Restarting pihole-FTL failed."
        fi
    else
        echo "8) pihole-FTL service found but not active, skipping restart."
    fi
else
    echo "8) pihole-FTL service not found or pihole command unavailable, skipping restart check."
fi

# Reminder about DHCP server interface configuration
echo
echo "--- IMPORTANT ---"
echo "If using isc-dhcp-server, ensure it's configured to listen ONLY on the"
echo "capture interface ('${CAPTURE_INTERFACE}'). This is usually done in"
echo "/etc/default/isc-dhcp-server by setting:"
echo "  INTERFACESv4=\"${CAPTURE_INTERFACE}\""
echo "You may need to restart the DHCP server manually after checking this setting"
echo "(e.g., 'sudo systemctl restart isc-dhcp-server.service')."
echo "---------------"

echo
echo "✅ Deployment complete."
echo "– Backups are in: ${BACKUP_DIR}"
echo "– Verify services (systemctl status tv-cap logsync logsync.timer), configs, and cron entries."

