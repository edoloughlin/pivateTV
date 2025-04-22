# Streamlining Deployment: Pushing Updates to the pivateTV Router

As the pivateTV project grew, managing configuration files and scripts directly on the Raspberry Pi became cumbersome. Cloning the git repository onto the Pi worked initially, but updating involved pulling changes, manually copying files to system locations (`/etc/systemd/system`, `/etc/dnsmasq.d`, etc.), setting permissions, and restarting services. This process was error-prone and tedious.

I needed a more robust and repeatable way to deploy updates from my development machine (where I manage the git repository) to the Pi. The solution was to create a deployment script.

## Why a Deployment Script?

Instead of managing the full git repository on the Pi, a deployment script offers several advantages:

1.  **Cleanliness:** Keeps the Pi's filesystem cleaner, only containing the necessary deployed files, not the entire git history or development artifacts.
2.  **Consistency:** Ensures that the deployment process is the same every time, reducing the risk of manual errors.
3.  **Automation:** Simplifies the update process to running a single command from the development machine.
4.  **Central Management:** All configuration and scripts are managed centrally in the git repository on the development machine.

## The Tools: `rsync` and `ssh`

I chose standard, reliable Unix tools for the job:

*   **`rsync`:** Highly efficient for transferring files. It only copies changed files or parts of files, making updates fast, especially over potentially slower network links. It also handles directory structures well.
*   **`ssh`:** The standard for secure remote access. It allows the script to not only copy files but also execute commands directly on the Pi to finalize the setup (e.g., move files into system directories, set permissions, reload services).

## How `deploy.sh` Works

I created a script named `deploy.sh` in the root of my project repository. Here’s a breakdown of its workflow:

1.  **Configuration:** At the top, variables define the Pi's hostname (`PI_HOST`), the SSH user (`PI_USER`), and a base directory on the Pi (`REMOTE_BASE_DIR`, e.g., `/opt/pivpi-tv`) where files will be initially synced.
2.  **Prerequisites Check:** Verifies that `rsync` and `ssh` are available on the machine running the script.
3.  **Remote Directory Setup:** Connects via SSH to create the base directory structure on the Pi, ensuring the SSH user has permission to write files there initially.
4.  **File Synchronization (`rsync`):**
    *   Iterates through a predefined list (`SYNC_ITEMS`) of directories (`scripts/`) and specific configuration files (`config/dnsmasq.d/blocklist.conf`, `cron/pivpi-tv.cron`, etc.).
    *   Uses `rsync -avz --delete` to efficiently sync these items to the corresponding locations under `REMOTE_BASE_DIR` on the Pi. The `--delete` flag ensures that files removed from the local repo are also removed from the remote staging area.
5.  **Remote Setup (`ssh`):**
    *   Executes a block of commands remotely on the Pi via a single SSH connection. This block uses `set -e` to ensure it stops if any command fails.
    *   **Copies Files to System Locations:** Uses `sudo cp` to move the synced files from the staging area (`/opt/pivpi-tv/...`) to their final destinations (e.g., `/etc/cron.d/`, `/etc/dnsmasq.d/`, `/etc/systemd/system/`).
    *   **Updates Cron Path:** Critically, before copying the cron file, it uses `sed` to replace the placeholder path (`/path/to/repo/`) with the actual path on the Pi (`/opt/pivpi-tv/`), ensuring the cron job calls the script correctly.
    *   **Sets Permissions/Ownership:** Uses `sudo chown` and `sudo chmod` to set the correct ownership (usually `root:root`) and permissions (e.g., `644` for config files) for system files.
    *   **Makes Scripts Executable:** Uses `sudo chmod +x` on the scripts in the remote `scripts` directory.
    *   **Reloads Services:** Uses `sudo systemctl daemon-reload` to make systemd aware of any unit file changes, and `sudo systemctl reload dnsmasq` to apply DNS configuration updates. (Optionally, it could also restart other services like `isc-dhcp-server` or enable/start systemd units if needed).

## Using the Script

Deploying updates now involves just a few steps:

1.  Ensure SSH key-based authentication is set up to the Pi for the specified user (to avoid password prompts).
2.  Make sure the Pi has the necessary system packages installed (`dnsmasq`, `isc-dhcp-server`, `logrotate`, `iptables-persistent`, etc.).
3.  Run `./deploy.sh` from the root of the local git repository.

The script handles the rest, providing informative output along the way.

## Benefits Realized

This script significantly improved my workflow. Deployments are now fast, reliable, and require minimal manual intervention. It ensures that the configuration running on the Pi accurately reflects the state of the git repository, making troubleshooting and updates much easier. It's a small investment in automation that pays off significantly in managing the project long-term.
