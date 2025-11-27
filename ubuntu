#!/bin/bash
set -e

echo "========================================="
echo " Ubuntu Initial Setup Script"
echo " Installs: .NET 8, MongoDB, Caddy, Swap, Firewall, Tmux, Fail2Ban, Python"
echo "========================================="

# ----- UPDATE SYSTEM PACKAGES -----
echo "[1/12] Updating system packages..."
sudo apt update && sudo apt upgrade -y


# ----- INSTALL REQUIRED UTILITIES -----
echo "[2/12] Installing essential utilities..."
sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common


# ============================================================
#                     INSTALL DOTNET 8
# ============================================================
echo "[3/12] Installing .NET 8 SDK + Runtime..."

# Import Microsoft GPG key
wget https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb

sudo apt update
sudo apt install -y dotnet-sdk-8.0 aspnetcore-runtime-8.0



# ============================================================
#                     INSTALL MONGODB
# ============================================================
echo "[4/12] Installing MongoDB Community Edition..."

curl -fsSL https://pgp.mongodb.com/server-7.0.asc | \
  sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor

echo "deb [signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/7.0 multiverse" \
  | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list

sudo apt update
sudo apt install -y mongodb-org

sudo systemctl enable mongod
sudo systemctl start mongod



# ============================================================
#                     INSTALL CADDY
# ============================================================
echo "[5/12] Installing Caddy Web Server..."

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | sudo gpg --dearmor -o /usr/share/keyrings/caddy.gpg

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | sudo tee /etc/apt/sources.list.d/caddy.list

sudo apt update
sudo apt install -y caddy

sudo systemctl enable caddy
sudo systemctl start caddy



# ============================================================
#                     CREATE SWAP (VIRTUAL RAM)
# ============================================================
SWAP_SIZE_GB=4  # Change if needed

echo "[6/12] Creating ${SWAP_SIZE_GB}GB SWAP file..."

sudo fallocate -l ${SWAP_SIZE_GB}G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

echo "/swapfile swap swap defaults 0 0" | sudo tee -a /etc/fstab



# ============================================================
#                     FIREWALL CONFIGURATION
# ============================================================
echo "[7/12] Configuring UFW Firewall..."

sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable



# ============================================================
#                     INSTALL TMUX
# ============================================================
echo "[8/12] Installing tmux..."
sudo apt install -y tmux



# ============================================================
#                     INSTALL PYTHON
# ============================================================
echo "[9/12] Installing Python3 + pip..."

sudo apt install -y python3 python3-pip python3-venv python3-dev build-essential



# ============================================================
#                     INSTALL FAIL2BAN
# ============================================================
echo "[10/12] Installing Fail2Ban..."

sudo apt install -y fail2ban

# Basic hardening config
echo "[Setting Fail2Ban basic protection...]"

sudo tee /etc/fail2ban/jail.local > /dev/null <<'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
backend = systemd

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
EOF

sudo systemctl enable fail2ban
sudo systemctl restart fail2ban



# ============================================================
#                     CLEANUP
# ============================================================
echo "[11/12] Cleaning up unused packages..."
sudo apt autoremove -y



# ============================================================
#                     COMPLETED
# ============================================================
echo "========================================="
echo "✔ All components installed successfully!"
echo " - .NET 8"
echo " - MongoDB"
echo " - Caddy"
echo " - Swap (${SWAP_SIZE_GB}GB)"
echo " - Firewall: 22, 80, 443"
echo " - Tmux"
echo " - Python3 + pip"
echo " - Fail2Ban (basic jail enabled)"
echo "========================================="
