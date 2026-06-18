#!/usr/bin/env bash
# start_bots.sh — Launch all 9 trading signal bots + MT5 auto-trader (runs 24/7)

cd "$(dirname "$0")"
set -a; source .env; set +a
mkdir -p logs

# Use venv python if available, fall back to system python3
PYTHON="${BOTENV_PYTHON:-/root/botenv/bin/python3}"
[ -x "$PYTHON" ] || PYTHON=python3

CHAT_ID="${SIGNAL_CHAT_ID:-1994067941}"

# Start MT5 bridge first (Xvfb + MT5 terminal + wine_server.py)
bash start_mt5_bridge.sh

# Create named symlinks so watchdog can identify each process uniquely
ln -sf signal_bot.py eurusd_bot.py
ln -sf signal_bot.py gbpusd_bot.py
ln -sf signal_bot.py usdjpy_bot.py

echo "==========================================="
echo "  Starting All Trading Signal Bots"
echo "==========================================="

SIGNAL_SYMBOL="EURUSD=X" SIGNAL_NAME="EURUSD" \
SIGNAL_TOKEN="$ELITE_BOT_TOKEN" SIGNAL_CHAT_ID="$CHAT_ID" \
$PYTHON eurusd_bot.py >> logs/eurusd.log 2>&1 &
echo "  [1] EURUSD    started  (PID $!)"

SIGNAL_SYMBOL="GBPUSD=X" SIGNAL_NAME="GBPUSD" \
SIGNAL_TOKEN="$STOCX_BOT_TOKEN" SIGNAL_CHAT_ID="$CHAT_ID" \
$PYTHON gbpusd_bot.py >> logs/gbpusd.log 2>&1 &
echo "  [2] GBPUSD    started  (PID $!)"

SIGNAL_SYMBOL="USDJPY=X" SIGNAL_NAME="USDJPY" \
SIGNAL_TOKEN="$STOCX_BOT_TOKEN" SIGNAL_CHAT_ID="$CHAT_ID" \
$PYTHON usdjpy_bot.py >> logs/usdjpy.log 2>&1 &
echo "  [3] USDJPY    started  (PID $!)"

$PYTHON gold_bot.py >> logs/gold.log 2>&1 &
echo "  [4] XAUUSD    started  (PID $!)"

$PYTHON nifty_scalper.py >> logs/nifty.log 2>&1 &
echo "  [5] Nifty     started  (PID $!)"

$PYTHON scanner_bot.py >> logs/scanner.log 2>&1 &
echo "  [6] Scanner   started  (PID $!)"

$PYTHON forex_scalper.py >> logs/scalper.log 2>&1 &
echo "  [7] Scalper   started  (PID $!)"

$PYTHON token_updater_bot.py >> logs/token_updater.log 2>&1 &
echo "  [8] TokenBot  started  (PID $!)"

$PYTHON btc_bot.py >> logs/btc.log 2>&1 &
echo "  [9] BTCUSD    started  (PID $!)"

$PYTHON trader.py >> logs/trader.log 2>&1 &
echo " [10] MT5Trader started  (PID $!)"

echo ""
echo "All 10 processes running 24/7. Watchdog checks every 5 minutes."
echo "Send /upstox <token> to Elite bot to refresh Upstox token."
echo "Set META_API_TOKEN in .env to activate MT5 auto-trading."
echo "==========================================="
