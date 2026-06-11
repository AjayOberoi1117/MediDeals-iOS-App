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
    python3 eurusd_bot.py

# GBPUSD
pgrep -f "gbpusd_bot.py" > /dev/null || \
    restart_bot "GBPUSD" "logs/gbpusd.log" \
    env SIGNAL_SYMBOL="GBPUSD=X" SIGNAL_NAME="GBPUSD" \
        SIGNAL_TOKEN="$STOCX_BOT_TOKEN" SIGNAL_CHAT_ID="$CHAT_ID" \
    python3 gbpusd_bot.py

# USDJPY
pgrep -f "usdjpy_bot.py" > /dev/null || \
    restart_bot "USDJPY" "logs/usdjpy.log" \
    env SIGNAL_SYMBOL="USDJPY=X" SIGNAL_NAME="USDJPY" \
        SIGNAL_TOKEN="$STOCX_BOT_TOKEN" SIGNAL_CHAT_ID="$CHAT_ID" \
    python3 usdjpy_bot.py

# Gold
pgrep -f "gold_bot.py" > /dev/null || \
    restart_bot "XAUUSD" "logs/gold.log" \
    python3 gold_bot.py

# Nifty Scalper
pgrep -f "nifty_scalper.py" > /dev/null || \
    restart_bot "NiftyScalper" "logs/nifty.log" \
    python3 nifty_scalper.py

# Stock Scanner
pgrep -f "scanner_bot.py" > /dev/null || \
    restart_bot "StockScanner" "logs/scanner.log" \
    python3 scanner_bot.py

# Forex+Gold Scalper
pgrep -f "forex_scalper.py" > /dev/null || \
    restart_bot "ForexScalper" "logs/scalper.log" \
    python3 forex_scalper.py

# Token Updater Bot
pgrep -f "token_updater_bot.py" > /dev/null || \
    restart_bot "TokenUpdater" "logs/token_updater.log" \
    python3 token_updater_bot.py
