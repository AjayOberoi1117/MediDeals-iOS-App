#!/bin/bash
#
# Mac Status Script — Check monitoring system status
#

REPO_ROOT="/Users/ajayoberoi/MediDeals-iOS-App"
LAUNCHAGENT_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/Library/Logs/ajay-trading-bot"

echo ""
echo "========================================================================="
echo "OPERATIONS MONITORING SYSTEM STATUS"
echo "========================================================================="
echo ""

# Check LaunchAgents
echo "LaunchAgent Status:"
echo "-------------------"

launchctl list | grep -E "com.ajay.tradingbot" | while read line; do
    pid=$(echo "$line" | awk '{print $1}')
    label=$(echo "$line" | awk '{print $NF}')

    if [ "$pid" != "-" ]; then
        echo "  ✓ $label (running, PID: $pid)"
    else
        echo "  ○ $label (loaded, not running)"
    fi
done

# Check logs
echo ""
echo "Recent Logs:"
echo "------------"

if [ -d "$LOG_DIR" ]; then
    ls -lt "$LOG_DIR"/*.log 2>/dev/null | head -5 | while read -r line; do
        echo "  $(echo $line | awk '{print $NF, "(", $(NF-4), ")"}')"
    done
else
    echo "  No logs found at $LOG_DIR"
fi

# Check bot process
echo ""
echo "Bot Process Status:"
echo "-------------------"

cd "$REPO_ROOT" && python3 ops/process_manager.py status 2>/dev/null || echo "  Unable to check bot process"

# Database status
echo ""
echo "Signal Database:"
echo "----------------"

DB_PATH="$HOME/Library/Application Support/AjayTradingBot/signals.db"
if [ -f "$DB_PATH" ]; then
    SIZE=$(du -h "$DB_PATH" | awk '{print $1}')
    echo "  ✓ Database exists (size: $SIZE)"

    # Check signal count
    COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM signals;" 2>/dev/null || echo "0")
    echo "  Signal ledger: $COUNT signals recorded"
else
    echo "  ○ Database not yet created"
fi

echo ""
echo "========================================================================="
echo ""
