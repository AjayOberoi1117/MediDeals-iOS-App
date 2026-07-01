#!/bin/bash
# Run once on Mac to install deps and start all trading bots as launchd services.
# Usage: bash telegram_bot/mac_setup.sh

set -e
cd "$(dirname "$0")/.."

echo "=== Installing Python dependencies ==="
pip3 install --user --break-system-packages pandas yfinance requests python-dotenv pytz

echo ""
echo "=== Copying launchd plists ==="
cp telegram_bot/com.medideals.forex-scalper.plist  ~/Library/LaunchAgents/
cp telegram_bot/com.medideals.india-scalper.plist  ~/Library/LaunchAgents/
cp telegram_bot/com.medideals.scanner-bot.plist    ~/Library/LaunchAgents/
cp telegram_bot/com.medideals.signal_sync.plist    ~/Library/LaunchAgents/

echo ""
echo "=== Unloading signal_sync (no longer needed) ==="
launchctl unload ~/Library/LaunchAgents/com.medideals.signal_sync.plist 2>/dev/null || true

echo ""
echo "=== Loading bots ==="
launchctl load ~/Library/LaunchAgents/com.medideals.forex-scalper.plist
launchctl load ~/Library/LaunchAgents/com.medideals.india-scalper.plist
launchctl load ~/Library/LaunchAgents/com.medideals.scanner-bot.plist

echo ""
echo "=== Done! Logs ==="
echo "  Forex scalper : tail -f /tmp/forex-scalper.log"
echo "  India scalper : tail -f /tmp/india-scalper.log"
echo "  Scanner bot   : tail -f /tmp/scanner-bot.log"
echo ""
echo "Remember to stop GCP bots:"
echo "  systemctl --user stop forex-scalper india-scalper"
