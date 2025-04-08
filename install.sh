#!/bin/bash
set -e

USER="tf2user"
HL_DIR="/var/lib/tf2server"
STEAMCMD_URL="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"

DISTRO=$(awk -F= '/^ID=/{print $2}' /etc/os-release | tr -d '"')

# Create the tf2user if needed
if ! id -u $USER >/dev/null 2>&1; then
    useradd --system --home-dir /var/lib/tf2server --shell /bin/false $USER
fi

install -d -o tf2user -g tf2user -m 0700 /var/lib/tf2server

# Download and install SteamCMD and MGE mod
sudo -u $USER bash <<EOF
cd "$HL_DIR"

# Download and extract SteamCMD
wget -N "$STEAMCMD_URL"
tar zxf steamcmd_linux.tar.gz

EOF

# Fedora libcurl fix
if [ "$DISTRO" = "fedora" ]; then
    if [ -f /usr/lib/libcurl.so.4 ] && [ ! -e /usr/lib/libcurl-gnutls.so.4 ]; then
        ln -s /usr/lib/libcurl.so.4 /usr/lib/libcurl-gnutls.so.4
    fi
fi

# Download TF2 server
sudo -u $USER bash -c "cd $HL_DIR && ./steamcmd.sh +force_install_dir ./tf2 +login anonymous +app_update 232250 +quit"

# Download and install MGE mod
sudo -u $USER bash -c "cd && wget https://github.com/sapphonie/MGEMod/releases/download/v3.0.9/mge.zip && unzip mge.zip -d $HL_DIR/tf2/tf/"

# Symlink steam sdk
sudo -u tf2user mkdir -p /var/lib/tf2server/.steam/sdk32
sudo -u tf2user ln -sf /var/lib/tf2server/linux32/steamclient.so /var/lib/tf2server/.steam/sdk32/steamclient.so

# Install service and logrotate configs
sudo cp tf2server.service /etc/systemd/system/
sudo cp logrotate /etc/logrotate.d/tf2server

# Prompt for server config
read -rp "Enter server hostname: " SERVER_NAME
read -rp "Enter server admin contact: " ADMIN_EMAIL
read -rp "Enable RCON? (y/n): " USE_RCON

if [[ "$USE_RCON" =~ ^[Yy]$ ]]; then
    read -rp "Enter RCON password: " RCON_PASSWORD
    RCON_LINE="rcon_password \"$RCON_PASSWORD\""
else
    RCON_LINE="// rcon_password \"Your_Rcon_Password\""
fi

SERVER_CFG_PATH="$HL_DIR/tf2/tf/cfg/server.cfg"
mkdir -p "$(dirname "$SERVER_CFG_PATH")"
sudo -u $USER tee "$SERVER_CFG_PATH" > /dev/null <<EOF
hostname "$SERVER_NAME"
sv_contact "$ADMIN_EMAIL"
mp_timelimit "0"
mp_maxrounds 100
sv_region -1

sv_rcon_banpenalty 1440
sv_rcon_maxfailures 5

log on

sv_log_onefile 1
sv_logfile 1
sv_logbans 1
sv_logecho 1

fps_max 600
sv_minrate 0
sv_maxrate 20000
sv_minupdaterate 10
sv_maxupdaterate 66

mp_autoteambalance 0
mp_allowspectators 1
sv_voiceenable 1
sv_alltalk 1

sv_allowdownload 1
sv_downloadurl "https://github.com/sapphonie/MGEMod/raw/refs/heads/master/maps/mge_training_v8_beta4b.bsp"
sv_allowupload 1
net_maxfilesize 128


$RCON_LINE
EOF

# Enable and start service
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable tf2server
sudo systemctl start tf2server
