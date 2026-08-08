#!/usr/bin/env bash
################################################################################
# Cleanup Duplicate Bot Processes
# ================================
#
# Removes duplicate generations of bot processes.
# Keeps only ONE intended instance per bot.
#
# Usage:
#   sudo bash cleanup_duplicate_bots.sh
#
# Safety:
#   - Lists duplicates before removing
#   - Asks for confirmation
#   - Does not touch signal bots (preserve them)
#
################################################################################

set -euo pipefail

echo "════════════════════════════════════════════════════════════════════"
echo "Duplicate Bot Cleanup"
echo "════════════════════════════════════════════════════════════════════"

# Bots that should be running (approved list)
declare -a APPROVED_BOTS=(
    "eurusd_bot.py"
    "gbpusd_bot.py"
    "usdjpy_bot.py"
    "gold_bot.py"
    "forex_scalper.py"
    "btc_bot.py"
    "nifty_scalper.py"
    "scanner_bot.py"
    "token_updater_bot.py"
    "trader.py"
)

echo ""
echo "Scanning for duplicate processes..."
echo ""

# Check each approved bot
for bot in "${APPROVED_BOTS[@]}"; do
    echo "Checking $bot..."

    # Count processes
    local count=$(pgrep -f "python3.*$bot\|python.*$bot" 2>/dev/null | wc -l)

    if [[ $count -eq 0 ]]; then
        echo "  ⊘ Not running"
    elif [[ $count -eq 1 ]]; then
        echo "  ✓ Single instance (OK)"
    else
        echo "  ⚠ Found $count instances (DUPLICATE)"

        # List PIDs
        echo "    PIDs: $(pgrep -f 'python3.*$bot\|python.*$bot' 2>/dev/null | tr '\n' ' ')"

        # Show details
        pgrep -f "python3.*$bot\|python.*$bot" 2>/dev/null | while read pid; do
            echo "    PID $pid: $(ps -p $pid -o cmd= | head -c 80)"
        done
    fi
done

echo ""
echo "════════════════════════════════════════════════════════════════════"

# Find total duplicates
total_duplicates=0
for bot in "${APPROVED_BOTS[@]}"; do
    count=$(pgrep -f "python3.*$bot\|python.*$bot" 2>/dev/null | wc -l)
    if [[ $count -gt 1 ]]; then
        ((total_duplicates+=$count-1))
    fi
done

if [[ $total_duplicates -eq 0 ]]; then
    echo "✓ No duplicate processes found"
    exit 0
fi

echo "⚠ Found $total_duplicates duplicate processes"
echo ""
read -p "Remove duplicates and keep only single instances? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Cleanup cancelled"
    exit 0
fi

echo ""
echo "Removing duplicates..."

# Remove duplicates, keeping first instance
for bot in "${APPROVED_BOTS[@]}"; do
    local pids=($(pgrep -f "python3.*$bot\|python.*$bot" 2>/dev/null || echo ""))
    local count=${#pids[@]}

    if [[ $count -gt 1 ]]; then
        echo "Removing $((count-1)) duplicate instance(s) of $bot"

        # Keep first PID, kill the rest
        for ((i=1; i<$count; i++)); do
            echo "  Killing PID ${pids[$i]}"
            kill -9 "${pids[$i]}" 2>/dev/null || true
        done
    fi
done

sleep 2

echo ""
echo "Verification..."
echo ""

# Verify cleanup
cleaned_ok=true
for bot in "${APPROVED_BOTS[@]}"; do
    local count=$(pgrep -f "python3.*$bot\|python.*$bot" 2>/dev/null | wc -l)
    if [[ $count -le 1 ]]; then
        echo "✓ $bot: clean"
    else
        echo "✗ $bot: still has $count instances"
        cleaned_ok=false
    fi
done

echo ""
echo "════════════════════════════════════════════════════════════════════"

if [[ "$cleaned_ok" == true ]]; then
    echo "✓ Duplicate Cleanup Complete"
    echo "════════════════════════════════════════════════════════════════════"
else
    echo "⚠ Cleanup incomplete - some duplicates remain"
    echo "════════════════════════════════════════════════════════════════════"
    exit 1
fi

echo ""
echo "All bots now running in single instances"
echo ""
