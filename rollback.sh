#!/bin/bash

set -euo pipefail

LOG_FILE="/var/log/wazuh_rollback_$(date +"%Y%m%d_%H%M%S").log"
BACKUP_DIR="/var/backups"

log() {
    echo -e "[INFO] $1" | tee -a "$LOG_FILE"
}

fail_exit() {
    echo -e "[ERROR] $1" | tee -a "$LOG_FILE"
    exit 1
}

check_service() {
    SERVICE_NAME="$1"
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        fail_exit "$SERVICE_NAME failed to start. Check logs with: journalctl -xeu $SERVICE_NAME"
    else
        log "$SERVICE_NAME is running"
    fi
}

# === Step 1: Choose Backup ===
echo "Available backups:"
echo
find "$BACKUP_DIR" -maxdepth 1 -type d -name "wazuh_upgrade_*" | sort | nl

read -rp "Enter the number of the backup you want to restore: " selection

# Validate numeric input to prevent sed errors
if [[ ! "$selection" =~ ^[0-9]+$ ]]; then
    fail_exit "Selection must be a numeric value."
fi

SELECTED_BACKUP=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "wazuh_upgrade_*" | sort | sed -n "${selection}p")

if [[ ! -d "$SELECTED_BACKUP" || -z "$SELECTED_BACKUP" ]]; then
    fail_exit "Invalid selection or backup directory not found."
fi

log "Selected backup: $SELECTED_BACKUP"

# === Step 2: Stop Services ===
log "Stopping services..."
sudo systemctl stop wazuh-manager || true
sudo systemctl stop filebeat || true
sudo systemctl stop kibana || true

# === Step 3: Restore Configs ===
log "Restoring Wazuh manager config..."
sudo tar xzf "$SELECTED_BACKUP/wazuh.tar.gz" -C /

log "Restoring Filebeat config..."
sudo tar xzf "$SELECTED_BACKUP/filebeat.tar.gz" -C /

log "Restoring Kibana config..."
sudo tar xzf "$SELECTED_BACKUP/kibana.tar.gz" -C /

# === Step 4: Restart Services ===
log "Starting services..."
sudo systemctl daemon-reexec
sudo systemctl start wazuh-manager
sudo systemctl start filebeat
sudo systemctl start kibana

# === Step 5: Check Services ===
log "Verifying service status..."
check_service wazuh-manager
check_service filebeat
check_service kibana

# === Step 6: Confirm Version Restored ===
if [[ -f /var/ossec/etc/version.txt ]]; then
    RESTORED_VERSION=$(cat /var/ossec/etc/version.txt)
    log "Restored Wazuh version: $RESTORED_VERSION"
else
    log "Could not find version.txt to confirm restored version."
fi

log "Rollback completed successfully. Log: $LOG_FILE"
