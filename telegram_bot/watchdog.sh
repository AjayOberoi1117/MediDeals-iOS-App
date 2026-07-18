#!/usr/bin/env bash
# watchdog.sh — Restart any crashed trading bot automatically
# Runs every 5 minutes via cron. Silent if all bots are healthy.

DIR="/root/MediDeals-iOS-App/telegram_bot"
LOG="$DIR/logs/watchdog.log"
cd "$DIR" || exit 1
mkdir -p logs

set -a; source .env; set +a
CHAT_ID="${SIGNAL_CHAT_ID:-1994067941}"
TOKEN="${ELITE_BOT_TOKEN}"

PYTHON="${BOTENV_PYTHON:-/root/botenv/bin/python3}"
[ -x "$PYTHON" ] || PYTHON=python3

tg_alert() {
    curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=$1" \
        -d "parse_mode=HTML" > /dev/null 2>&1 || true
}

restart_bot() {
    local name="$1"
    local logfile="$2"
    shift 2
    echo "[$(date '+%Y-%m-%d %H:%M:%S IST')] RESTART: $name" >> "$LOG"
    "$@" >> "$logfile" 2>&1 &
    local pid=$!
    echo "[$(date '+%Y-%m-%d %H:%M:%S IST')] $name restarted PID=$pid" >> "$LOG"
    tg_alert "⚠️ <b>Bot Auto-Restarted</b>
<b>$name</b> was down and has been restarted automatically.
PID: $pid"
}

# EURUSD
pgrep -f "eurusd_bot.py" > /dev/null || \
    restart_bot "EURUSD" "logs/eurusd.log" \
    env SIGNAL_SYMBOL="EURUSD=X" SIGNAL_NAME="EURUSD" \
        SIGNAL_TOKEN="$ELITE_BOT_TOKEN" SIGNAL_CHAT_ID="$CHAT_ID" \
    $PYTHON eurusd_bot.py

# GBPUSD
pgrep -f "gbpusd_bot.py" > /dev/null || \
    restart_bot "GBPUSD" "logs/gbpusd.log" \
    env SIGNAL_SYMBOL="GBPUSD=X" SIGNAL_NAME="GBPUSD" \
        SIGNAL_TOKEN="$STOCX_BOT_TOKEN" SIGNAL_CHAT_ID="$CHAT_ID" \
    $PYTHON gbpusd_bot.py

# USDJPY
pgrep -f "usdjpy_bot.py" > /dev/null || \
    restart_bot "USDJPY" "logs/usdjpy.log" \
    env SIGNAL_SYMBOL="USDJPY=X" SIGNAL_NAME="USDJPY" \
        SIGNAL_TOKEN="$STOCX_BOT_TOKEN" SIGNAL_CHAT_ID="$CHAT_ID" \
    $PYTHON usdjpy_bot.py

# Gold
pgrep -f "gold_bot.py" > /dev/null || \
    restart_bot "XAUUSD" "logs/gold.log" \
    $PYTHON gold_bot.py

# Nifty Scalper
pgrep -f "nifty_scalper.py" > /dev/null || \
    restart_bot "NiftyScalper" "logs/nifty.log" \
    $PYTHON nifty_scalper.py

# Stock Scanner
pgrep -f "scanner_bot.py" > /dev/null || \
    restart_bot "StockScanner" "logs/scanner.log" \
    $PYTHON scanner_bot.py

# Forex+Gold Scalper
pgrep -f "forex_scalper.py" > /dev/null || \
    restart_bot "ForexScalper" "logs/scalper.log" \
    $PYTHON forex_scalper.py

# Token Updater Bot
pgrep -f "token_updater_bot.py" > /dev/null || \
    restart_bot "TokenUpdater" "logs/token_updater.log" \
    $PYTHON token_updater_bot.py

# BTC Bot
pgrep -f "btc_bot.py" > /dev/null || \
    restart_bot "BTCUSD" "logs/btc.log" \
    $PYTHON btc_bot.py

# MT5 Auto-Trader
pgrep -f "trader.py" > /dev/null || \
    restart_bot "MT5Trader" "logs/trader.log" \
    $PYTHON trader.py

# MT5 Wine bridge components
export WINEPREFIX=/root/.wine_mt5 WINEARCH=win64 DISPLAY=:99

if ! pgrep -x Xvfb > /dev/null; then
    Xvfb :99 -screen 0 1024x768x24 &
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Xvfb restarted" >> "$LOG"
fi

if ! pgrep -f "wine_server.py" > /dev/null; then
    WINEDEBUG=-all wine python "$DIR/wine_server.py" >> "$DIR/logs/wine_server.log" 2>&1 &
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] wine_server.py restarted" >> "$LOG"
    tg_alert "⚠️ <b>MT5 Bridge Restarted</b>\nwine_server.py was down and has been restarted."
fi

if ! pgrep -f "terminal64.exe" > /dev/null; then
    MT5_EXE="$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"
    WINEDEBUG=-all wine "$MT5_EXE" /portable >> "$DIR/logs/mt5.log" 2>&1 &
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] MT5 terminal restarted" >> "$LOG"
    tg_alert "⚠️ <b>MT5 Terminal Restarted</b>\nMT5 terminal was down and has been restarted."
fi
