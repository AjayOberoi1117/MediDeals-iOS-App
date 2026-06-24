#!/bin/bash
# Start all trading signal bots on GCP VM
# Run from the telegram_bot/ directory: bash start_bots_gcp.sh
# Tokens are read from .env — never hardcoded here

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=================================================="
echo "  MediDeals Trading Bots — GCP Startup"
echo "  $(date '+%d %b %Y %H:%M:%S')"
echo "=================================================="

# Kill any running bot processes
echo ""
echo "Stopping existing bot processes..."
pkill -f "signal_bot.py"   2>/dev/null || true
pkill -f "gold_bot.py"     2>/dev/null || true
pkill -f "btc_bot.py"      2>/dev/null || true
pkill -f "forex_scalper.py"2>/dev/null || true
pkill -f "nifty_scalper.py"2>/dev/null || true
pkill -f "scanner_bot.py"  2>/dev/null || true
sleep 2
echo "Done."

# Create logs directory
mkdir -p logs

echo ""
echo "Starting bots..."

# Forex signal bots (EURUSD, GBPUSD, USDJPY — one process each via SIGNAL_NAME)
SIGNAL_NAME=EURUSD SIGNAL_TOKEN="" nohup python3 signal_bot.py \
    >> logs/signal_eurusd.log 2>&1 &
echo "  [OK] signal_bot.py (EURUSD) — PID $!"

SIGNAL_NAME=GBPUSD SIGNAL_TOKEN="" nohup python3 signal_bot.py \
    >> logs/signal_gbpusd.log 2>&1 &
echo "  [OK] signal_bot.py (GBPUSD) — PID $!"

SIGNAL_NAME=USDJPY SIGNAL_TOKEN="" nohup python3 signal_bot.py \
    >> logs/signal_usdjpy.log 2>&1 &
echo "  [OK] signal_bot.py (USDJPY) — PID $!"

# Gold bot
nohup python3 gold_bot.py >> logs/gold_bot.log 2>&1 &
echo "  [OK] gold_bot.py — PID $!"

# BTC bot (only if BTC_BOT_TOKEN is set)
if grep -q "^BTC_BOT_TOKEN=.\+" .env 2>/dev/null; then
    nohup python3 btc_bot.py >> logs/btc_bot.log 2>&1 &
    echo "  [OK] btc_bot.py — PID $!"
else
    echo "  [SKIP] btc_bot.py — BTC_BOT_TOKEN not set in .env"
fi

# Forex scalper (15min — EURUSD/GBPUSD/USDJPY/XAUUSD)
nohup python3 forex_scalper.py >> logs/forex_scalper.log 2>&1 &
echo "  [OK] forex_scalper.py — PID $!"

# Nifty scalper (Indian market hours only)
nohup python3 nifty_scalper.py >> logs/nifty_scalper.log 2>&1 &
echo "  [OK] nifty_scalper.py — PID $!"

# Stock scanner (Indian market hours only)
nohup python3 scanner_bot.py >> logs/scanner_bot.log 2>&1 &
echo "  [OK] scanner_bot.py — PID $!"

echo ""
echo "All bots started. Logs in: $SCRIPT_DIR/logs/"
echo ""
echo "Useful commands:"
echo "  tail -f logs/gold_bot.log          # watch gold bot"
echo "  tail -f logs/nifty_scalper.log     # watch nifty bot"
echo "  tail -f logs/scanner_bot.log       # watch stock scanner"
echo "  ps aux | grep '.py'                # list running bots"
echo "  bash stop_bots_gcp.sh              # stop all bots"
echo ""
