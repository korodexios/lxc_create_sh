# 📂 Proxmox LXC Modular Automation

Collection of Bash scripts to rapidly, securely, and modularly provision Linux Containers (LXC) on **Proxmox VE 8/9**, with optional automated deployments of **Docker** and **Portainer CE**.

## ✨ Key Features

*   **🧠 Smart Defaults & Persistence:** Remembers your configurations (usernames, resources, storage) in a local `.lxc_defaults` file. Next time, just press `Enter`.
*   **👤 Optional User Creation:** By default, it creates only `root`. If you specify a username (or a list of users), accounts are generated with `sudo` and SSH access automatically.
*   **🧩 Modular Architecture:** Run via an interactive menu, or call standalone modules directly (`lxc_create_base.sh`, `lxc_install_docker.sh`) for CI/CD and AI Agent automation.
*   **📦 Clean Standards:** Portainer CE is deployed to `/opt/portainer` (independent of user existence), and the container time zone is automatically synchronized from the Proxmox host.
*   **🔒 Security & Git Ready:** Automatic SSH public key injection. Built-in `.gitignore` rules prevent accidentally committing private/public keys and credentials.

---

## 🚀 Getting Started

### 1. Clone the repository to your Proxmox Host
Log in via SSH as `root` and clone repo:
```bash
git clone https://github.com/korodexios/lxc_create_sh.git
cd lxc_create_sh
```

### 2. Set Permissions
Grant execution permissions to all scripts:
```bash
chmod +x *.sh
```

### 3. Execution
Run the interactive menu:
```bash
./0_lxc_create.sh
```

---

## 🛠 Script Overview

| Script Name | Purpose |
| :--- | :--- |
| `0_lxc_create.sh` | **Main Menu.** Interactive wrapper prompting for configuration and calling sub-modules. |
| `lxc_create_base.sh` | Creates barebone LXC, sets up optional user(s), locales, and host-matched timezone. |
| `lxc_install_docker.sh` | Installs Docker Engine & Docker Compose inside an existing Debian/Ubuntu LXC. |
| `lxc_install_portainer.sh` | Deploys Portainer CE mapped to `/opt/portainer`. |
| `all-lxc-update.sh` | Safely updates all running/stopped Debian/Ubuntu LXCs with automatic snapshot rotation. |
| `lxc_module_validation.sh` | Parameter validator (CTID, Hostname) used by the creation scripts. |

---

## 🤖 AI / Non-Interactive Automation

You can bypass the interactive menu entirely by exporting environment variables and executing the base scripts:

```bash
# Example: Automated container setup
export LXC_ROOTFS_STORAGE="local-lvm"
export LXC_ROOTFS_SIZE="8"
export LXC_CORES="2"
export LXC_MEMORY="2048"
export LXC_USER="user"              # Leave unset or empty to keep only root
export LXC_EXTRA_USERS="admin,dev"  # Optional extra users
export LXC_PASS="SuperSecretPass123"

./lxc_create_base.sh 105 "my-app" "debian-12"
./lxc_install_docker.sh 105
./lxc_install_portainer.sh 105
```

---

## ⚠️ Security Notice

*   **Passwords:** Always update default passwords inside the container immediately after creation:
    ```bash
    pct enter <CTID>
    passwd root
    ```
*   **SSH Public Key:** Drop your `id_ed25519.pub` or `id_rsa.pub` into this directory. It will be copied into root (and new users), but `.gitignore` prevents pushing it to GitHub.

---

## 📝 License
MIT License. Free to use and modify for personal and production environments.
