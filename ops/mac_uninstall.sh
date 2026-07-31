#!/bin/bash
#
# Mac Uninstall Script — Removes monitoring LaunchAgents and disables scheduling
#

REPO_ROOT="/Users/ajayoberoi/MediDeals-iOS-App"
LAUNCHAGENT_DIR="$HOME/Library/LaunchAgents"

echo ""
echo "========================================================================="
echo "OPERATIONS MONITORING SYSTEM — Uninstall"
echo "========================================================================="
echo ""

# Unload LaunchAgents
echo "Unloading LaunchAgents..."

for plist in "$LAUNCHAGENT_DIR"/com.ajay.tradingbot*.plist; do
    if [ -f "$plist" ]; then
        launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
        echo "  ✓ $(basename "$plist")"
    fi
done

# Remove plist files
echo ""
echo "Removing plist files..."

for plist in "$LAUNCHAGENT_DIR"/com.ajay.tradingbot*.plist; do
    if [ -f "$plist" ]; then
        rm "$plist"
        echo "  ✓ $(basename "$plist") deleted"
    fi
done

echo ""
echo "========================================================================="
echo "Uninstall Complete"
echo "========================================================================="
echo ""
echo "Notes:"
echo "  • Monitoring has been disabled"
echo "  • Signal database is preserved at:"
echo "    ~/Library/Application Support/AjayTradingBot/signals.db"
echo "  • Logs are preserved at:"
echo "    ~/Library/Logs/ajay-trading-bot/"
echo ""
echo "To reinstall:"
echo "  bash $REPO_ROOT/ops/mac_install.sh"
echo ""
