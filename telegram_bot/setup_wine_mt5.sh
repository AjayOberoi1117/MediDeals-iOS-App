#!/usr/bin/env bash
# setup_wine_mt5.sh — One-time setup: Wine + MT5 + Python on Ubuntu VPS
# Run once as root: bash setup_wine_mt5.sh
# After this, run start_mt5_bridge.sh to launch MT5 headlessly.

set -e
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=========================================================="
echo "  MT5 Wine Setup — Ubuntu VPS"
echo "=========================================================="

# ── Step 1: System packages ───────────────────────────────────
echo "[1/6] Installing Wine + Xvfb + VNC..."
sudo dpkg --add-architecture i386
sudo apt update -y
sudo apt install -y \
    wine wine32 wine64 \
    xvfb x11vnc \
    wget curl python3-pip \
    libglib2.0-0t64:i386 libsm6 libxrender1 libxext6

# Install winetricks directly (removed from Ubuntu 24.04 repos)
if ! command -v winetricks &>/dev/null; then
    wget -q -O /usr/local/bin/winetricks \
        https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
    chmod +x /usr/local/bin/winetricks
fi

# ── Step 2: Wine environment ──────────────────────────────────
echo "[2/6] Initialising Wine prefix..."
export WINEPREFIX=/root/.wine_mt5
export WINEARCH=win64
export DISPLAY=:99

# Start virtual display
pkill Xvfb 2>/dev/null || true
Xvfb :99 -screen 0 1024x768x24 &
sleep 3

WINEDEBUG=-all wine wineboot --init 2>/dev/null
winetricks -q corefonts 2>/dev/null || true

# ── Step 3: Windows Python inside Wine ───────────────────────
echo "[3/6] Installing Windows Python 3.11 inside Wine..."
PY_EXE=/tmp/python-win.exe
if [ ! -f "$PY_EXE" ]; then
    wget -q -O "$PY_EXE" \
        "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
fi
WINEDEBUG=-all wine "$PY_EXE" /quiet InstallAllUsers=1 PrependPath=1 2>/dev/null
sleep 15

# ── Step 4: MetaTrader5 + mt5linux in Wine Python ────────────
echo "[4/6] Installing MetaTrader5 + mt5linux in Wine Python..."
WINEDEBUG=-all wine python -m pip install --quiet MetaTrader5 mt5linux
sleep 5

# ── Step 5: Download + install MT5 terminal ──────────────────
echo "[5/6] Downloading + installing MT5 terminal..."
MT5_EXE=/tmp/mt5setup.exe
if [ ! -f "$MT5_EXE" ]; then
    wget -q -O "$MT5_EXE" \
        "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"
fi
WINEDEBUG=-all wine "$MT5_EXE" /auto 2>/dev/null
sleep 30

# ── Step 6: Native Python mt5linux ───────────────────────────
echo "[6/6] Installing mt5linux in native Python..."
pip3 install -q mt5linux

echo ""
echo "=========================================================="
echo "  Setup complete!"
echo ""
echo "  NEXT STEP — log in to MT5 via VNC (one-time only):"
echo ""
echo "  1. On VPS run:"
echo "       x11vnc -display :99 -nopw -listen 0.0.0.0 -port 5900 &"
echo "       DISPLAY=:99 WINEPREFIX=/root/.wine_mt5 wine \\"
echo "         '/root/.wine_mt5/drive_c/Program Files/MetaTrader 5/terminal64.exe' &"
echo ""
echo "  2. On your Mac, open Finder → Go → Connect to Server:"
echo "       vnc://$(curl -s ifconfig.me):5900"
echo ""
echo "  3. In the MT5 window:"
echo "       File → Login to Trade Account"
echo "       Login: 25285913"
echo "       Server: VantageMarkets-Demo"
echo "       Password: <your password>  ✓ Save password"
echo ""
echo "  4. Tools → Options → Expert Advisors → tick:"
echo "       ✓ Allow automated trading"
echo ""
echo "  5. After login, run:  bash start_mt5_bridge.sh"
echo "     From then on MT5 auto-connects on every reboot — Mac not needed."
echo "=========================================================="
