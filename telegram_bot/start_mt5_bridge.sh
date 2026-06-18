#!/usr/bin/env bash
# start_mt5_bridge.sh — Start Xvfb virtual display + Wine bridge server.
# trader.py calls mt5.initialize(path, login, password, server) which auto-starts
# and logs in to MT5 terminal — no VNC manual login needed.

export WINEPREFIX=/root/.wine_mt5
export WINEARCH=win64

DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DIR/logs"

# ── 1. Virtual display ────────────────────────────────────────
if ! pgrep -x Xvfb > /dev/null; then
    Xvfb :99 -screen 0 1024x768x24 &
    sleep 3
    echo "[bridge] Xvfb started on :99"
else
    echo "[bridge] Xvfb already running"
fi
export DISPLAY=:99

# ── 2. Wine bridge server ─────────────────────────────────────
# MT5 terminal is started automatically by trader.py via mt5.initialize(path, login, ...)
if ! pgrep -f "wine_server.py" > /dev/null; then
    WINEDEBUG=-all wine python "$DIR/wine_server.py" >> "$DIR/logs/wine_server.log" 2>&1 &
    sleep 3
    echo "[bridge] wine_server.py started on localhost:18812"
else
    echo "[bridge] wine_server.py already running"
fi

echo "[bridge] Bridge ready. trader.py will auto-start + log in to MT5 on first connection."
echo "[bridge] Start all bots with: bash start_bots.sh"
