#!/usr/bin/env bash
# start_bots.sh — Launch all 9 trading signal bots (runs 24/7)

cd "$(dirname "$0")"
set -a; source .env; set +a
mkdir -p logs

CHAT_ID="${SIGNAL_CHAT_ID:-1994067941}"

# Create named symlinks so watchdog can identify each process uniquely
ln -sf signal_bot.py eurusd_bot.py
ln -sf signal_bot.py gbpusd_bot.py
ln -sf signal_bot.py usdjpy_bot.py

echo "==========================================="
echo "  Starting All Trading Signal Bots"
echo "==========================================="

SIGNAL_SYMBOL="EURUSD=X" SIGNAL_NAME="EURUSD" \
SIGNAL_TOKEN="$ELITE_BOT_TOKEN" SIGNAL_CHAT_ID="$CHAT_ID" \
python3 eurusd_bot.py >> logs/eurusd.log 2>&1 &
echo "  [1] EURUSD    started  (PID $!)"

SIGNAL_SYMBOL="GBPUSD=X" SIGNAL_NAME="GBPUSD" \
SIGNAL_TOKEN="$STOCX_BOT_TOKEN" SIGNAL_CHAT_ID="$CHAT_ID" \
python3 gbpusd_bot.py >> logs/gbpusd.log 2>&1 &
echo "  [2] GBPUSD    started  (PID $!)"

SIGNAL_SYMBOL="USDJPY=X" SIGNAL_NAME="USDJPY" \
SIGNAL_TOKEN="$STOCX_BOT_TOKEN" SIGNAL_CHAT_ID="$CHAT_ID" \
python3 usdjpy_bot.py >> logs/usdjpy.log 2>&1 &
echo "  [3] USDJPY    started  (PID $!)"

python3 gold_bot.py >> logs/gold.log 2>&1 &
echo "  [4] XAUUSD    started  (PID $!)"

python3 nifty_scalper.py >> logs/nifty.log 2>&1 &
echo "  [5] Nifty     started  (PID $!)"

python3 scanner_bot.py >> logs/scanner.log 2>&1 &
echo "  [6] Scanner   started  (PID $!)"

python3 forex_scalper.py >> logs/scalper.log 2>&1 &
echo "  [7] Scalper   started  (PID $!)"

python3 token_updater_bot.py >> logs/token_updater.log 2>&1 &
echo "  [8] TokenBot  started  (PID $!)"

python3 btc_bot.py >> logs/btc.log 2>&1 &
echo "  [9] BTCUSD    started  (PID $!)"

python3 trader.py >> logs/trader.log 2>&1 &
echo " [10] MT5Trader started  (PID $!)"

echo ""
echo "All 10 processes running 24/7. Watchdog checks every 5 minutes."
echo "Send /upstox <token> to Elite bot to refresh Upstox token."
echo "Set META_API_TOKEN in .env to activate MT5 auto-trading."
echo "==========================================="
