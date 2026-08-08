#!/usr/bin/env bash
################################################################################
# Fix Wine 11 RpcSs Service Initialization on Ubuntu 24.04
# =========================================================
#
# Diagnoses and resolves "Failed to open RpcSs service" error.
# Root causes:
# 1. Missing i386 architecture support
# 2. Wine packages incomplete (Ubuntu 9 residue vs WineHQ 11 conflict)
# 3. Missing system dependencies (libfaudio0, gnutls, etc)
#
# Usage:
#   sudo bash fix_wine11_rpcss.sh
#
# Prerequisites:
#   - Ubuntu 24.04 LTS
#   - Root access
#
# Preserves:
#   - /root/.wine_mt5 backup
#   - Repository
#   - Credentials
#
################################################################################

set -euo pipefail

readonly WINE_PREFIX="/root/.wine_mt5_w11"
readonly BACKUP_PREFIX="/root/.wine_mt5_backup_$(date +%s)"

################################################################################
# COLORS
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_ok() {
    echo -e "${GREEN}✓${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

echo_error() {
    echo -e "${RED}✗${NC} $1"
}

################################################################################
# PHASE 1: DIAGNOSIS
################################################################################

diagnose() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "PHASE 1: Diagnosis"
    echo "════════════════════════════════════════════════════════════════════"

    echo ""
    echo "Checking Wine installation..."

    if ! command -v wine &> /dev/null; then
        echo_error "Wine not found in PATH"
        return 1
    fi

    local wine_version=$(wine --version 2>/dev/null || echo "unknown")
    echo_ok "Wine installed: $wine_version"

    echo ""
    echo "Checking i386 architecture support..."
    if dpkg --print-foreign-architectures | grep -q i386; then
        echo_ok "i386 architecture enabled"
    else
        echo_error "i386 architecture NOT enabled"
        echo "  Ubuntu Wine requires 32-bit support"
        return 1
    fi

    echo ""
    echo "Checking Wine packages..."
    local wineqt=$(dpkg -l | grep wine-stable-i386 | awk '{print $1}' || echo "un")
    if [[ "$wineqt" != "ii" ]]; then
        echo_error "wine-stable-i386 not installed"
        return 1
    fi
    echo_ok "wine-stable-i386 installed"

    echo ""
    echo "Checking conflicting Wine versions..."
    local ubuntu_wine=$(dpkg -l | grep -v winehq | grep "^ii" | grep wine | wc -l || echo 0)
    if [[ $ubuntu_wine -gt 0 ]]; then
        echo_warn "Found $ubuntu_wine Ubuntu Wine packages (may conflict with WineHQ)"
    else
        echo_ok "No conflicting Ubuntu Wine packages"
    fi

    echo ""
    echo "Checking system dependencies..."
    local missing=0
    for pkg in libfaudio0 libgnutls30 libpulse0 libgstreamer1.0-0; do
        if dpkg -l | grep -q "^ii.*$pkg"; then
            echo_ok "$pkg installed"
        else
            echo_error "$pkg NOT installed"
            ((missing++)) || true
        fi
    done

    if [[ $missing -gt 0 ]]; then
        echo_warn "Missing $missing critical library packages"
        return 1
    fi

    return 0
}

################################################################################
# PHASE 2: FIX MISSING i386 ARCHITECTURE
################################################################################

enable_i386() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "PHASE 2: Enable i386 Architecture"
    echo "════════════════════════════════════════════════════════════════════"

    if dpkg --print-foreign-architectures | grep -q i386; then
        echo_ok "i386 architecture already enabled"
        return 0
    fi

    echo ""
    echo "Adding i386 architecture..."
    dpkg --add-architecture i386
    echo_ok "i386 architecture added"

    echo ""
    echo "Updating package cache..."
    apt-get update -qq
    echo_ok "Package cache updated"

    return 0
}

################################################################################
# PHASE 3: INSTALL/REINSTALL WINE 11 CLEANLY
################################################################################

install_wine11() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "PHASE 3: Ensure Wine 11 (WineHQ Stable) Installation"
    echo "════════════════════════════════════════════════════════════════════"

    echo ""
    echo "Checking for WineHQ repository..."
    if [[ ! -f /etc/apt/sources.list.d/winehq-ubuntu.sources ]]; then
        echo_warn "WineHQ repository not found, adding..."

        # Add WineHQ GPG key
        mkdir -p /etc/apt/keyrings
        wget -q -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key

        # Add WineHQ repository
        echo "deb [signed-by=/etc/apt/keyrings/winehq-archive.key] https://dl.winehq.org/wine-builds/ubuntu $(lsb_release -cs) main" \
            | tee /etc/apt/sources.list.d/winehq-ubuntu.sources

        echo_ok "WineHQ repository added"

        echo ""
        echo "Updating package cache..."
        apt-get update -qq
        echo_ok "Package cache updated"
    else
        echo_ok "WineHQ repository already configured"
    fi

    echo ""
    echo "Installing Wine 11 (stable)..."

    # Ensure i386 packages are available
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        wine-stable:i386 wine-stable:amd64 \
        wine-stable-amd64 wine-stable-i386 \
        wine-stable-dev wine-stable-i386:i386 \
        libfaudio0:i386 libfaudio0:amd64 \
        fonts-liberation fonts-dejavu \
        ca-certificates 2>&1 | grep -v "^Get:\|^Hit:\|^Reading\|^Building" || true

    echo_ok "Wine 11 installed"

    return 0
}

################################################################################
# PHASE 4: CLEAN OLD PREFIX
################################################################################

clean_old_prefix() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "PHASE 4: Clean Old Wine Prefix"
    echo "════════════════════════════════════════════════════════════════════"

    echo ""
    echo "Killing Wine processes..."
    pkill -9 wineserver 2>/dev/null || true
    pkill -9 wine 2>/dev/null || true
    pkill -9 explorer.exe 2>/dev/null || true
    pkill -9 svchost.exe 2>/dev/null || true
    sleep 2
    echo_ok "Wine processes terminated"

    if [[ -d "$WINE_PREFIX" ]]; then
        echo ""
        echo "Removing old prefix: $WINE_PREFIX"
        rm -rf "$WINE_PREFIX"
        echo_ok "Old prefix removed"
    fi

    echo ""
    echo "Creating fresh prefix directory..."
    mkdir -p "$WINE_PREFIX"
    echo_ok "Prefix directory created"

    return 0
}

################################################################################
# PHASE 5: INITIALIZE FRESH PREFIX
################################################################################

init_fresh_prefix() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "PHASE 5: Initialize Fresh Wine Prefix"
    echo "════════════════════════════════════════════════════════════════════"

    echo ""
    echo "Setting environment..."
    export WINEPREFIX="$WINE_PREFIX"
    export WINEARCH="win64"
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    echo_ok "Environment configured"

    echo ""
    echo "Running wineboot --init (this may take 2-3 minutes)..."

    if WINEPREFIX="$WINE_PREFIX" WINEARCH=win64 wineboot --init 2>&1; then
        echo_ok "wineboot --init succeeded"
    else
        echo_error "wineboot --init failed"
        echo ""
        echo "Checking Wine runtime..."
        wineserver -p 2>/dev/null || true
        return 1
    fi

    return 0
}

################################################################################
# PHASE 6: VERIFY PREFIX
################################################################################

verify_prefix() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "PHASE 6: Verify Prefix"
    echo "════════════════════════════════════════════════════════════════════"

    export WINEPREFIX="$WINE_PREFIX"
    export WINEARCH="win64"

    echo ""
    echo "Testing: wine cmd /c ver"

    if WINEPREFIX="$WINE_PREFIX" WINEARCH=win64 wine cmd /c ver 2>&1; then
        echo_ok "wine cmd /c ver succeeded (RpcSs working)"
    else
        echo_error "wine cmd /c ver failed"
        return 1
    fi

    echo ""
    echo "Checking Wine server..."
    if WINEPREFIX="$WINE_PREFIX" wineserver -p 2>&1 | grep -q "Wine"; then
        echo_ok "Wine server responsive"
    else
        echo_warn "Wine server check unclear"
    fi

    return 0
}

################################################################################
# MAIN
################################################################################

main() {
    if [[ $EUID -ne 0 ]]; then
        echo_error "This script must be run as root (use: sudo bash fix_wine11_rpcss.sh)"
        exit 1
    fi

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "Wine 11 RpcSs Fix for Ubuntu 24.04"
    echo "════════════════════════════════════════════════════════════════════"

    # Phase 1: Diagnosis
    if ! diagnose; then
        echo ""
        echo_error "Diagnosis failed"
        echo ""
        echo "Common causes:"
        echo "  1. i386 architecture not enabled"
        echo "  2. WineHQ packages not installed"
        echo "  3. Missing system dependencies"
        echo "  4. Conflicting Ubuntu Wine 9 packages"
        echo ""
        exit 1
    fi

    # Phase 2: Enable i386
    if ! enable_i386; then
        echo_error "Failed to enable i386 architecture"
        exit 1
    fi

    # Phase 3: Install Wine 11
    if ! install_wine11; then
        echo_error "Failed to install Wine 11"
        exit 1
    fi

    # Phase 4: Clean old prefix
    if ! clean_old_prefix; then
        echo_error "Failed to clean old prefix"
        exit 1
    fi

    # Phase 5: Initialize fresh prefix
    if ! init_fresh_prefix; then
        echo_error "Failed to initialize fresh prefix"
        echo ""
        echo "Troubleshooting:"
        echo "  • Check disk space: df -h"
        echo "  • Check Wine installation: wine --version"
        echo "  • Check wineserver: which wineserver"
        echo "  • Manual test: WINEPREFIX=/tmp/test WINEARCH=win64 wineboot --init"
        exit 1
    fi

    # Phase 6: Verify
    if ! verify_prefix; then
        echo_error "Failed to verify prefix"
        exit 1
    fi

    # Success
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo_ok "WINE 11 PREFIX INITIALIZATION FIXED"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""
    echo "Prefix location: $WINE_PREFIX"
    echo ""
    echo "Next: Install MT5"
    echo "  cd /root/MediDeals-iOS-App/telegram_bot"
    echo "  export WINEPREFIX=$WINE_PREFIX"
    echo "  export WINEARCH=win64"
    echo "  # Install MT5 here"
    echo ""
    exit 0
}

main "$@"
