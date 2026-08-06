#!/usr/bin/env bash
# start_bots.sh — Launch trading signal bots independently (skip already-running)
# SAFETY: Forces signal-only mode. Verifies execution gate before any bot starts.
# Preserves: scanner_bot.py, india_scalper.py (unmanaged, untouched)

cd "$(dirname "$0")"
set -a; source .env; set +a
mkdir -p logs

# CRITICAL SAFETY: Force signal-only mode (no live trading)
export BOT_EXECUTION_MODE="signal_only"
unset LIVE_TRADING_CONFIRMED

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

  # Wait 2 seconds for bot to initialize
  sleep 2

  # Verify bot is still running (did not crash during startup)
  if kill -0 "$pid" 2>/dev/null; then
    echo "START: $display_name (PID $pid)"
    STARTED+=("$display_name")
  else
    echo "FAIL: $display_name exited during startup"
    FAILED+=("$display_name")
    echo "  Last 20 lines of log:"
    tail -20 "$log_file" 2>/dev/null | sed 's/^/    /' || true
  fi
}

echo "Checking and starting 5 dedicated signal bots..."
echo ""

# SAFETY GATE: Verify execution mode before starting ANY bot
echo "Verifying execution gate..."
"$PYTHON" - <<'PY'
import sys
sys.path.insert(0, '.')

from telegram_config import get_execution_mode, order_execution_enabled

mode = get_execution_mode()
enabled = order_execution_enabled()

print(f"BOT_EXECUTION_MODE={mode}")
print(f"ORDER_EXECUTION_ENABLED={enabled}")

if mode != "signal_only":
    print("ERROR: Unsafe execution mode (expected signal_only)")
    sys.exit(1)
if enabled:
    print("ERROR: Order execution must be disabled")
    sys.exit(1)

print("✓ Safety gate PASSED")
PY

if [ $? -ne 0 ]; then
  echo ""
  echo "⚠️  SAFETY GATE FAILED - Aborting launcher"
  exit 1
fi

echo ""

# Start each managed bot independently.
# scanner_bot.py, india_scalper.py, and signal_bot.py are intentionally excluded and preserved.
start_bot "$PYTHON" "btc_bot.py" "logs/btc.log" "BTC Bot"
start_bot "$PYTHON" "gold_bot.py" "logs/gold.log" "GOLD Bot"
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
echo "  Safety Summary"
echo "==========================================="
echo "EXECUTION MODE: signal_only"
echo "ORDER EXECUTION: BLOCKED"
echo "SCANNER BOT: PRESERVED"
echo "INDIA SCALPER: PRESERVED"
echo "==========================================="
