#!/bin/bash
#
# Signal-Only Watchdog — Monitor and auto-restart approved bots
# Strict validation: no process termination, observe-only for scanner
#
set -e

SCRIPT_DIR="${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
cd "$SCRIPT_DIR"

WATCHDOG_LOG="$LOG_DIR/watchdog.log"

APPROVED_BOTS=(
    "eurusd_bot.py"
    "gbpusd_bot.py"
    "usdjpy_bot.py"
    "gold_bot.py"
    "btc_bot.py"
    "nifty_scalper.py"
)

SYMBOLS=("EURUSD" "GBPUSD" "USDJPY" "XAUUSD" "BTCUSD" "NIFTY")
SCANNER_BOT="scanner_bot.py"

ENV_ALLOWLIST=(
    "VANTAGE_EA_TOKEN"
    "BTC_BOT_TOKEN"
    "STOCX_BOT_TOKEN"
    "SIGNAL_CHAT_ID"
)

log_msg() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$WATCHDOG_LOG"
}

parse_env() {
    local line key value
    local -a seen_keys

    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"

        if [ -z "$line" ] || [[ "$line" == \#* ]]; then
            continue
        fi

        if [[ ! "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            log_msg "ERROR: Malformed .env: $line"
            return 1
        fi

        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"

        if [[ " ${seen_keys[@]} " =~ " $key " ]]; then
            log_msg "ERROR: Duplicate .env key: $key"
            return 1
        fi
        seen_keys+=("$key")

        if [[ ! " ${ENV_ALLOWLIST[@]} " =~ " $key " ]]; then
            continue
        fi

        if [ -z "$value" ]; then
            log_msg "ERROR: Empty value for $key"
            return 1
        fi

        export "$key"="$value"
    done < "$SCRIPT_DIR/.env"

    return 0
}

validate_env() {
    if [ ! -f "$SCRIPT_DIR/.env" ]; then
        log_msg "ERROR: .env not found"
        return 1
    fi

    if ! parse_env; then
        return 1
    fi

    local required=("VANTAGE_EA_TOKEN" "BTC_BOT_TOKEN" "STOCX_BOT_TOKEN" "SIGNAL_CHAT_ID")
    local var
    for var in "${required[@]}"; do
        if [ -z "${!var:-}" ]; then
            log_msg "ERROR: Required variable not set: $var"
            return 1
        fi
    done

    return 0
}

validate_process() {
    local pid="$1" bot_file="$2"
    local exe cmdline cwd

    if ! ps -p "$pid" > /dev/null 2>&1; then
        return 1
    fi

    exe=$(readlink "/proc/$pid/exe" 2>/dev/null || echo "")
    if [ "$exe" != "/usr/bin/python3" ] && [ "$exe" != "/usr/bin/python" ]; then
        return 1
    fi

    IFS=$'\0' read -rd '' -a cmdline_arr < "/proc/$pid/cmdline" 2>/dev/null || return 1

    if [ -z "${cmdline_arr[1]:-}" ] || [ "${cmdline_arr[1]##*/}" != "$bot_file" ]; then
        return 1
    fi

    cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null || echo "")
    if [ "$cwd" != "$SCRIPT_DIR" ]; then
        return 1
    fi

    return 0
}

find_process() {
    local bot_file="$1"
    local pid found_pid

    while IFS= read -r pid; do
        if [ -n "$pid" ] && validate_process "$pid" "$bot_file"; then
            found_pid="$pid"
            break
        fi
    done < <(pgrep -f "python3" 2>/dev/null || true)

    if [ -n "$found_pid" ]; then
        echo "$found_pid"
        return 0
    fi

    return 1
}

check_health() {
    local pid="$1" log_file="$2" timeout=5 elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if ! ps -p "$pid" > /dev/null 2>&1; then
            log_msg "HEALTH: Process $pid exited"
            return 1
        fi

        if [ -f "$log_file" ]; then
            local mtime=$(stat -c '%Y' "$log_file" 2>/dev/null || echo 0)
            local size=$(stat -c '%s' "$log_file" 2>/dev/null || echo 0)

            if [ "$mtime" -gt 0 ] && [ "$size" -gt 0 ]; then
                if grep -q "Error\|ERROR\|Traceback\|Exception" "$log_file" 2>/dev/null; then
                    log_msg "HEALTH: Fatal error in log: $log_file"
                    return 1
                fi
            fi
        fi

        sleep 1
        elapsed=$((elapsed + 1))
    done

    if ps -p "$pid" > /dev/null 2>&1; then
        return 0
    fi

    return 1
}

restart_bot() {
    local bot_file="$1" symbol="$2"

    if [ ! -f "$bot_file" ]; then
        log_msg "RESTART FAILED: Bot file not found: $bot_file"
        return 1
    fi

    log_file="$LOG_DIR/${bot_file%.py}.log"
    log_msg "RESTART: $symbol ($bot_file)"

    nohup python3 "$bot_file" > "$log_file" 2>&1 &
    local pid=$!

    if check_health "$pid" "$log_file"; then
        log_msg "RESTART SUCCESS: $symbol (PID $pid)"
        return 0
    else
        log_msg "RESTART FAILED: $symbol did not stay healthy"
        return 1
    fi
}

check_prohibited() {
    local prohibited=("trader.py" "MT5Trader" "forex_scalper" "token_updater" "mac_trade_writer" "wine" ".trade_queue.jsonl" "mt5_signals.csv")
    local item

    for item in "${prohibited[@]}"; do
        if pgrep -f "$item" >/dev/null 2>&1; then
            log_msg "ERROR: Prohibited process detected: $item"
            return 1
        fi
    done

    return 0
}

monitor_scanner() {
    local pid
    pid=$(find_process "$SCANNER_BOT" 2>/dev/null) || pid=""

    if [ -z "$pid" ]; then
        log_msg "OBSERVE: Scanner not running (no action)"
        return 0
    fi

    if ps -p "$pid" > /dev/null 2>&1; then
        log_msg "OBSERVE: Scanner running (PID $pid, no action)"
        return 0
    else
        log_msg "OBSERVE: Scanner crashed (no auto-restart)"
        return 0
    fi
}

monitor_bot() {
    local bot_file="$1" symbol="$2"
    local pid

    pid=$(find_process "$bot_file" 2>/dev/null) || pid=""

    if [ -z "$pid" ]; then
        log_msg "ALERT: $symbol is not running"

        if ! validate_env; then
            log_msg "SKIP RESTART: .env validation failed for $symbol"
            return 1
        fi

        restart_bot "$bot_file" "$symbol"
        return $?
    fi

    if ps -p "$pid" > /dev/null 2>&1; then
        return 0
    else
        log_msg "ALERT: $symbol crashed (PID $pid)"

        if ! validate_env; then
            log_msg "SKIP RESTART: .env validation failed for $symbol"
            return 1
        fi

        restart_bot "$bot_file" "$symbol"
        return $?
    fi
}

run_cycle() {
    log_msg "========== WATCHDOG CYCLE =========="

    if ! check_prohibited; then
        log_msg "COMPLIANCE: Prohibited processes detected"
    fi

    for i in "${!APPROVED_BOTS[@]}"; do
        bot_file="${APPROVED_BOTS[$i]}"
        symbol="${SYMBOLS[$i]}"

        monitor_bot "$bot_file" "$symbol" || true
    done

    monitor_scanner

    log_msg "========== CYCLE COMPLETE =========="
}

if [ "${1:-}" = "--once" ]; then
    run_cycle
    exit 0
fi

log_msg "Watchdog started (dry-run mode)"
run_cycle
