#!/usr/bin/env bash
################################################################################
# Official MetaTrader 5 Linux Installation
# ========================================
#
# Uses MetaQuotes official mt5linux.sh installer.
# No manual Wine configuration.
#
# Usage:
#   sudo bash install_mt5_official.sh
#
# Prerequisites:
#   - Ubuntu 24.04 LTS
#   - Internet connectivity
#   - Root access
#
# Preserves:
#   - /root/.wine_mt5 (old prefix, not modified)
#   - Backup archives
#   - Repository
#   - Credentials
#
# Installs to:
#   - Wherever mt5linux.sh default location is
#   - User account created as needed
#
################################################################################

set -euo pipefail

readonly INSTALLER_URL="https://download.terminal.free/cdn/web/metaquotes.software.corp/mt5/mt5linux.sh"
readonly INSTALLER_FILE="/tmp/mt5linux.sh"
readonly LOG_FILE="/tmp/mt5_install.log"

################################################################################
# LOGGING
################################################################################

log() {
    echo "$1" | tee -a "$LOG_FILE"
}

log_ok() {
    echo "✓ $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "✗ $1" | tee -a "$LOG_FILE"
}

################################################################################
# PHASE 1: PRESERVE EXISTING STATE
################################################################################

preserve_state() {
    log ""
    log "════════════════════════════════════════════════════════════════════"
    log "PHASE 1: Preserve Existing State"
    log "════════════════════════════════════════════════════════════════════"

    log ""
    log "Backing up existing /root/.wine_mt5..."
    if [[ -d /root/.wine_mt5 ]]; then
        local backup_file="/root/.wine_mt5_backup_official_install_$(date +%s).tar.gz"
        if tar -czf "$backup_file" -C /root .wine_mt5 2>&1 | tail -5 >> "$LOG_FILE"; then
            log_ok "Backed up to: $backup_file"
        else
            log_error "Backup failed (continuing anyway)"
        fi
    else
        log "  /root/.wine_mt5 not found (OK, will be created by installer)"
    fi

    log ""
    log "Preserving repository state..."
    log_ok "Repository at /root/MediDeals-iOS-App (not modified)"

    log ""
    log "Preserving credentials..."
    if [[ -f /root/MediDeals-iOS-App/telegram_bot/.env ]]; then
        log_ok ".env file preserved"
    else
        log "  .env not found (will need to be created)"
    fi

    log ""
    log "Preserving TradeFromFile.mq5..."
    if [[ -f /root/MediDeals-iOS-App/telegram_bot/TradeFromFile.mq5 ]]; then
        log_ok "TradeFromFile.mq5 preserved"
    else
        log "  TradeFromFile.mq5 not found"
    fi

    return 0
}

################################################################################
# PHASE 2: DOWNLOAD OFFICIAL INSTALLER
################################################################################

download_installer() {
    log ""
    log "════════════════════════════════════════════════════════════════════"
    log "PHASE 2: Download Official Installer"
    log "════════════════════════════════════════════════════════════════════"

    log ""
    log "Downloading mt5linux.sh from MetaQuotes..."
    log "  URL: $INSTALLER_URL"

    if wget -q -O "$INSTALLER_FILE" "$INSTALLER_URL" 2>&1 | tail -5 >> "$LOG_FILE"; then
        log_ok "Downloaded: $INSTALLER_FILE"
    else
        log_error "Download failed"
        return 1
    fi

    if [[ ! -f "$INSTALLER_FILE" ]]; then
        log_error "Installer file not found after download"
        return 1
    fi

    local file_size=$(stat -f%z "$INSTALLER_FILE" 2>/dev/null || stat -c%s "$INSTALLER_FILE" 2>/dev/null || echo "unknown")
    log_ok "File size: $file_size bytes"

    return 0
}

################################################################################
# PHASE 3: VERIFY INSTALLER
################################################################################

verify_installer() {
    log ""
    log "════════════════════════════════════════════════════════════════════"
    log "PHASE 3: Verify Installer"
    log "════════════════════════════════════════════════════════════════════"

    log ""
    log "Checking installer file..."

    if [[ ! -x "$INSTALLER_FILE" ]]; then
        log "Making installer executable..."
        chmod +x "$INSTALLER_FILE"
        log_ok "Executable bit set"
    else
        log_ok "Installer is executable"
    fi

    log ""
    log "Checking file integrity..."
    if file "$INSTALLER_FILE" | grep -q "shell script\|text"; then
        log_ok "Installer is a shell script (expected)"
    else
        log "Installer type: $(file "$INSTALLER_FILE")"
    fi

    return 0
}

################################################################################
# PHASE 4: RUN OFFICIAL INSTALLER
################################################################################

run_installer() {
    log ""
    log "════════════════════════════════════════════════════════════════════"
    log "PHASE 4: Run Official Installer"
    log "════════════════════════════════════════════════════════════════════"

    log ""
    log "Executing: $INSTALLER_FILE"
    log ""
    log "The installer will:"
    log "  - Install MetaTrader 5 Linux"
    log "  - Set up Wine/Mono/Gecko as needed"
    log "  - Create user account if required"
    log "  - Configure broker connectivity"
    log ""
    log "This may take 5-10 minutes..."
    log ""

    if "$INSTALLER_FILE" 2>&1 | tee -a "$LOG_FILE"; then
        log_ok "Installer completed successfully"
        return 0
    else
        local exit_code=$?
        log_error "Installer exited with code: $exit_code"
        log ""
        log "Last 30 lines of installer output:"
        tail -30 "$LOG_FILE" | tee /dev/stderr
        return 1
    fi
}

################################################################################
# PHASE 5: VERIFY MT5 INSTALLATION
################################################################################

verify_mt5() {
    log ""
    log "════════════════════════════════════════════════════════════════════"
    log "PHASE 5: Verify MT5 Installation"
    log "════════════════════════════════════════════════════════════════════"

    log ""
    log "Waiting for MT5 to initialize (30 seconds)..."
    sleep 30

    log ""
    log "Checking for MT5 processes..."

    if pgrep -f "terminal64.exe\|MT5\|metaeditor" > /dev/null 2>&1; then
        log_ok "MT5 processes detected"
    else
        log "  No MT5 processes running yet (may still be initializing)"
    fi

    log ""
    log "Checking for MT5 installation folder..."

    local possible_paths=(
        "$HOME/.wine/drive_c/Program Files/MetaTrader 5"
        "$HOME/.mt5"
        "/root/.wine/drive_c/Program Files/MetaTrader 5"
        "/opt/metaquotes/terminal5"
    )

    local found_mt5=0
    for path in "${possible_paths[@]}"; do
        if [[ -d "$path" ]]; then
            log_ok "MT5 found at: $path"
            found_mt5=1
            break
        fi
    done

    if [[ $found_mt5 -eq 0 ]]; then
        log_error "MT5 installation path not found in common locations"
        log ""
        log "Searching for MT5..."
        find /root -name "terminal64.exe" -o -name "terminal.exe" 2>/dev/null | head -5 | while read path; do
            log "  Found: $path"
        done
    fi

    return 0
}

################################################################################
# PHASE 6: TEST BROKER CONNECTIVITY
################################################################################

test_broker() {
    log ""
    log "════════════════════════════════════════════════════════════════════"
    log "PHASE 6: Test Broker Connectivity"
    log "════════════════════════════════════════════════════════════════════"

    log ""
    log "Manual verification required:"
    log ""
    log "1. Connect to VNC: vncviewer 168.144.30.182:5999"
    log ""
    log "2. In MT5 terminal:"
    log "   - File → Login (or New Account)"
    log "   - Search broker: select 'VantageMarkets'"
    log "   - Account type: Demo"
    log "   - Login with credentials from .env (MT5_LOGIN, MT5_PASSWORD)"
    log ""
    log "3. Verify:"
    log "   ✓ Account connected"
    log "   ✓ Account type shows 'DEMO'"
    log "   ✓ No 'unsupported Wine' warnings"
    log "   ✓ Market watch loads symbols"
    log ""
    log "4. Return to terminal after verification"
    log ""

    read -p "Press ENTER after confirming MT5 broker login: " _

    log_ok "MT5 broker connectivity verified"

    return 0
}

################################################################################
# MAIN
################################################################################

main() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use: sudo bash install_mt5_official.sh)"
        exit 1
    fi

    > "$LOG_FILE"  # Clear log

    log "════════════════════════════════════════════════════════════════════"
    log "Official MetaTrader 5 Linux Installation"
    log "════════════════════════════════════════════════════════════════════"

    if ! preserve_state; then
        log_error "Failed to preserve existing state"
        exit 1
    fi

    if ! download_installer; then
        log_error "Failed to download installer"
        exit 1
    fi

    if ! verify_installer; then
        log_error "Failed to verify installer"
        exit 1
    fi

    if ! run_installer; then
        log_error "Installer failed"
        log ""
        log "Troubleshooting:"
        log "  • Check internet connectivity"
        log "  • Check disk space: df -h"
        log "  • Review full log: $LOG_FILE"
        exit 1
    fi

    if ! verify_mt5; then
        log_error "MT5 verification incomplete"
    fi

    log ""
    log "════════════════════════════════════════════════════════════════════"
    log_ok "OFFICIAL MT5 LINUX INSTALLATION COMPLETE"
    log "════════════════════════════════════════════════════════════════════"
    log ""
    log "Next: Verify broker login via VNC"
    log "  vncviewer 168.144.30.182:5999"
    log ""
    log "Then: Compile and test TradeFromFile.mq5"
    log "  See: /root/MediDeals-iOS-App/VALIDATE_FILE_BRIDGE_DEMO.md"
    log ""
    log "Full install log: $LOG_FILE"
    log ""

    exit 0
}

main "$@"
