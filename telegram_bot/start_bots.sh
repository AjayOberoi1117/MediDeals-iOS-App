#!/usr/bin/env bash
# start_bots.sh — Launch trading signal bots independently (skip already-running)
# NEW: Checks each bot independently. Does NOT abort if one bot is running.

cd "$(dirname "$0")"
set -a; source .env; set +a
mkdir -p logs

# Use venv python if available, fall back to system python3
PYTHON="${BOTENV_PYTHON:-/root/botenv/bin/python3}"
[ -x "$PYTHON" ] || PYTHON=python3

echo "==========================================="
echo "  Independent Bot Launcher"
echo "  (Skips already-running bots)"
echo "==========================================="
echo ""

# Tracking arrays
declare -a STARTED
declare -a SKIPPED
declare -a FAILED

# Function to check if a bot is already running
is_running() {
  local bot_name=$1
  pgrep -f "$bot_name" > /dev/null 2>&1
  return $?
}

# Function to start a bot safely
start_bot() {
  local python_path=$1
  local bot_file=$2
  local log_file=$3
  local display_name=$4

  if is_running "$bot_file"; then
    echo "SKIP: $display_name ($bot_file) already running"
    SKIPPED+=("$display_name")
    return 0
  fi

  # Start the bot
  $python_path "$bot_file" >> "$log_file" 2>&1 &
  local pid=$!

  if [ $? -eq 0 ]; then
    echo "START: $display_name (PID $pid)"
    STARTED+=("$display_name")
  else
    echo "FAIL: $display_name could not start"
    FAILED+=("$display_name")
  fi
}

echo "Checking and starting 6 dedicated signal bots..."
echo ""

# Start each bot independently (do NOT preserve scanner_bot or india_scalper)
start_bot "$PYTHON" "btc_bot.py" "logs/btc.log" "BTC Bot"
start_bot "$PYTHON" "gold_bot.py" "logs/gold.log" "GOLD Bot"
start_bot "$PYTHON" "signal_bot.py" "logs/signal.log" "SIGNAL Bot"
start_bot "$PYTHON" "forex_scalper.py" "logs/forex.log" "FOREX Scalper"
start_bot "$PYTHON" "nifty_scalper.py" "logs/nifty.log" "NIFTY Scalper"
start_bot "$PYTHON" "options_scalper.py" "logs/options.log" "OPTIONS Scalper"

echo ""
echo "==========================================="
echo "  Summary"
echo "==========================================="

if [ ${#STARTED[@]} -gt 0 ]; then
  echo "STARTED:"
  for bot in "${STARTED[@]}"; do
    echo "  - $bot"
  done
else
  echo "STARTED: (none)"
fi

echo ""

if [ ${#SKIPPED[@]} -gt 0 ]; then
  echo "SKIPPED:"
  for bot in "${SKIPPED[@]}"; do
    echo "  - $bot"
  done
else
  echo "SKIPPED: (none)"
fi

echo ""

if [ ${#FAILED[@]} -gt 0 ]; then
  echo "FAILED:"
  for bot in "${FAILED[@]}"; do
    echo "  - $bot"
  done
  echo ""
  echo "⚠️  Review logs/ directory for error details"
else
  echo "FAILED: (none)"
fi

echo ""
echo "==========================================="
