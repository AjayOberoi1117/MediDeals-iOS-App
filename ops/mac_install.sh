#!/bin/bash
#
# Mac Installation Script — Installs and activates monitoring LaunchAgents
# Run this script on your Mac to install the operations monitoring system
#
# Usage: bash mac_install.sh
#

set -e

REPO_ROOT="/Users/ajayoberoi/MediDeals-iOS-App"
PLIST_SOURCE_DIR="$REPO_ROOT/ops"
LAUNCHAGENT_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/Library/Logs/ajay-trading-bot"
APP_SUPPORT_DIR="$HOME/Library/Application Support/AjayTradingBot"

echo "========================================================================="
echo "OPERATIONS ENGINEER V2 — Mac Installation"
echo "========================================================================="
echo ""

# Verify repo exists
if [ ! -d "$REPO_ROOT" ]; then
    echo "✗ ERROR: Repository not found at $REPO_ROOT"
    exit 1
fi

echo "✓ Repository verified at: $REPO_ROOT"

# Create directories
mkdir -p "$LAUNCHAGENT_DIR" "$LOG_DIR" "$APP_SUPPORT_DIR"
echo "✓ Created required directories"

# Validate plist files
echo ""
echo "Validating plist files..."
for plist in "$PLIST_SOURCE_DIR"/com.ajay.tradingbot*.plist; do
    if [ -f "$plist" ]; then
        if plutil -lint "$plist" > /dev/null 2>&1; then
            echo "  ✓ $(basename "$plist")"
        else
            echo "  ✗ $(basename "$plist") — validation failed"
            exit 1
        fi
    fi
done

# Install LaunchAgents
echo ""
echo "Installing LaunchAgents..."

for plist in "$PLIST_SOURCE_DIR"/com.ajay.tradingbot*.plist; do
    if [ -f "$plist" ]; then
        dest="$LAUNCHAGENT_DIR/$(basename "$plist")"
        cp "$plist" "$dest"
        echo "  ✓ $(basename "$plist")"
    fi
done

# Load LaunchAgents (macOS 10.13+)
echo ""
echo "Loading LaunchAgents..."
for plist in "$LAUNCHAGENT_DIR"/com.ajay.tradingbot*.plist; do
    if [ -f "$plist" ]; then
        launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || true
        echo "  ✓ $(basename "$plist")"
    fi
done

# Verify installation
echo ""
echo "Verifying installation..."
echo ""

launchctl list | grep com.ajay.tradingbot | while read line; do
    label=$(echo "$line" | awk '{print $NF}')
    echo "  ✓ $label is loaded"
done

echo ""
echo "========================================================================="
echo "INSTALLATION COMPLETE"
echo "========================================================================="
echo ""
echo "Configuration:"
echo "  Repository: $REPO_ROOT"
echo "  LaunchAgents: $LAUNCHAGENT_DIR"
echo "  Logs: $LOG_DIR"
echo "  Database: $APP_SUPPORT_DIR/signals.db"
echo ""
echo "Next steps:"
echo "  1. Pre-market check runs daily at 8:45 AM IST (Mon-Fri)"
echo "  2. Bot is auto-restarted if health issues detected"
echo "  3. Reports generated at market close (3:45 PM)"
echo ""
echo "To check status:"
echo "  bash $REPO_ROOT/ops/mac_status.sh"
echo ""
echo "To stop monitoring:"
echo "  bash $REPO_ROOT/ops/mac_uninstall.sh"
echo ""
