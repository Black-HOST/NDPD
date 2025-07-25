#!/bin/bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/Black-HOST/NDPD/master"
BIN_PATH="/usr/local/bin/ndpd"
SYSTEMD_PATH="/etc/systemd/system/ndpd.service"
SERVICE_NAME="ndpd.service"

# Color Output Helpers
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m" # No Color

info()    { echo -e "${BLUE}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[-]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }

# Root Check
info "Checking root permissions..."
if [[ $EUID -ne 0 ]]; then
    error "This installer must be run as root."
    exit 1
fi

# Detect Package Manager
detect_package_manager() {
    if command -v apt &> /dev/null; then echo "apt"
    elif command -v dnf &> /dev/null; then echo "dnf"
    elif command -v yum &> /dev/null; then echo "yum"
    elif command -v pacman &> /dev/null; then echo "pacman"
    else echo ""; fi
}

prepare_epel() {
    local PM
    PM=$(detect_package_manager)

    if [[ "$PM" == "yum" || "$PM" == "dnf" ]]; then
        if ! "$PM" repolist enabled | grep -q "^epel/"; then
            if ! rpm -q epel-release &>/dev/null; then
                info "EPEL repository not installing. Installing and disabling it..."
                "$PM" install -y -q epel-release >/dev/null
                sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/epel.repo
            else
                info "EPEL repository is installed but disabled."
            fi
        else
            info "EPEL repository is already enabled."
        fi
    fi
}

# Install a package quietly
install_package() {
    local pkg="$1"
    local PM
    PM=$(detect_package_manager)

    case "$PM" in
        apt)
            DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg" >/dev/null
            ;;
        dnf|yum)
            "$PM" install -y -q --enablerepo="epel" "$pkg" >/dev/null
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

# Download file using curl or wget
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

    success "NDPD uninstalled successfully."
    exit 0
}

# Check for existing installation
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

# Check if ndisc6 is installed, prepare EPEL if needed
NDISC6_PATH="$(command -v ndisc6 || true)"
if [[ -z "$NDISC6_PATH" ]]; then
    prepare_epel
    info "ndisc6 not found. Installing..."
    install_package ndisc6
else
    info "ndisc6 found at: $NDISC6_PATH"
fi

# Install NDPD
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

success "NDPD installed and running!"