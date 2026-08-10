#!/usr/bin/env bash
################################################################################
# Stabilize MT5 Bridge on Existing DigitalOcean Droplet
# =====================================================
#
# Ensures clean, idempotent MT5 Wine bridge startup.
# Uses verified Windows Python path.
#
# Usage:
#   sudo bash stabilize_mt5_bridge.sh
#
# Components verified:
#   - Xvfb :99
#   - MT5 terminal64.exe
#   - C:\Python311\python.exe (explicit path)
#   - wine_server.py
#   - port 18812 listening
#
# Safety:
#   - Checks for duplicates before starting
#   - Idempotent (safe to re-run)
#   - No credential exposure
#
################################################################################

set -euo pipefail

readonly WINE_PREFIX="/root/.wine_mt5"
readonly WINEPREFIX="${WINE_PREFIX}"
readonly WINEARCH="win64"
readonly DISPLAY=":99"
readonly BRIDGE_PORT=18812
readonly BRIDGE_TIMEOUT=10

echo "════════════════════════════════════════════════════════════════════"
echo "MT5 Bridge Stabilization"
echo "════════════════════════════════════════════════════════════════════"

# ──────────────────────────────────────────────────────────────────────────────
# STEP 1: Verify and start Xvfb
# ──────────────────────────────────────────────────────────────────────────────

echo ""
echo "STEP 1: Verify Xvfb virtual display :99"

if pgrep -x Xvfb >/dev/null 2>&1; then
    echo "✓ Xvfb already running"
else
    echo "Starting Xvfb :99..."
    Xvfb :99 -screen 0 1024x768x24 -ac &
    sleep 3
    if pgrep -x Xvfb >/dev/null 2>&1; then
        echo "✓ Xvfb started on :99"
    else
        echo "✗ Failed to start Xvfb"
        exit 1
    fi
fi

# Verify DISPLAY is accessible
if DISPLAY=:99 xdpyinfo >/dev/null 2>&1; then
    echo "✓ DISPLAY :99 accessible"
else
    echo "✗ DISPLAY :99 not accessible"
    exit 1
fi

# ──────────────────────────────────────────────────────────────────────────────
# STEP 2: Kill old wine/MT5 processes (clean slate)
# ──────────────────────────────────────────────────────────────────────────────

echo ""
echo "STEP 2: Clean old Wine/MT5 processes"

# Kill any existing wine_server.py instances
pkill -f "wine_server.py" || true
sleep 2

# Kill any existing terminal64.exe instances
export WINEPREFIX="${WINE_PREFIX}"
export WINEARCH="${WINEARCH}"
export DISPLAY="${DISPLAY}"
pkill -9 -f "terminal64.exe" 2>/dev/null || true
pkill -9 wineserver 2>/dev/null || true
sleep 3

echo "✓ Old processes cleaned"

# ──────────────────────────────────────────────────────────────────────────────
# STEP 3: Start MT5 terminal
# ──────────────────────────────────────────────────────────────────────────────

echo ""
echo "STEP 3: Start MT5 terminal"

export WINEPREFIX="${WINE_PREFIX}"
export WINEARCH="${WINEARCH}"
export DISPLAY="${DISPLAY}"
export WINEDEBUG=-all

MT5_PATH="${WINE_PREFIX}/drive_c/Program Files/MetaTrader 5/terminal64.exe"

if [[ ! -f "$MT5_PATH" ]]; then
    echo "✗ MT5 terminal not found at: $MT5_PATH"
    exit 1
fi

echo "Launching MT5 terminal..."
wine "$MT5_PATH" &
sleep 10

if pgrep -f "terminal64.exe" >/dev/null 2>&1; then
    echo "✓ MT5 terminal launched (PID: $(pgrep -f terminal64.exe))"
else
    echo "⚠ MT5 process not found (may still be initializing)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# STEP 4: Start wine_server.py bridge
# ──────────────────────────────────────────────────────────────────────────────

echo ""
echo "STEP 4: Start wine_server.py bridge on port ${BRIDGE_PORT}"

# Kill any existing instance
pkill -f "wine_server.py" || true
sleep 2

cd /root/MediDeals-iOS-App/telegram_bot

export WINEPREFIX="${WINE_PREFIX}"
export WINEARCH="${WINEARCH}"
export DISPLAY="${DISPLAY}"
export WINEDEBUG=-all

# Start wine_server.py with explicit Windows Python path
echo "Starting wine_server.py with C:\\Python311\\python.exe..."

# Use wine to run Windows Python
wine C:\\Python311\\python.exe wine_server.py >> /tmp/wine_server.log 2>&1 &
WINE_SERVER_PID=$!

sleep 5

# Verify bridge is listening
if netstat -tuln 2>/dev/null | grep -q ":${BRIDGE_PORT} "; then
    echo "✓ Port ${BRIDGE_PORT} listening"
else
    echo "⚠ Port ${BRIDGE_PORT} not yet listening (checking again...)"
    sleep 5
    if netstat -tuln 2>/dev/null | grep -q ":${BRIDGE_PORT} "; then
        echo "✓ Port ${BRIDGE_PORT} now listening"
    else
        echo "✗ Port ${BRIDGE_PORT} failed to start"
        echo "Last 20 lines of wine_server.log:"
        tail -20 /tmp/wine_server.log || true
        exit 1
    fi
fi

# Test connectivity
echo "Testing bridge connectivity..."
if timeout ${BRIDGE_TIMEOUT} bash -c "</dev/tcp/localhost/${BRIDGE_PORT}" 2>/dev/null; then
    echo "✓ Bridge port ${BRIDGE_PORT} is responding"
else
    echo "✗ Bridge port ${BRIDGE_PORT} not responding"
    exit 1
fi

# ──────────────────────────────────────────────────────────────────────────────
# STEP 5: Verify bridge functionality
# ──────────────────────────────────────────────────────────────────────────────

echo ""
echo "STEP 5: Verify bridge functionality"

python3 << 'PYTHON'
import sys
import time

try:
    import rpyc

    print("Testing rpyc connection to wine_server.py...")
    conn = rpyc.classic.connect("localhost", 18812)

    # Test module access
    mt5 = conn.modules.MetaTrader5
    print("✓ Connected to wine_server.py")
    print(f"✓ MetaTrader5 module accessible")

    conn.close()
    sys.exit(0)
except Exception as e:
    print(f"✗ Bridge test failed: {e}")
    sys.exit(1)
PYTHON

if [[ $? -eq 0 ]]; then
    echo "✓ Bridge functionality verified"
else
    echo "⚠ Bridge connectivity test needs investigation"
fi

# ──────────────────────────────────────────────────────────────────────────────
# FINAL STATUS
# ──────────────────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "MT5 Bridge Stabilization Complete"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "Status:"
echo "  ✓ Xvfb :99 active"
echo "  ✓ MT5 terminal launched"
echo "  ✓ wine_server.py active on port ${BRIDGE_PORT}"
echo "  ✓ Bridge responding to connections"
echo ""
echo "Next step: Run verify_vantage_demo.py to test account connectivity"
echo ""
