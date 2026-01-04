#!/bin/bash
# devbox-setup.sh - Bootstrap nix/devbox environment using host's nix store (deskrun pattern)
#
# === Overview ===
# This script implements the "deskrun pattern" which provides persistent caching across
# CI runs by mounting the host's nix store into the container. The host Docker daemon
# is available at /var/run/docker.sock for container builds.
#
# === Strategy ===
#   1. Copy busybox binary before mounting (provides mount, find, grep, etc.)
#   2. Copy SSL CA certificates before mounting (needed after host store replaces container store)
#   3. Copy GitHub workspace directories from /__w/_temp/_github_* to /github/*
#   4. Bind mount host /nix/store over container's /nix/store
#   5. Bind mount host daemon socket to /nix/var/nix/daemon-socket
#   6. Install devbox and docker client via host nix daemon using flake references
#
# === Volume Mounts (configured in deskrun runner) ===
#   - /nix/store-host        <- Host's nix store (bind mounted to /nix/store in Phase 1)
#   - /nix/var/nix/daemon-socket-host <- Host's nix daemon (bind mounted to /nix/var/nix/daemon-socket in Phase 1)
#   - /var/run/docker.sock   <- Host's docker daemon socket (available for docker client)
#
# === Why Busybox? ===
# After mounting the host store over /nix/store, all Nixery-provided binaries become unavailable
# because their /nix/store paths no longer exist. We copy busybox (single multi-call binary)
# BEFORE mounting to ensure we have essential utilities (mount, mkdir, find, etc.) afterwards.
#
# === Why Copy CA Bundle? ===
# Similar to busybox - the Nixery CA bundle lives in /nix/store and becomes unavailable after
# mounting. We copy it to /etc/ssl/certs/ca-bundle.crt for persistence across workflow steps.
#
# === Container Image Requirements ===
# The Nixery image must include: shell/bash/busybox/gnutar/findutils/gnugrep/coreutils/gzip/cacert
# - busybox: provides mount and utilities for bootstrapping
# - cacert: provides SSL CA certificates
# - Other tools: required by GitHub Actions (actions/checkout@v4, etc.)
#
# === Usage ===
# devbox-setup.sh

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$*"
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$*"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$*"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$*"
}

# ============================================================================
# PHASE 0: Copy Busybox and SSL Certificates Before Mounting
# ============================================================================
# WHY: After mounting host store over /nix/store, all Nixery binaries become inaccessible.
# We copy busybox (provides mount, find, grep, etc.) and SSL certs beforehand so they remain
# available after mounting. Busybox is installed to both /tmp/bootstrap and /bin:
# - /tmp/bootstrap: for use during this script
# - /bin: for persistence across all GitHub Actions workflow steps
log_info "=========================================="
log_info "Devbox Setup Script (deskrun pattern)"
log_info "=========================================="
log_info ""
log_info "Phase 0: Copying busybox before host mount..."

# Create bootstrap directory
BOOTSTRAP_DIR="/tmp/bootstrap"
mkdir -p "$BOOTSTRAP_DIR/bin"

# Find and copy busybox from Nixery's /nix/store
log_info "Finding busybox in Nixery's /nix/store..."
BUSYBOX=$(find /nix/store -path "*/bin/busybox" -type f -o -path "*/bin/busybox" -type l 2>/dev/null | head -1)

if [ -z "$BUSYBOX" ]; then
    log_error "Could not find busybox in /nix/store"
    log_error "Ensure busybox is included in the Nixery container image"
    exit 1
fi

log_success "Found busybox at: $BUSYBOX"

# Copy busybox to bootstrap location (dereference symlinks with -L)
log_info "Copying busybox to $BOOTSTRAP_DIR/bin/busybox..."
if cp -L "$BUSYBOX" "$BOOTSTRAP_DIR/bin/busybox"; then
    chmod +x "$BOOTSTRAP_DIR/bin/busybox"
    log_success "Copied busybox to bootstrap location"
else
    log_error "Failed to copy busybox"
    exit 1
fi

# Verify busybox works
if "$BOOTSTRAP_DIR/bin/busybox" --help >/dev/null 2>&1; then
    log_success "Busybox is functional"
else
    log_error "Busybox copy is not functional"
    exit 1
fi

# Create symlinks for essential commands in bootstrap dir
log_info "Creating busybox command symlinks in $BOOTSTRAP_DIR/bin..."
for cmd in mount mkdir ls find cat grep head tail dirname basename wc tr cut sort uniq; do
    ln -sf busybox "$BOOTSTRAP_DIR/bin/$cmd"
done
log_success "Created command symlinks in bootstrap dir"

# Also copy busybox to /bin and create symlinks there for persistence across GitHub Actions steps
log_info "Installing busybox to /bin for all workflow steps..."
cp "$BOOTSTRAP_DIR/bin/busybox" /bin/busybox
chmod +x /bin/busybox
for cmd in mount mkdir ls find cat grep head tail dirname basename wc tr cut sort uniq; do
    ln -sf busybox "/bin/$cmd"
done
log_success "Busybox installed to /bin with symlinks"

# Copy SSL CA certificates before mounting to a persistent location
# WHY: The CA bundle from Nixery lives in /nix/store and will be inaccessible after mounting.
# Copying to /etc/ssl/certs/ca-bundle.crt ensures SSL works in all workflow steps.
# This is critical for 'nix profile install' which needs to fetch packages over HTTPS.
log_info "Copying SSL CA certificates..."
mkdir -p /etc/ssl/certs
# Try to find and copy CA bundle from Nixery's nix store
CA_BUNDLE=$(find /nix/store -path "*/etc/ssl/certs/ca-bundle.crt" -type f 2>/dev/null | head -1)
if [ -n "$CA_BUNDLE" ]; then
    # Copy to /etc/ssl/certs for persistence across all workflow steps
    cp "$CA_BUNDLE" /etc/ssl/certs/ca-bundle.crt
    log_success "Copied CA bundle to /etc/ssl/certs/ca-bundle.crt"
    # Set the persistent path for use after mounting
    PERSISTENT_CA_BUNDLE="/etc/ssl/certs/ca-bundle.crt"
else
    log_warn "Could not find CA bundle in /nix/store, SSL may not work"
    PERSISTENT_CA_BUNDLE=""
fi

# Add bootstrap dir to PATH (highest priority)
export PATH="$BOOTSTRAP_DIR/bin:$PATH"

log_info ""
log_success "Phase 0: Busybox bootstrap tools ready"
echo ""

# ============================================================================
# PHASE 0.5: Setup GitHub Workspace Directories
# ============================================================================
# WHY: The deskrun k8s-novolume hooks copy GitHub workspace files from the runner pod
# to the workflow pod, placing them in /__w/_temp/_github_*. We need to copy them to
# /github/* where GitHub Actions expects them (particularly /github/workflow/event.json).
#
# TIMING: This must be done in the main container (not init container) because:
# - Init containers run BEFORE k8s-novolume hooks execute
# - When init container runs, /__w/_temp/_github_* directories are empty
# - By the time this script runs, hooks have completed and files are available
#
# See: https://github.com/rkoster/deskrun/issues/28
log_info "Phase 0.5: Setting up GitHub workspace directories..."

# Check if source directories exist
if [ -d "/__w/_temp/_github_workflow" ] || [ -d "/__w/_temp/_github_home" ]; then
    log_info "Found GitHub workspace directories in /__w/_temp/"
    
    # Create target directories
    mkdir -p /github/workflow
    mkdir -p /github/home
    
    # Copy workflow directory (contains event.json)
    if [ -d "/__w/_temp/_github_workflow" ]; then
        log_info "Copying /__w/_temp/_github_workflow to /github/workflow..."
        if cp -R /__w/_temp/_github_workflow/. /github/workflow/; then
            log_success "Copied workflow directory"
            # List what was copied for debugging
            if [ -f "/github/workflow/event.json" ]; then
                log_info "  ✓ event.json is available at /github/workflow/event.json"
            fi
        else
            log_error "Failed to copy workflow directory"
            exit 1
        fi
    else
        log_warn "/__w/_temp/_github_workflow not found (may not be needed for this workflow)"
    fi
    
    # Copy home directory
    if [ -d "/__w/_temp/_github_home" ]; then
        log_info "Copying /__w/_temp/_github_home to /github/home..."
        if cp -R /__w/_temp/_github_home/. /github/home/; then
            log_success "Copied home directory"
        else
            log_error "Failed to copy home directory"
            exit 1
        fi
    else
        log_warn "/__w/_temp/_github_home not found (may not be needed for this workflow)"
    fi
    
    log_success "Phase 0.5: GitHub workspace directories setup complete"
else
    log_info "No GitHub workspace directories found in /__w/_temp/ (skipping)"
    log_info "This is normal if not running in deskrun environment"
fi

echo ""

# ============================================================================
# PHASE 1: Mount Host Store and Find Host Nix
# ============================================================================
log_info "Phase 1: Mounting host store and finding host nix..."

# Verify host store is available
if [ ! -d "/nix/store-host" ]; then
    log_error "Host nix store not found at /nix/store-host"
    log_error "Ensure runner is configured to mount host /nix/store at /nix/store-host"
    exit 1
fi
log_success "Found host store at /nix/store-host"

# Verify daemon socket
if [ ! -S "/nix/var/nix/daemon-socket-host/socket" ]; then
    log_error "Host nix daemon socket not found at /nix/var/nix/daemon-socket-host/socket"
    log_error "Ensure nix-daemon is running on host and socket is mounted"
    exit 1
fi
log_success "Found nix daemon socket"

# Mount host store over container's /nix/store
log_info "Mounting host store at /nix/store..."
if mount --bind /nix/store-host /nix/store; then
    log_success "Host store mounted at /nix/store"
else
    log_error "Failed to mount host store"
    log_error "Ensure container is running with --privileged"
    exit 1
fi

# Mount daemon socket directory
log_info "Mounting daemon socket at /nix/var/nix/daemon-socket..."
mkdir -p /nix/var/nix/daemon-socket
if mount --bind /nix/var/nix/daemon-socket-host /nix/var/nix/daemon-socket; then
    log_success "Daemon socket mounted at /nix/var/nix/daemon-socket"
else
    log_error "Failed to mount daemon socket"
    log_error "Ensure container is running with --privileged"
    exit 1
fi

# Find nix-env in host store (now mounted at /nix/store)
# WHY LS PATTERN VS FIND:
# Using 'ls -d /nix/store/*-nix-*/bin/nix-env' is 10-100x faster than recursive find
# on large nix stores. The pattern directly matches nix package directories.
log_info "Searching for nix-env in host store..."
NIX_ENV=$(ls -d /nix/store/*-nix-*/bin/nix-env 2>/dev/null | head -1)

if [ -z "$NIX_ENV" ]; then
    log_error "Could not find nix-env in /nix/store"
    log_error "Ensure nix is installed on the host"
    exit 1
fi

log_success "Found nix-env at: $NIX_ENV"

# Get the nix package directory
NIX_BIN_DIR=$(dirname "$NIX_ENV")
log_info "Nix bin directory: $NIX_BIN_DIR"

# Add to PATH (after bootstrap dir)
export PATH="$BOOTSTRAP_DIR/bin:$NIX_BIN_DIR:$PATH"

log_success "Phase 1: Host store mounted and nix found"
echo ""

# ============================================================================
# PHASE 2: Configure Nix Environment
# ============================================================================
# Configure nix.conf with:
# - build-users-group = (empty, not needed with daemon mode)
# - experimental-features (needed for 'nix profile install' command)
# - ssl-cert-file (points to our persistent CA bundle)
#
# We use the host's nix daemon, so we DON'T need to:
# - Set up channels (host already has them)
# - Run 'nix store ping' test (can fail with cert issues, not necessary)
log_info "Phase 2: Configuring nix environment..."

# Use the persistent CA bundle we copied in Phase 0
# (We can't use /nix/store paths here because host store is now mounted)
if [ -n "$PERSISTENT_CA_BUNDLE" ]; then
    CA_BUNDLE="$PERSISTENT_CA_BUNDLE"
    log_info "Using persistent CA bundle: $CA_BUNDLE"
else
    log_warn "No persistent CA bundle available, SSL may not work"
    CA_BUNDLE="/etc/ssl/certs/ca-bundle.crt"
fi

mkdir -p /etc/nix
cat > /etc/nix/nix.conf <<EOF
build-users-group =
experimental-features = nix-command flakes
ssl-cert-file = $CA_BUNDLE
EOF
log_success "Nix configured with experimental features and SSL certs"

# Also export NIX_SSL_CERT_FILE for nix commands
export NIX_SSL_CERT_FILE="$CA_BUNDLE"

# Connect to host daemon
# WHY TWO VARIABLES:
# - NIX_REMOTE=daemon tells nix to use the daemon
# - NIX_DAEMON_SOCKET_PATH specifies socket location  
# Older nix versions don't support the 'daemon?socket=' format, so we use separate variables.
log_info "Connecting to host nix daemon..."
export NIX_REMOTE="daemon"
export NIX_DAEMON_SOCKET_PATH="/nix/var/nix/daemon-socket/socket"

# Note: We skip channel setup and ping test since we're using the host's daemon
# The host already has channels configured, and we'll use nix-env directly
log_success "NIX_REMOTE configured to use host daemon"
log_info "Daemon socket: $NIX_DAEMON_SOCKET_PATH"

log_success "Phase 2: Nix environment configured"
echo ""

# ============================================================================
# PHASE 3: Install Required Packages
# ============================================================================
# Install devbox and docker client using 'nix profile install' with flake references (nixpkgs#package).
# The docker client connects to the host Docker daemon at /var/run/docker.sock (no need to start dockerd).
# 
# WHY FLAKE REFERENCES:
# - Don't require local nix channels to be configured
# - Work directly with host daemon without channel setup
# - Modern nix approach (vs old nix-env -iA which needs channels)
#
# ALTERNATIVES TRIED:
# - nix-env -iA nixpkgs.package: Failed because container doesn't have nixpkgs channel
# - nix-env -i package: Failed with "attribute not found" errors  
# - Searching host store: Too slow and fragile (packages move between builds)
# - nix bundle: Too complex and unnecessary for this use case
#
# Packages install to ~/.nix-profile/bin which we add to PATH
log_info "Phase 3: Installing required packages..."

# Install devbox
log_info "Installing devbox from nixpkgs flake..."
if nix profile install nixpkgs#devbox 2>&1 | head -20; then
    log_success "Installed devbox"
else
    log_error "Failed to install devbox"
    exit 1
fi
log_info ""

# Install docker client
log_info "Installing docker client from nixpkgs flake..."
if nix profile install nixpkgs#docker 2>&1 | head -20; then
    log_success "Installed docker client"
else
    log_error "Failed to install docker client"
    exit 1
fi
log_info ""

# Nix profile installs to ~/.nix-profile, add to PATH
export PATH="$HOME/.nix-profile/bin:$PATH"

# Verify installations
log_info "Verifying installations..."
if command -v devbox >/dev/null 2>&1; then
    DEVBOX_VERSION=$(devbox version 2>&1 | head -1 || echo "unknown")
    log_success "devbox is available: $DEVBOX_VERSION"
else
    log_error "devbox not found in PATH after installation"
    exit 1
fi

if command -v docker >/dev/null 2>&1; then
    DOCKER_VERSION=$(docker --version 2>&1 | head -1 || echo "unknown")
    log_success "docker client is available: $DOCKER_VERSION"
    
    # Verify docker can connect to host daemon
    if [ -S "/var/run/docker.sock" ]; then
        log_info "Verifying connection to host Docker daemon..."
        if docker info >/dev/null 2>&1; then
            log_success "Successfully connected to host Docker daemon"
        else
            log_warn "Docker socket exists but connection failed (this may be normal if daemon is not yet ready)"
        fi
    else
        log_warn "Docker socket /var/run/docker.sock not found (ensure host daemon socket is mounted)"
    fi
else
    log_error "docker client not found in PATH after installation"
    exit 1
fi

log_success "Phase 3: Package installation complete"
echo ""

# ============================================================================
# Export Environment Variables for GitHub Actions
# ============================================================================
log_info "Exporting environment variables for subsequent steps..."

# Persist environment variables for GitHub Actions using GITHUB_ENV
if [ -n "$GITHUB_ENV" ]; then
    echo "NIX_REMOTE=daemon" >> "$GITHUB_ENV"
    echo "NIX_DAEMON_SOCKET_PATH=/nix/var/nix/daemon-socket/socket" >> "$GITHUB_ENV"
    echo "NIX_SSL_CERT_FILE=$CA_BUNDLE" >> "$GITHUB_ENV"
    # Also export standard SSL cert variables for devbox, curl, and other tools
    echo "SSL_CERT_FILE=$CA_BUNDLE" >> "$GITHUB_ENV"
    echo "CURL_CA_BUNDLE=$CA_BUNDLE" >> "$GITHUB_ENV"
    echo "PATH=$HOME/.nix-profile/bin:$BOOTSTRAP_DIR/bin:$PATH" >> "$GITHUB_ENV"
    log_success "Environment variables exported to GITHUB_ENV"
else
    log_warn "GITHUB_ENV not set (not running in GitHub Actions?)"
    log_warn "Subsequent steps may need to source environment manually"
fi

echo ""

# ============================================================================
# Summary
# ============================================================================
log_success "=========================================="
log_success "Devbox setup complete!"
log_success "=========================================="
log_info ""
log_info "Environment variables set:"
log_info "  NIX_REMOTE=daemon"
log_info "  NIX_DAEMON_SOCKET_PATH=/nix/var/nix/daemon-socket/socket"
log_info "  PATH includes ~/.nix-profile/bin"
log_info ""
log_info "Installed tools:"
log_info "  - devbox"
log_info "  - docker client (connects to host daemon at /var/run/docker.sock)"
log_info ""
log_info "Bootstrap tools preserved at: $BOOTSTRAP_DIR/bin"
log_info "Host nix store mounted at: /nix/store"
log_info ""
log_info "To use these in subsequent steps, ensure:"
log_info "  - NIX_REMOTE and NIX_DAEMON_SOCKET_PATH are set"
log_info "  - PATH includes \$HOME/.nix-profile/bin"
