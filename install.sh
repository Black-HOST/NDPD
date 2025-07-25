#!/bin/bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/Black-HOST/NDPD/master"
BIN_PATH="/usr/local/bin/ndpd"
SYSTEMD_PATH="/etc/systemd/system/ndpd.service"
SERVICE_NAME="ndpd.service"

# Colors
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m" # No color

info()    { echo -e "${BLUE}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[-]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }

# Root check
info "Checking root permissions..."
if [[ $EUID -ne 0 ]]; then
    error "This installer must be run as root."
    exit 1
fi

# Detect package manager
detect_package_manager() {
    if command -v apt &> /dev/null; then echo "apt"
    elif command -v dnf &> /dev/null; then echo "dnf"
    elif command -v yum &> /dev/null; then echo "yum"
    elif command -v pacman &> /dev/null; then echo "pacman"
    else echo ""; fi
}

# Global flag to track EPEL
EPEL_ENABLED_BEFORE=false

# Install EPEL if necessary
ensure_epel() {
    local PM
    PM=$(detect_package_manager)

    if [[ "$PM" == "dnf" || "$PM" == "yum" ]]; then
        if "$PM" repolist enabled | grep -q "^epel/"; then
            EPEL_ENABLED_BEFORE=true
            info "EPEL repository already enabled."
        else
            info "EPEL repository not found. Installing..."
            "$PM" install -y -q epel-release >/dev/null
            "$PM" config-manager --set-enabled epel >/dev/null 2>&1 || true
            EPEL_ENABLED_BEFORE=false
        fi
    fi
}

# Disable EPEL if script enabled it
cleanup_epel() {
    local PM
    PM=$(detect_package_manager)

    if [[ "$PM" == "dnf" || "$PM" == "yum" ]]; then
        if [[ "$EPEL_ENABLED_BEFORE" == false ]]; then
            info "Disabling EPEL repository..."
            "$PM" config-manager --set-disabled epel >/dev/null 2>&1 || true
        fi
    fi
}

# Install package quietly
install_package() {
    local pkg="$1"
    local PM
    PM=$(detect_package_manager)

    case "$PM" in
        apt)
            DEBIAN_FRONTEND=noninteractive apt update -qq >/dev/null
            DEBIAN_FRONTEND=noninteractive apt install -y -qq "$pkg" >/dev/null
            ;;
        dnf|yum)
            ensure_epel
            "$PM" install -y -q "$pkg" >/dev/null
            ;;
        pacman)
            pacman -Sy --noconfirm --quiet "$pkg" >/dev/null
            ;;
        *)
            error "Unsupported package manager. Please install '$pkg' manually."
            exit 1
            ;;
    esac
}

# Fetch file from URL
fetch() {
    local url="$1"
    local dest="$2"
    if command -v curl &> /dev/null; then
        curl -fsSL "$url" -o "$dest"
    elif command -v wget &> /dev/null; then
        wget -q "$url" -O "$dest"
    else
        warn "Neither curl nor wget found. Installing curl..."
        install_package curl
        curl -fsSL "$url" -o "$dest"
    fi
}

# Uninstall NDPD
uninstall_ndpd() {
    warn "Uninstalling NDPD..."

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        info "Stopping NDPD service..."
        systemctl stop "$SERVICE_NAME"
    fi

    info "Disabling NDPD service..."
    systemctl disable "$SERVICE_NAME" >/dev/null || true

    info "Removing files..."
    rm -f "$BIN_PATH"
    rm -f "$SYSTEMD_PATH"

    info "Reloading systemd..."
    systemctl daemon-reexec
    systemctl daemon-reload

    cleanup_epel

    success "NDPD uninstalled successfully."
    exit 0
}

# Check if already installed
if [[ -f "$BIN_PATH" ]]; then
    warn "NDPD is already installed at $BIN_PATH."
    read -rp "Do you want to uninstall it? (y/N): " CONFIRM
    case "$CONFIRM" in
        [yY][eE][sS]|[yY])
            uninstall_ndpd
            ;;
        *)
            info "Keeping existing installation. Continuing..."
            ;;
    esac
fi

# Check for ndisc6
NDISC6_PATH="$(command -v ndisc6 || true)"
if [[ -z "$NDISC6_PATH" ]]; then
    info "ndisc6 not found. Installing..."
    install_package ndisc6
else
    info "ndisc6 found at: $NDISC6_PATH"
fi

# Download NDPD script
info "Downloading NDPD script..."
fetch "$REPO_RAW/ndpd" "$BIN_PATH"
chmod +x "$BIN_PATH"

# Download systemd service
info "Downloading systemd service file..."
fetch "$REPO_RAW/ndpd.service" "$SYSTEMD_PATH"

# Enable and start service
info "Enabling and starting NDPD service..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable "$SERVICE_NAME" >/dev/null
systemctl start "$SERVICE_NAME"

cleanup_epel

success "NDPD installed and running!"