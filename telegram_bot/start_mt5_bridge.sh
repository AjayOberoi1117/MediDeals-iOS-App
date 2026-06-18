#!/usr/bin/env bash
# start_mt5_bridge.sh — Start headless MT5 + Wine bridge server
# Run this BEFORE start_bots.sh on every reboot.
# After the first manual login via VNC, MT5 auto-connects (saved credentials).

export WINEPREFIX=/root/.wine_mt5
export WINEARCH=win64

DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DIR/logs"

MT5_EXE="$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"

# ── 1. Virtual display ────────────────────────────────────────
if ! pgrep -x Xvfb > /dev/null; then
    Xvfb :99 -screen 0 1024x768x24 &
    sleep 3
    echo "[bridge] Xvfb started on :99"
else
    echo "[bridge] Xvfb already running"
fi
export DISPLAY=:99

# ── 2. MT5 terminal ──────────────────────────────────────────
if ! pgrep -f "terminal64.exe" > /dev/null; then
    WINEDEBUG=-all wine "$MT5_EXE" /portable >> "$DIR/logs/mt5.log" 2>&1 &
    echo "[bridge] MT5 terminal starting (waiting 20s to connect to broker)..."
    sleep 20
else
    echo "[bridge] MT5 terminal already running"
fi

# ── 3. Wine bridge server ─────────────────────────────────────
if ! pgrep -f "wine_server.py" > /dev/null; then
    WINEDEBUG=-all wine python "$DIR/wine_server.py" >> "$DIR/logs/wine_server.log" 2>&1 &
    sleep 3
    echo "[bridge] wine_server.py started on localhost:18812"
else
    echo "[bridge] wine_server.py already running"
fi

echo "[bridge] MT5 bridge ready. Start bots with: bash start_bots.sh"
