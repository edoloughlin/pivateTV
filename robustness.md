# Operational Robustness Enhancements (Implemented in 5093d14)

This document summarizes the discussion and changes made to improve the operational robustness of the pivateTV deployment process, focusing on network interface handling, deployment script sanity checks, and configuration management.

## 1. Network Interface Parameterization

### Problem:
- Hardcoding interface names like `eth0` (main) and `eth1` (capture) is unreliable due to "Predictable Network Interface Names" in modern Linux.
- Different hardware (especially USB adapters) can result in different interface names.

### Solution:
- Introduced a central configuration file: `config/pivateTV.conf`.
- Defined variables `MAIN_INTERFACE` and `CAPTURE_INTERFACE` in `config/pivateTV.conf`.
- Modified configuration files (`config/iptables/iptables/rules.v4`, `config/systemd/tv-cap.service`, `config/dhcp/dhcp/dhcpd.conf`) to use placeholders (e.g., `__MAIN_INTERFACE__`, `__CAPTURE_INTERFACE__`).
- Updated deployment scripts (`scripts/local-deploy.sh`, `scripts/remote-deploy.sh`) to:
    - Source `config/pivateTV.conf`.
    - Use `sed` to substitute the placeholders in configuration files with the actual values during deployment.

### Related IP/Subnet Parameterization:
- The following parameters were also added to `config/pivateTV.conf` and corresponding placeholders were added to configuration files (`rules.v4`, `dhcpd.conf`, `tv-cap.service`) to allow customization of IP addressing:
    - `PI_MAIN_IP`
    - `MAIN_SUBNET`
    - `PI_CAPTURE_IP`
    - `CAPTURE_SUBNET`
    - `CAPTURE_DHCP_RANGE_START`
    - `CAPTURE_DHCP_RANGE_END`
- The deployment scripts use `ipcalc` (added as a required command) to derive network and netmask values from `CAPTURE_SUBNET` for `dhcpd.conf`.

## 2. Deployment Script Sanity Checks

### Problem:
- Deployment scripts (`local-deploy.sh`, `remote-deploy.sh`) could potentially fail or cause issues if run in an unsuitable environment.

### Solution:
- Added sanity checks near the beginning of both deployment scripts:
    - **Root Privileges:** Check if running as root (`id -u`).
    - **Required Commands:** Verify essential commands are installed (`command -v <tool>`), including `iptables`, `dnsmasq`, `systemctl`, `tcpdump`, `ip`, `sed`, `ipcalc`.
    - **Network Interfaces:** Check if the interfaces specified in `config/pivateTV.conf` (`$MAIN_INTERFACE`, `$CAPTURE_INTERFACE`) actually exist (`ip link show <interface>`).
    - **Configuration Loading:** Ensure `config/pivateTV.conf` exists and essential variables are set.
- Scripts now exit with an error message if a check fails.

## 3. Deployment Script Standardization (`local-deploy.sh` vs. `remote-deploy.sh`)

### Problem:
- Inconsistencies existed between `local-deploy.sh` and `remote-deploy.sh` regarding:
    - Project naming (`pivateTV` vs. `pivpi-tv`).
    - Target directories (`/usr/local/bin/`, `/etc/`).
    - Backup directory naming.
    - Cron job installation method (`crontab` vs. `/etc/cron.d/`).

### Solution:
- Standardized on the project name `pivateTV`.
- Standardized target paths:
    - Scripts: `/usr/local/bin/pivateTV/`
    - Config Schema: `/etc/pivateTV/collector-api-schema.json`
    - Cron file: `/etc/cron.d/pivateTV`
    - Backup directory pattern: `/etc/pivateTV-backup-YYYY-MM-DD-HHMMSS`
- Modified `remote-deploy.sh` to install the cron job by copying the file to `/etc/cron.d/` and setting appropriate permissions (owner root, mode 644), matching the `local-deploy.sh` method.

## 4. Configuration Management Strategy

### Discussion Points:
- **Shell Scripts:** Simple but can become complex and lack idempotency.
- **Ansible:** More robust, declarative, idempotent, better for scaling, but has a learning curve.
- **Alternatives:** Fabric (Python-based), Salt/Chef/Puppet (likely overkill).

### Decision:
- For now, enhance the existing shell scripts with parameterization and sanity checks (as implemented in commit `5093d14`).
- Ansible remains a potential future improvement if complexity increases or multiple devices need management.
