#!/usr/bin/env bash
# start_bots.sh — Launch all trading signal bots
#
# HOW TO USE:
#   cd ~/MediDeals-iOS-App/telegram_bot
#   bash start_bots.sh
#
# To stop all:  bash stop_bots.sh

set -e
cd "$(dirname "$0")"
export $(grep -v '^#' .env | grep -v '^$' | xargs)
mkdir -p logs

CHAT_ID="${SIGNAL_CHAT_ID:-1994067941}"

echo "==========================================="
echo "  Starting All Trading Signal Bots"
echo "==========================================="

# ── Forex Bots ───────────────────────────────────────────────────────────────

SIGNAL_SYMBOL="EURUSD=X" \
SIGNAL_NAME="EURUSD" \
SIGNAL_TOKEN="$ELITE_BOT_TOKEN" \
SIGNAL_CHAT_ID="$CHAT_ID" \
python3 signal_bot.py >> logs/eurusd.log 2>&1 &
echo "  [1] EURUSD    started  (PID $!)  log: logs/eurusd.log"

SIGNAL_SYMBOL="GBPUSD=X" \
SIGNAL_NAME="GBPUSD" \
SIGNAL_TOKEN="$STOCX_BOT_TOKEN" \
SIGNAL_CHAT_ID="$CHAT_ID" \
python3 signal_bot.py >> logs/gbpusd.log 2>&1 &
echo "  [2] GBPUSD    started  (PID $!)  log: logs/gbpusd.log"

SIGNAL_SYMBOL="USDJPY=X" \
SIGNAL_NAME="USDJPY" \
SIGNAL_TOKEN="$STOCX_BOT_TOKEN" \
SIGNAL_CHAT_ID="$CHAT_ID" \
python3 signal_bot.py >> logs/usdjpy.log 2>&1 &
echo "  [3] USDJPY    started  (PID $!)  log: logs/usdjpy.log"

# ── Gold Bot ─────────────────────────────────────────────────────────────────

python3 gold_bot.py >> logs/gold.log 2>&1 &
echo "  [4] XAUUSD    started  (PID $!)  log: logs/gold.log"

# ── Nifty / BankNifty Scalper ────────────────────────────────────────────────

python3 nifty_scalper.py >> logs/nifty.log 2>&1 &
echo "  [5] Nifty     started  (PID $!)  log: logs/nifty.log"

# ── Upstox Stock Scanner ─────────────────────────────────────────────────────

python3 scanner_bot.py >> logs/scanner.log 2>&1 &
echo "  [6] Scanner   started  (PID $!)  log: logs/scanner.log"

echo ""
echo "All 6 bots running in the background."
echo ""
echo "View live logs:"
echo "  tail -f logs/eurusd.log"
echo "  tail -f logs/gold.log"
echo "  tail -f logs/nifty.log"
echo "  tail -f logs/scanner.log"
echo ""
echo "To stop all bots:  bash stop_bots.sh"
echo "==========================================="
