# wazuh-updater-ubuntu
# Wazuh Upgrade Script for All-in-One Ubuntu Server

This repository contains a Bash script to safely upgrade all core components of a Wazuh all-in-one deployment on Ubuntu 22.04. It includes configuration backups, Wazuh Indexer preparation, component upgrades via APT, version verification, and post-upgrade service health checks.

---

## 🔧 What It Does

- ✅ Backs up configuration for:
  - Wazuh Manager (`/var/ossec`)
  - Filebeat (`/etc/filebeat`)
  - Kibana (`/etc/kibana`, `/usr/share/kibana`)
- 🔒 Prompts for Wazuh Indexer credentials and disables shard allocation
- 📦 Upgrades:
  - `wazuh-manager`
  - `filebeat`
  - `kibana`
- 🚦 Starts services and verifies successful startup
- 📈 Compares installed Wazuh version against the latest in the official repo
- 🧾 Logs all actions to `/var/log/wazuh_upgrade_<timestamp>.log`

---

## 📂 Files

- `wazuh-upgrade.sh` — Main script to perform the upgrade
- `README.md` — This documentation file
- (Optional) `rollback.sh` — Restore script using backups (coming soon)

---

## ⚠️ Prerequisites

- Ubuntu 22.04 server
- All-in-one Wazuh installation (Manager, Filebeat, Kibana)
- APT repositories for Wazuh configured
- Systemd-managed services
- Access to the Wazuh Indexer (Elasticsearch node) and credentials
- Root or sudo privileges

---

## 🚀 How to Use

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/wazuh-upgrade-script.git
   cd wazuh-upgrade-script
