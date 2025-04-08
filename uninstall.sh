#!/bin/bash
set -e

USER="tf2user"
LOGROTATE_PATH="/etc/logrotate.d/tf2server"
SYSTEMD_SERVICE_PATH="/etc/systemd/system/tf2server.service"
STATE_DIR="/var/lib/tf2server"
SERVER_CFG="$STATE_DIR/tf2/tf/cfg/server.cfg"

# Stop and disable the systemd service
sudo systemctl stop tf2server 
sudo systemctl disable tf2server  
sudo systemctl daemon-reexec  
sudo systemctl daemon-reload  

# Remove systemd service file
[ -f "$SYSTEMD_SERVICE_PATH" ] && sudo rm -f "$SYSTEMD_SERVICE_PATH"

# Remove logrotate config
[ -f "$LOGROTATE_PATH" ] && sudo rm -f "$LOGROTATE_PATH"

# Remove server config file (optional, in case user wants to keep it)
[ -f "$SERVER_CFG" ] && sudo rm -f "$SERVER_CFG"

# Remove the TF2 state directory
[ -d "$STATE_DIR" ] && sudo rm -rf "$STATE_DIR"

# Ask if the user should be removed
read -rp "Do you want to remove the user '$USER' and their home directory? (y/N): " REMOVE_USER
if [[ "$REMOVE_USER" =~ ^[Yy]$ ]]; then
    sudo userdel -r "$USER" >/dev/null 2>&1 || true
fi
