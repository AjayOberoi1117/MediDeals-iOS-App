#!/bin/bash
# Stop all trading signal bots on GCP VM

echo "Stopping all bots..."
pkill -f "signal_bot.py"    2>/dev/null && echo "  [stopped] signal_bot.py"    || true
pkill -f "gold_bot.py"      2>/dev/null && echo "  [stopped] gold_bot.py"      || true
pkill -f "btc_bot.py"       2>/dev/null && echo "  [stopped] btc_bot.py"       || true
pkill -f "forex_scalper.py" 2>/dev/null && echo "  [stopped] forex_scalper.py" || true
pkill -f "nifty_scalper.py" 2>/dev/null && echo "  [stopped] nifty_scalper.py" || true
pkill -f "scanner_bot.py"   2>/dev/null && echo "  [stopped] scanner_bot.py"   || true
echo "Done."
