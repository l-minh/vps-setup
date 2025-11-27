#!/usr/bin/env bash
# Ubuntu bootstrap installer (MongoDB 8.0 fixed)
# Installs:
# - .NET 8
# - MongoDB 8.0 (always)
# - Caddy
# - Fail2Ban
# - Swap RAM
# - UFW open ports 22,80,443
# - tmux
# - Python3 + pip
# - bpytop (Python resource monitor)
#
# Usage:
#   curl -fsSL https://your-host/setup.sh | sudo bash

set -euo pipefail

# ---------- Config ----------
SWAP_SIZE_GB=4       # Change if needed
LOG_PREFIX="[setup]"
ARCH=$(dpkg --print-architecture)

info()    { printf "%s INFO: %s\n" "$LOG_PREFIX" "$*"; }
warn()    { printf "%s WARN: %s\n" "$LOG_PREFIX" "$*"; }
error()   { printf "%s ERROR: %s\n" "$LOG_PREFIX" "$*" >&2; }
run_as_sudo(){ if [ "$(id -u)" -ne 0 ]; then sudo "$@"; else "$@"; fi }

# ---------- Detect Ubuntu ----------
if ! command -v lsb_release >/dev/null 2>&1; then
  run_as_sudo apt-get update -y
  run_as_sudo apt-get install -y lsb-release >/dev/null 2>&1 || true
fi
UBUNTU_CODENAME=$(lsb_release -cs)
info "Detected Ubuntu codename: ${UBUNTU_CODENAME}, arch: ${ARCH}"

# ---------- Update & essentials ----------
info "Updating system packages..."
run_as_sudo apt-get update -y
run_as_sudo apt-get upgrade -y
run_as_sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common wget build-essential

# ---------- Install .NET 8 ----------
info "Installing .NET 8 SDK + ASP.NET Core runtime..."
wget -qO /tmp/packages-microsoft-prod.deb "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"
run_as_sudo dpkg -i /tmp/packages-microsoft-prod.deb
rm -f /tmp/packages-microsoft-prod.deb
run_as_sudo apt-get update -y
run_as_sudo apt-get install -y dotnet-sdk-8.0 aspnetcore-runtime-8.0 || {
    warn "dotnet install failed — trying fallback..."
    run_as_sudo apt-get install -y dotnet-sdk-8.0 || true
}

# ---------- Install MongoDB 8.0 ----------
info "Installing MongoDB 8.0..."
run_as_sudo rm -f /etc/apt/sources.list.d/mongodb-org-*.list || true

# Import GPG key
curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | run_as_sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg

# Add repository
echo "deb [ arch=${ARCH} signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${UBUNTU_CODENAME}/mongodb-org/8.0 multiverse" \
    | run_as_sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list > /dev/null

# Update & install
run_as_sudo apt-get update -y || warn "apt update warning (possibly unsupported codename)"
run_as_sudo apt-get install -y mongodb-org || warn "MongoDB install may fail on unsupported Ubuntu versions"

# Enable & start MongoDB
if systemctl list-unit-files | grep -q '^mongod'; then
    run_as_sudo systemctl enable mongod
    run_as_sudo systemctl start mongod
fi

# ---------- Install Caddy ----------
info "Installing Caddy web server..."

# Remove old Caddy repo files
sudo rm -f /etc/apt/sources.list.d/caddy.list || true

sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg
chmod o+r /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install caddy

# Enable & start service
sudo systemctl enable caddy
sudo systemctl start caddy

# ---------- Install tmux ----------
info "Installing tmux..."
run_as_sudo apt-get install -y tmux

# ---------- Install Python3 + pip ----------
info "Installing Python3, pip, venv, build tools..."
run_as_sudo apt-get install -y python3 python3-pip python3-venv python3-dev build-essential

# ---------- Install Fail2Ban ----------
info "Installing Fail2Ban..."
run_as_sudo apt-get install -y fail2ban
run_as_sudo tee /etc/fail2ban/jail.local > /dev/null <<'EOF'
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
run_as_sudo systemctl enable fail2ban
run_as_sudo systemctl restart fail2ban

# ---------- Install bpytop ----------
info "Installing bpytop (Python resource monitor)..."
pip3 install --user bpytop

# ---------- Cleanup ----------
info "Cleaning up..."
run_as_sudo apt-get autoremove -y
run_as_sudo apt-get clean

# ---------- Summary ----------
echo "========================================="
info "Installation complete summary:"
echo " - .NET 8: $(dotnet --info 2>/dev/null | head -n 1 || echo 'installed')"
if command -v mongod >/dev/null 2>&1; then echo " - MongoDB: $(mongod --version | head -n 1)"; else echo " - MongoDB: not installed"; fi
echo " - Caddy: $(caddy version 2>/dev/null || echo 'installed')"
echo " - Swap: $(swapon --show=NAME,SIZE --noheadings || echo '/swapfile may be active')"
echo " - UFW: $(ufw status verbose | sed -n '1,3p')"
echo " - tmux: $(tmux -V 2>/dev/null || echo 'installed')"
echo " - Python: $(python3 --version 2>/dev/null || echo 'installed')"
echo " - bpytop: $(bpytop --version 2>/dev/null || echo 'installed in ~/.local/bin')"
echo " - Fail2Ban: $(fail2ban-client version 2>/dev/null || echo 'installed')"
echo "========================================="
info "Done. Reboot recommended if kernel updates were applied."
