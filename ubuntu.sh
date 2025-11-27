#!/usr/bin/env bash
# setup.sh
# Ubuntu bootstrap installer (Flexible mode)
# - .NET 8
# - MongoDB (auto choose 7.0 or 8.0 depending on Ubuntu codename)
# - Caddy
# - Fail2Ban
# - Swap file
# - UFW open ports 22,80,443
# - tmux
# - Python3 + pip + build tools
#
# Usage:
#   curl -sSL https://your-host/setup.sh | sudo bash
#
set -euo pipefail

# ---------- Config ----------
SWAP_SIZE_GB=4       # change as needed
LOG_PREFIX="[setup]"
MONGODB_DEFAULT="8.0"  # used for unknown/new Ubuntu versions (Flexible mode)

# ---------- Helpers ----------
info()    { printf "%s INFO: %s\n" "$LOG_PREFIX" "$*"; }
warn()    { printf "%s WARN: %s\n" "$LOG_PREFIX" "$*"; }
error()   { printf "%s ERROR: %s\n" "$LOG_PREFIX" "$*" >&2; }
run_as_sudo(){ if [ "$(id -u)" -ne 0 ]; then sudo "$@"; else "$@"; fi }

# ---------- Detect OS ----------
if ! command -v lsb_release >/dev/null 2>&1; then
  run_as_sudo apt-get update -y
  run_as_sudo apt-get install -y lsb-release >/dev/null 2>&1 || true
fi

UBUNTU_CODENAME=$(lsb_release -cs)
ARCH=$(dpkg --print-architecture)

info "Detected Ubuntu codename: ${UBUNTU_CODENAME}, arch: ${ARCH}"

# Determine MongoDB version to use
case "${UBUNTU_CODENAME}" in
  focal|20.04) MONGO_VER="7.0";;
  jammy|22.04) MONGO_VER="7.0";;
  noble|24.04) MONGO_VER="8.0";;
  *)
    warn "Unknown/new Ubuntu codename '${UBUNTU_CODENAME}', defaulting MongoDB to ${MONGODB_DEFAULT} (Flexible mode)."
    MONGO_VER="${MONGODB_DEFAULT}"
    ;;
esac

info "Will install MongoDB ${MONGO_VER}"

# ---------- Update & essentials ----------
info "Updating apt and installing essential packages..."
run_as_sudo apt-get update -y
run_as_sudo apt-get upgrade -y
run_as_sudo apt-get install -y \
  apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common \
  wget ca-certificates gnupg2 build-essential

# ---------- Install .NET 8 ----------
info "Installing .NET 8 SDK + ASP.NET Core runtime..."
# Microsoft packages installer - supports multiple ubuntu versions
wget -qO /tmp/packages-microsoft-prod.deb "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"
run_as_sudo dpkg -i /tmp/packages-microsoft-prod.deb
rm -f /tmp/packages-microsoft-prod.deb
run_as_sudo apt-get update -y
run_as_sudo apt-get install -y dotnet-sdk-8.0 aspnetcore-runtime-8.0 || {
  warn "dotnet package install failed — attempting to install via apt-get without exact version"
  run_as_sudo apt-get install -y dotnet-sdk-8.0 || true
}

# ---------- Install MongoDB (auto chosen version) ----------
info "Installing MongoDB ${MONGO_VER}..."

# Remove any old mongodb-org list files to avoid conflicts
run_as_sudo rm -f /etc/apt/sources.list.d/mongodb-org-*.list || true

if [ "${MONGO_VER%%.*}" -ge 8 ]; then
  # MongoDB 8.x
  info "Configuring repo for MongoDB 8.0"
  curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | run_as_sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg
  echo "deb [ arch=${ARCH} signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${UBUNTU_CODENAME}/mongodb-org/8.0 multiverse" \
    | run_as_sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list > /dev/null
else
  # MongoDB 7.x
  info "Configuring repo for MongoDB 7.0"
  curl -fsSL https://pgp.mongodb.com/server-7.0.asc | run_as_sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
  echo "deb [ arch=${ARCH} signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${UBUNTU_CODENAME}/mongodb-org/7.0 multiverse" \
    | run_as_sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list > /dev/null
fi

run_as_sudo apt-get update -y

# Try installing mongodb-org package — if apt complains about Release file (unsupported codename),
# attempt to fall back by installing mongodb-org from the closest supported codename (jammy).
if ! run_as_sudo apt-get install -y mongodb-org; then
  warn "Direct mongodb-org install failed for ${UBUNTU_CODENAME}. Attempting fallback: use jammy (22.04) repo."
  # fallback to jammy if possible
  FALLBACK_CODENAME="jammy"
  if [ "${MONGO_VER%%.*}" -ge 8 ]; then
    curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | run_as_sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg
    echo "deb [ arch=${ARCH} signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${FALLBACK_CODENAME}/mongodb-org/8.0 multiverse" \
      | run_as_sudo tee /etc/apt/sources.list.d/mongodb-org-8.0-fallback.list > /dev/null
  else
    curl -fsSL https://pgp.mongodb.com/server-7.0.asc | run_as_sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
    echo "deb [ arch=${ARCH} signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${FALLBACK_CODENAME}/mongodb-org/7.0 multiverse" \
      | run_as_sudo tee /etc/apt/sources.list.d/mongodb-org-7.0-fallback.list > /dev/null
  fi

  run_as_sudo apt-get update -y
  if ! run_as_sudo apt-get install -y mongodb-org; then
    error "MongoDB install failed even after fallback. Skipping MongoDB installation."
  else
    info "MongoDB installed via fallback repo (${FALLBACK_CODENAME})."
  fi
else
  info "MongoDB installed successfully for ${UBUNTU_CODENAME}."
fi

# If mongodb installed, enable & start
if systemctl list-unit-files | grep -q '^mongod'; then
  run_as_sudo systemctl enable mongod
  run_as_sudo systemctl start mongod
  info "MongoDB service started and enabled."
fi

# ---------- Install Caddy ----------
info "Installing Caddy web server..."
# Cloudsmith recommended install
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | run_as_sudo gpg --dearmor -o /usr/share/keyrings/caddy.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | run_as_sudo tee /etc/apt/sources.list.d/caddy.list > /dev/null
run_as_sudo apt-get update -y
run_as_sudo apt-get install -y caddy
run_as_sudo systemctl enable caddy
run_as_sudo systemctl start caddy
info "Caddy installed and started."

# ---------- Create swap file ----------
info "Creating ${SWAP_SIZE_GB}GB swap file at /swapfile (if not exists)..."
if [ ! -f /swapfile ]; then
  run_as_sudo fallocate -l "${SWAP_SIZE_GB}G" /swapfile
  run_as_sudo chmod 600 /swapfile
  run_as_sudo mkswap /swapfile
  run_as_sudo swapon /swapfile
  echo "/swapfile swap swap defaults 0 0" | run_as_sudo tee -a /etc/fstab > /dev/null
  info "Swap created and enabled."
else
  info "/swapfile already exists — skipping creation."
fi

# ---------- UFW Firewall setup ----------
info "Configuring UFW firewall (allow 22,80,443) and enabling..."
run_as_sudo apt-get install -y ufw
run_as_sudo ufw allow 22/tcp
run_as_sudo ufw allow 80/tcp
run_as_sudo ufw allow 443/tcp
# enable non-interactively
if ! run_as_sudo ufw status | grep -q "Status: active"; then
  run_as_sudo ufw --force enable
fi
info "UFW configured."

# ---------- Install tmux ----------
info "Installing tmux..."
run_as_sudo apt-get install -y tmux

# ---------- Install Python3 + pip ----------
info "Installing Python3, pip, venv and build tools..."
run_as_sudo apt-get install -y python3 python3-pip python3-venv python3-dev build-essential

# ---------- Install Fail2Ban ----------
info "Installing Fail2Ban..."
run_as_sudo apt-get install -y fail2ban
# Basic jail.local configuration (safe defaults)
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
info "Fail2Ban installed and basic jail enabled."

# ---------- Cleanup ----------
info "Cleaning up apt caches..."
run_as_sudo apt-get autoremove -y
run_as_sudo apt-get clean

# ---------- Summary ----------
echo "========================================="
info "Installation complete (summary):"
echo " - .NET 8: $(dotnet --info 2>/dev/null | head -n 1 || echo 'installed or partially installed')"
if command -v mongod >/dev/null 2>&1; then
  echo " - MongoDB: $(mongod --version | head -n 1)"
else
  echo " - MongoDB: not installed (see messages above)"
fi
echo " - Caddy: $(caddy version 2>/dev/null || echo 'installed or partially installed')"
echo " - Swap: $(swapon --show=NAME,SIZE --noheadings || echo '/swapfile may be active')"
echo " - UFW: $(ufw status verbose | sed -n '1,3p')"
echo " - tmux: $(tmux -V 2>/dev/null || echo 'tmux installed')"
echo " - Python: $(python3 --version 2>/dev/null || echo 'python3 installed')"
echo " - Fail2Ban: $(fail2ban-client version 2>/dev/null || echo 'fail2ban installed')"
echo "========================================="

info "Done. Reboot is optional but recommended if kernel updates were applied."
