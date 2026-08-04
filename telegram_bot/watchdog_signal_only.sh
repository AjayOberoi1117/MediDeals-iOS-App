#!/bin/bash
#
# Signal-Only Watchdog for Approved Bots
# - Monitors 6 approved signal bots for crashes, auto-restarts if needed
# - OBSERVE_ONLY mode for scanner_bot.py (no restart, no signal, protect)
# - check_duplicates() detects multiple processes without killing (alerts only)
# - Validates signal-only operation (no trader.py, MT5Trader, wine, queue files)
# - Never executes: kill, pkill, killall, xargs kill, process termination
# - .env validation before starting any bot
#
# Usage: ./watchdog_signal_only.sh
#        Run in a loop via cron or systemd for continuous monitoring
#

set -e

SCRIPT_DIR="${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
WATCHDOG_LOG="$LOG_DIR/watchdog.log"
mkdir -p "$LOG_DIR"

APPROVED_BOTS=(
    "eurusd_bot.py"
    "gbpusd_bot.py"
    "usdjpy_bot.py"
    "gold_bot.py"
    "btc_bot.py"
    "nifty_scalper.py"
)

SCANNER_BOT="scanner_bot.py"
SIGNAL_ONLY_SYMBOLS=("EURUSD" "GBPUSD" "USDJPY" "XAUUSD" "BTCUSD" "NIFTY")

validate_env() {
    if [ ! -f "$SCRIPT_DIR/.env" ]; then
        echo "[$(date)] ERROR: .env not found" >> "$WATCHDOG_LOG"
        return 1
    fi

    local required_vars=("VANTAGE_EA_TOKEN" "BTC_BOT_TOKEN" "SIGNAL_CHAT_ID")
    local missing=0

    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$SCRIPT_DIR/.env"; then
            echo "[$(date)] ERROR: Required variable $var not found in .env" >> "$WATCHDOG_LOG"
            missing=$((missing + 1))
        fi
    done

    if [ $missing -gt 0 ]; then
        return 1
    fi

    return 0
}

validate_process() {
    local pid="$1"
    local bot_file="$2"

    if ! ps -p "$pid" > /dev/null 2>&1; then
        return 1
    fi

    local cmdline=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ' || echo "")

    if ! echo "$cmdline" | grep -q "$bot_file"; then
        return 1
    fi

    if ! echo "$cmdline" | grep -q "python3"; then
        return 1
    fi

    local cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null || echo "")
    if [ "$cwd" != "$SCRIPT_DIR" ]; then
        return 1
    fi

    return 0
}

find_valid_process() {
    local bot_file="$1"
    local found_pid=""

    while IFS= read -r pid; do
        if [ -n "$pid" ]; then
            if validate_process "$pid" "$bot_file"; then
                found_pid="$pid"
                break
            fi
        fi
    done < <(pgrep -f "python3.*${bot_file}" 2>/dev/null || true)

    if [ -n "$found_pid" ]; then
        echo "$found_pid"
        return 0
    fi

    return 1
}

check_duplicates() {
    local bot_file="$1"
    local symbol="$2"
    local duplicate_count=0
    local duplicate_pids=()

    while IFS= read -r pid; do
        if [ -n "$pid" ]; then
            if validate_process "$pid" "$bot_file"; then
                duplicate_count=$((duplicate_count + 1))
                duplicate_pids+=("$pid")
            fi
        fi
    done < <(pgrep -f "python3.*${bot_file}" 2>/dev/null || true)

    if [ $duplicate_count -gt 1 ]; then
        echo "[$(date)] ALERT: Multiple $symbol processes detected: ${duplicate_pids[*]}" >> "$WATCHDOG_LOG"
        return 1
    fi

    return 0
}

check_signal_only_compliance() {
    local prohibited_patterns=(
        "nohup.*trader\.py"
        "python3.*trader\.py"
        "nohup.*MT5Trader"
        "python3.*MT5Trader"
        "nohup.*wine[^_]"
        "python3.*wine[^_]"
        "nohup.*forex_scalper"
        "python3.*forex_scalper"
        "nohup.*token_updater"
        "python3.*token_updater"
        "nohup.*mac_trade_writer"
        "python3.*mac_trade_writer"
    )

    for pattern in "${prohibited_patterns[@]}"; do
        if pgrep -f "$pattern" >/dev/null 2>&1; then
            echo "[$(date)] ERROR: Prohibited process detected: $pattern" >> "$WATCHDOG_LOG"
            return 1
        fi
    done

    if [ -f "$SCRIPT_DIR/.trade_queue.jsonl" ]; then
        echo "[$(date)] WARNING: Trade queue file detected (signal-only mode should not have this)" >> "$WATCHDOG_LOG"
    fi

    if [ -f "$SCRIPT_DIR/mt5_signals.csv" ]; then
        echo "[$(date)] WARNING: MT5 signals file detected (signal-only mode should not have this)" >> "$WATCHDOG_LOG"
    fi

    return 0
}

monitor_scanner() {
    local scanner_pid
    scanner_pid=$(find_valid_process "$SCANNER_BOT" 2>/dev/null || true)

    if [ -z "$scanner_pid" ]; then
        echo "[$(date)] OBSERVE: Scanner bot not running" >> "$WATCHDOG_LOG"
        return 0
    fi

    if ps -p "$scanner_pid" > /dev/null 2>&1; then
        echo "[$(date)] OBSERVE: Scanner bot running at PID $scanner_pid (no action)" >> "$WATCHDOG_LOG"
        return 0
    else
        echo "[$(date)] OBSERVE: Scanner bot crashed (no auto-restart)" >> "$WATCHDOG_LOG"
        return 0
    fi
}

restart_bot() {
    local bot_file="$1"
    local symbol="$2"

    if [ ! -f "$SCRIPT_DIR/$bot_file" ]; then
        echo "[$(date)] ERROR: Bot file not found: $bot_file" >> "$WATCHDOG_LOG"
        return 1
    fi

    local log_file="$LOG_DIR/${bot_file%.py}.log"
    echo "[$(date)] RESTART: $symbol ($bot_file)" >> "$WATCHDOG_LOG"

    nohup python3 "$SCRIPT_DIR/$bot_file" > "$log_file" 2>&1 &
    local pid=$!

    sleep 1

    if ps -p "$pid" > /dev/null 2>&1; then
        echo "[$(date)] SUCCESS: $symbol restarted at PID $pid" >> "$WATCHDOG_LOG"
        return 0
    else
        echo "[$(date)] FAILURE: $symbol failed to restart" >> "$WATCHDOG_LOG"
        return 1
    fi
}

monitor_bot() {
    local bot_file="$1"
    local symbol="$2"
    local current_pid

    current_pid=$(find_valid_process "$bot_file" 2>/dev/null || true)

    if [ -z "$current_pid" ]; then
        echo "[$(date)] ALERT: $symbol is not running" >> "$WATCHDOG_LOG"
        if ! validate_env; then
            echo "[$(date)] SKIP: .env invalid, not restarting $symbol" >> "$WATCHDOG_LOG"
            return 1
        fi
        restart_bot "$bot_file" "$symbol"
        return $?
    fi

    if ps -p "$current_pid" > /dev/null 2>&1; then
        return 0
    else
        echo "[$(date)] ALERT: $symbol crashed (PID $current_pid)" >> "$WATCHDOG_LOG"
        if ! validate_env; then
            echo "[$(date)] SKIP: .env invalid, not restarting $symbol" >> "$WATCHDOG_LOG"
            return 1
        fi
        restart_bot "$bot_file" "$symbol"
        return $?
    fi
}

run_one_cycle() {
    echo "[$(date)] ========== WATCHDOG CYCLE ==========" >> "$WATCHDOG_LOG"

    if ! check_signal_only_compliance; then
        echo "[$(date)] COMPLIANCE CHECK FAILED" >> "$WATCHDOG_LOG"
        return 1
    fi

    for i in "${!APPROVED_BOTS[@]}"; do
        bot_file="${APPROVED_BOTS[$i]}"
        symbol="${SIGNAL_ONLY_SYMBOLS[$i]}"

        if ! check_duplicates "$bot_file" "$symbol"; then
            echo "[$(date)] DUPLICATE CHECK FAILED for $symbol" >> "$WATCHDOG_LOG"
            continue
        fi

        monitor_bot "$bot_file" "$symbol" || true
    done

    monitor_scanner

    echo "[$(date)] ========== CYCLE COMPLETE ==========" >> "$WATCHDOG_LOG"
    return 0
}

if [ "${1:-}" = "--once" ]; then
    run_one_cycle
    exit $?
fi

echo "[$(date)] Watchdog started (dry-run mode)" >> "$WATCHDOG_LOG"
run_one_cycle
