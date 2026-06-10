#!/usr/bin/env bash
# stop_bots.sh — Stop all running signal bots

echo "Stopping all signal bots..."
pkill -f "signal_bot.py" && echo "Done — all signal bots stopped." || echo "No signal bots were running."
