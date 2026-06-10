#!/usr/bin/env bash
# stop_bots.sh — Stop all running signal bots

echo "Stopping all signal bots..."
pkill -f "signal_bot.py"   2>/dev/null || true
pkill -f "gold_bot.py"     2>/dev/null || true
pkill -f "nifty_scalper.py" 2>/dev/null || true
pkill -f "scanner_bot.py"  2>/dev/null || true
pkill -f "forex_scalper.py" 2>/dev/null || true
echo "Done — all signal bots stopped."
