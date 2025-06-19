#!/bin/bash

set -euo pipefail

# === Setup ===
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/var/backups/wazuh_upgrade_$TIMESTAMP"
LOG_FILE="/var/log/wazuh_upgrade_$TIMESTAMP.log"
mkdir -p "$BACKUP_DIR"
touch "$LOG_FILE"

log() {
    echo -e "[INFO] $1" | tee -a "$LOG_FILE"
}

fail_exit() {
    echo -e "[ERROR] $1" | tee -a "$LOG_FILE"
    exit 1
}

prompt_continue() {
    read -rp "$1 (y/N): " response
    [[ "$response" =~ ^[Yy]$ ]]
}

prompt_input() {
    read -rp "$1: " input
    echo "$input"
}

prompt_secret() {
    read -rsp "$1: " secret
    echo
    echo "$secret"
}

check_service() {
    SERVICE_NAME="$1"
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        fail_exit "$SERVICE_NAME failed to start. Check logs with: journalctl -xeu $SERVICE_NAME"
    else
        log "$SERVICE_NAME is running ✅"
    fi
}

# === Step 1: Backups ===
if prompt_continue "Would you like to create backups before proceeding?"; then
    log "Backing up configs to $BACKUP_DIR"

    tar czf "$BACKUP_DIR/wazuh.tar.gz" /var/ossec | tee -a "$LOG_FILE"
    tar czf "$BACKUP_DIR/filebeat.tar.gz" /etc/filebeat | tee -a "$LOG_FILE"
    tar czf "$BACKUP_DIR/kibana.tar.gz" /etc/kibana /usr/share/kibana | tee -a "$LOG_FILE"

    log "Backups complete."
fi

# === Step 2: Prepare Wazuh Indexer Cluster ===
if prompt_continue "Prepare the Wazuh Indexer (Elasticsearch) for upgrade?"; then
    INDEXER_IP=$(prompt_input "Enter WAZUH_INDEXER_IP_ADDRESS")
    INDEXER_USER=$(prompt_input "Enter Wazuh indexer username (e.g., admin)")
    INDEXER_PASS=$(prompt_secret "Enter password for $INDEXER_USER")

    log "Disabling shard allocation..."
    curl -u "$INDEXER_USER:$INDEXER_PASS" -X PUT "https://${INDEXER_IP}:9200/_cluster/settings" \
        -H 'Content-Type: application/json' -k \
        -d '{"persistent":{"cluster.routing.allocation.enable":"none"}}' | tee -a "$LOG_FILE"

    log "Refreshing all indices..."
    curl -u "$INDEXER_USER:$INDEXER_PASS" -X POST "https://${INDEXER_IP}:9200/_refresh" -k | tee -a "$LOG_FILE"

    log "Checking shard sync..."
    curl -u "$INDEXER_USER:$INDEXER_PASS" -X GET "https://${INDEXER_IP}:9200/_synced" -k | tee -a "$LOG_FILE"

    log "Index preparation complete."
fi

# === Step 3: Stop Services ===
if prompt_continue "Stop Wazuh, Filebeat, and Kibana services?"; then
    sudo systemctl stop wazuh-manager | tee -a "$LOG_FILE"
    sudo systemctl stop filebeat | tee -a "$LOG_FILE"
    sudo systemctl stop kibana | tee -a "$LOG_FILE"
fi

# === Step 4: Upgrade ===
if prompt_continue "Proceed with upgrading all Wazuh components using apt?"; then
    sudo apt update | tee -a "$LOG_FILE"
    sudo apt install --only-upgrade wazuh-manager filebeat kibana | tee -a "$LOG_FILE"
    log "APT upgrade completed."
fi

# === Step 5: Start Services + Health Check ===
if prompt_continue "Start services again?"; then
    sudo systemctl daemon-reexec
    sudo systemctl start wazuh-manager | tee -a "$LOG_FILE"
    sudo systemctl start filebeat | tee -a "$LOG_FILE"
    sudo systemctl start kibana | tee -a "$LOG_FILE"

    # Check health of each service
    log "Verifying service status..."
    check_service wazuh-manager
    check_service filebeat
    check_service kibana
fi

# === Step 6: Version Check ===
log "Checking installed Wazuh version..."
INSTALLED_VERSION=$(cat /var/ossec/etc/version.txt)
log "Installed Wazuh version: $INSTALLED_VERSION"

LATEST_VERSION=$(curl -s https://packages.wazuh.com/4.x/apt/dists/stable/main/binary-amd64/Packages \
    | grep -A1 "Package: wazuh-manager" | grep Version | head -n1 | awk '{print $2}')
log "Latest Wazuh version in repo: $LATEST_VERSION"

if [[ "$INSTALLED_VERSION" == "$LATEST_VERSION" ]]; then
    log "✅ Wazuh is running the latest version."
else
    log "⚠️ Installed version ($INSTALLED_VERSION) is not the latest ($LATEST_VERSION). Please verify manually."
fi

log "🚀 Wazuh upgrade completed. Review the full log at $LOG_FILE"
