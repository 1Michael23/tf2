#!/bin/bash
set -e

USER="tf2user"
HL_DIR="/var/lib/tf2server"
STEAMCMD_URL="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
METAMOD_URL="https://mms.alliedmods.net/mmsdrop/1.12/mmsource-1.12.0-git1217-linux.tar.gz"
SOURCEMOD_URL="https://sm.alliedmods.net/smdrop/1.12/sourcemod-1.12.0-git7196-linux.tar.gz"

DISTRO=$(awk -F= '/^ID=/{print $2}' /etc/os-release | tr -d '"')

# Create the tf2user if needed
if ! id -u $USER >/dev/null 2>&1; then
    useradd --system --home-dir /var/lib/tf2server --shell /bin/false $USER
fi

install -d -o tf2user -g tf2user -m 0700 /var/lib/tf2server

# Download and install SteamCMD
sudo -u $USER bash <<EOF
cd "$HL_DIR"
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

# Download Metamod and Sourcemod
sudo -u $USER bash -c "cd $HL_DIR && wget $METAMOD_URL -O metamod.tar.gz && tar xvf metamod.tar.gz --directory=$HL_DIR/tf2/tf/"
sudo -u $USER bash -c "cd $HL_DIR && wget $SOURCEMOD_URL -O sourcemod.tar.gz && tar xvf sourcemod.tar.gz --directory=$HL_DIR/tf2/tf/"

# Download and install MGE mod
sudo -u $USER bash -c "cd && wget https://github.com/sapphonie/MGEMod/releases/download/v3.0.9/mge.zip -O mge.zip && unzip mge.zip -d $HL_DIR/tf2/tf/"

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

read -rp "Use sv_setsteamaccount? (y/n): " USE_TOKEN

#install start script
START_SCRIPT_PATH="$HL_DIR/start.sh"

if [[ "$USE_TOKEN" =~ ^[Yy]$ ]]; then
    read -rp "Enter Steam Token: " TOKEN
    sudo -u $USER tee "$START_SCRIPT_PATH" > /dev/null <<EOF
#!/bin/bash
cd /var/lib/tf2server/tf2
exec ./srcds_run -game tf +map mge_chillypunch_final4_fix2 +sv_pure 1 +maxplayers 100 -console +sv_setsteamaccount $TOKEN
EOF
else
    sudo -u $USER tee "$START_SCRIPT_PATH" > /dev/null <<EOF
#!/bin/bash
cd /var/lib/tf2server/tf2
exec ./srcds_run -game tf +map mge_chillypunch_final4_fix2 +sv_pure 1 +maxplayers 100 -console
EOF
fi

chmod +x "$START_SCRIPT_PATH"
chown $USER:$USER "$START_SCRIPT_PATH"

#Make selinux happy on fedora, no error if not installed
semanage fcontext -a -t bin_t "/var/lib/tf2server/start.sh" 2>/dev/null || true
restorecon -v /var/lib/tf2server/start.sh 2>/dev/null || truegit 

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
sv_downloadurl "https://github.com/1Michael23/tf2/raw/refs/heads/master/"
sv_allowupload 1
net_maxfilesize 128


$RCON_LINE
EOF

# Enable and start service
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable tf2server
sudo systemctl start tf2server
