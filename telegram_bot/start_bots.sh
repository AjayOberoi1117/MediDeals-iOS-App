#!/usr/bin/env bash
# start_bots.sh — Launch all 4 trading signal bots
#
# HOW TO USE:
#   1. Open Terminal on your Mac
#   2. cd into the telegram_bot folder:
#        cd /path/to/MediDeals-iOS-App/telegram_bot
#   3. Run:
#        bash start_bots.sh
#
# Each bot runs in the background and writes its own log file to logs/
# To stop all bots:  bash stop_bots.sh

set -e
cd "$(dirname "$0")"

# Load .env so we can read the tokens
export $(grep -v '^#' .env | grep -v '^$' | xargs)

# Create logs directory if it doesn't exist
mkdir -p logs

CHAT_ID="${SIGNAL_CHAT_ID:-1994067941}"

echo "==========================================="
echo "  Starting 4 Trading Signal Bots"
echo "==========================================="

# ── Bot 1: EURUSD — Elite bot ─────────────────────────────────────────────────
SIGNAL_SYMBOL="EURUSD=X" \
SIGNAL_NAME="EURUSD" \
SIGNAL_TOKEN="$ELITE_BOT_TOKEN" \
SIGNAL_CHAT_ID="$CHAT_ID" \
python signal_bot.py >> logs/eurusd.log 2>&1 &
BOT1_PID=$!
echo "  [1] EURUSD   started  (PID $BOT1_PID)  log: logs/eurusd.log"

# ── Bot 2: GBPUSD — Stocx bot ─────────────────────────────────────────────────
SIGNAL_SYMBOL="GBPUSD=X" \
SIGNAL_NAME="GBPUSD" \
SIGNAL_TOKEN="$STOCX_BOT_TOKEN" \
SIGNAL_CHAT_ID="$CHAT_ID" \
python signal_bot.py >> logs/gbpusd.log 2>&1 &
BOT2_PID=$!
echo "  [2] GBPUSD   started  (PID $BOT2_PID)  log: logs/gbpusd.log"

# ── Bot 3: USDJPY — Stocx bot ─────────────────────────────────────────────────
SIGNAL_SYMBOL="USDJPY=X" \
SIGNAL_NAME="USDJPY" \
SIGNAL_TOKEN="$STOCX_BOT_TOKEN" \
SIGNAL_CHAT_ID="$CHAT_ID" \
python signal_bot.py >> logs/usdjpy.log 2>&1 &
BOT3_PID=$!
echo "  [3] USDJPY   started  (PID $BOT3_PID)  log: logs/usdjpy.log"

# ── Bot 4: XAUUSD (Gold) — VantageEA bot ─────────────────────────────────────
SIGNAL_SYMBOL="GC=F" \
SIGNAL_NAME="XAUUSD" \
SIGNAL_TOKEN="$VANTAGE_EA_TOKEN" \
SIGNAL_CHAT_ID="$CHAT_ID" \
python signal_bot.py >> logs/xauusd.log 2>&1 &
BOT4_PID=$!
echo "  [4] XAUUSD   started  (PID $BOT4_PID)  log: logs/xauusd.log"

echo ""
echo "All 4 bots are running in the background."
echo ""
echo "View live logs:"
echo "  tail -f logs/eurusd.log"
echo "  tail -f logs/gbpusd.log"
echo "  tail -f logs/usdjpy.log"
echo "  tail -f logs/xauusd.log"
echo ""
echo "To stop all bots:  bash stop_bots.sh"
echo "==========================================="
