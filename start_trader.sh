#!/usr/bin/env bash
################################################################################
# Start trader.py for MT5 Order Execution
# ========================================
#
# Starts trader.py after verifying bridge is ready.
# Polls for bridge connectivity before starting.
#
# Usage:
#   bash start_trader.sh
#
# Prerequisites:
#   - stabilize_mt5_bridge.sh has completed
#   - port 18812 is listening
#   - .env file configured
#   - verify_vantage_demo.py has passed
#
# Safety:
#   - Checks bridge before starting
#   - Kills duplicate trader instances
#   - Idempotent
#
################################################################################

set -euo pipefail

readonly BRIDGE_PORT=18812
readonly BRIDGE_CHECK_TIMEOUT=10
readonly MAX_BRIDGE_WAIT=60
readonly TRADER_SCRIPT="trader.py"
readonly LOG_DIR="/root/MediDeals-iOS-App/telegram_bot/logs"

echo "════════════════════════════════════════════════════════════════════"
echo "Starting trader.py"
echo "════════════════════════════════════════════════════════════════════"

# ──────────────────────────────────────────────────────────────────────────────
# Step 1: Verify bridge is ready
# ──────────────────────────────────────────────────────────────────────────────

echo ""
echo "STEP 1: Verify MT5 bridge is ready"

elapsed=0
while [[ $elapsed -lt $MAX_BRIDGE_WAIT ]]; do
    if timeout 2 bash -c "</dev/tcp/localhost/${BRIDGE_PORT}" 2>/dev/null; then
        echo "✓ Bridge port ${BRIDGE_PORT} is listening"
        break
    fi

    echo "  Waiting for bridge (${elapsed}s)..."
    sleep 5
    ((elapsed+=5))
done

if [[ $elapsed -ge $MAX_BRIDGE_WAIT ]]; then
    echo "✗ Bridge did not start within ${MAX_BRIDGE_WAIT}s"
    echo "  Verify stabilize_mt5_bridge.sh completed successfully"
    exit 1
fi

echo ""

# ──────────────────────────────────────────────────────────────────────────────
# Step 2: Kill any existing trader instance
# ──────────────────────────────────────────────────────────────────────────────

echo "STEP 2: Check for existing trader processes"

if pgrep -f "python3.*trader\.py" >/dev/null 2>&1; then
    echo "Found existing trader.py instance, stopping..."
    pkill -f "python3.*trader\.py" || true
    sleep 2
fi

if pgrep -f "python3.*trader\.py" >/dev/null 2>&1; then
    echo "✗ Could not stop existing trader process"
    exit 1
else
    echo "✓ No trader processes running"
fi

echo ""

# ──────────────────────────────────────────────────────────────────────────────
# Step 3: Create log directory
# ──────────────────────────────────────────────────────────────────────────────

echo "STEP 3: Setup logging"

mkdir -p "${LOG_DIR}"
echo "✓ Log directory ready: ${LOG_DIR}"

echo ""

# ──────────────────────────────────────────────────────────────────────────────
# Step 4: Start trader.py
# ──────────────────────────────────────────────────────────────────────────────

echo "STEP 4: Start trader.py"

cd /root/MediDeals-iOS-App/telegram_bot

# Set up environment
export DISPLAY=":99"
export WINEPREFIX="/root/.wine_mt5"
export WINEARCH="win64"

# Check .env exists
if [[ ! -f ".env" ]]; then
    echo "✗ .env file not found"
    exit 1
fi

echo "Starting trader.py..."
nohup python3 trader.py >> "${LOG_DIR}/trader.log" 2>&1 &
TRADER_PID=$!

sleep 3

# Verify trader is running
if kill -0 $TRADER_PID 2>/dev/null; then
    echo "✓ trader.py started (PID: $TRADER_PID)"
else
    echo "✗ trader.py failed to start"
    echo "Last 20 lines of trader.log:"
    tail -20 "${LOG_DIR}/trader.log" || true
    exit 1
fi

echo ""

# ──────────────────────────────────────────────────────────────────────────────
# Step 5: Verify trader connectivity
# ──────────────────────────────────────────────────────────────────────────────

echo "STEP 5: Verify trader connectivity"

sleep 5

# Check logs for errors
if grep -i "error\|failed\|exception" "${LOG_DIR}/trader.log" 2>/dev/null | head -3; then
    echo "⚠ Errors detected in trader.log"
    echo "Review log for details: ${LOG_DIR}/trader.log"
else
    echo "✓ No errors in trader.log"
fi

# Check for successful connection
if grep -i "connected\|initialized\|ready" "${LOG_DIR}/trader.log" 2>/dev/null | head -1; then
    echo "✓ trader.py appears to have connected successfully"
else
    echo "⚠ Could not confirm successful connection"
fi

echo ""

# ──────────────────────────────────────────────────────────────────────────────
# Final status
# ──────────────────────────────────────────────────────────────────────────────

echo "════════════════════════════════════════════════════════════════════"
echo "trader.py Started"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "Status:"
echo "  ✓ MT5 bridge verified (port ${BRIDGE_PORT})"
echo "  ✓ trader.py running (PID: $TRADER_PID)"
echo "  ✓ Logging to: ${LOG_DIR}/trader.log"
echo ""
echo "Next steps:"
echo "  1. Monitor trader.log for order queue processing"
echo "  2. Start signal bots to populate .trade_queue.jsonl"
echo "  3. Verify orders execute to Vantage DEMO account"
echo ""
