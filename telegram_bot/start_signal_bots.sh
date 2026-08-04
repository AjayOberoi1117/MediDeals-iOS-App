#!/bin/bash
#
# Start Signal-Only Bots — Forex, Gold, Crypto, Nifty
# Strict validation: process ownership, environment variables, working directory
#
set -e

SCRIPT_DIR="${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
cd "$SCRIPT_DIR"

APPROVED_BOTS=(
    "eurusd_bot.py"
    "gbpusd_bot.py"
    "usdjpy_bot.py"
    "gold_bot.py"
    "btc_bot.py"
    "nifty_scalper.py"
)

SYMBOLS=("EURUSD" "GBPUSD" "USDJPY" "XAUUSD" "BTCUSD" "NIFTY")

ENV_ALLOWLIST=(
    "VANTAGE_EA_TOKEN"
    "BTC_BOT_TOKEN"
    "STOCX_BOT_TOKEN"
    "SIGNAL_CHAT_ID"
)

parse_env() {
    local line key value
    local -a seen_keys

    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"

        if [ -z "$line" ] || [[ "$line" == \#* ]]; then
            continue
        fi

        if [[ ! "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            echo "ERROR: Malformed .env: $line" >&2
            return 1
        fi

        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"

        if [[ " ${seen_keys[@]} " =~ " $key " ]]; then
            echo "ERROR: Duplicate .env key: $key" >&2
            return 1
        fi
        seen_keys+=("$key")

        if [[ ! " ${ENV_ALLOWLIST[@]} " =~ " $key " ]]; then
            continue
        fi

        if [ -z "$value" ]; then
            echo "ERROR: Empty value for $key" >&2
            return 1
        fi

        export "$key"="$value"
    done < "$SCRIPT_DIR/.env"

    return 0
}

validate_env() {
    if [ ! -f "$SCRIPT_DIR/.env" ]; then
        echo "ERROR: .env not found" >&2
        return 1
    fi

    if ! parse_env; then
        return 1
    fi

    local required=("VANTAGE_EA_TOKEN" "BTC_BOT_TOKEN" "STOCX_BOT_TOKEN" "SIGNAL_CHAT_ID")
    local var
    for var in "${required[@]}"; do
        if [ -z "${!var:-}" ]; then
            echo "ERROR: Required variable not set: $var" >&2
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

check_existing_process() {
    local bot_file="$1" symbol="$2"
    local pid found_pid count=0

    while IFS= read -r pid; do
        if [ -n "$pid" ] && validate_process "$pid" "$bot_file"; then
            found_pid="$pid"
            count=$((count + 1))
        fi
    done < <(pgrep -f "python3" 2>/dev/null || true)

    if [ $count -eq 0 ]; then
        return 0
    elif [ $count -eq 1 ]; then
        echo "$found_pid"
        return 2
    else
        return 1
    fi
}

echo "========== SIGNAL-ONLY BOT STARTUP =========="
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Host: $(hostname)"
echo "Directory: $(pwd)"
echo ""

if ! validate_env; then
    echo "ERROR: Environment validation failed"
    exit 1
fi

echo "Validating bot files..."
for bot_file in "${APPROVED_BOTS[@]}"; do
    if [ ! -f "$bot_file" ]; then
        echo "ERROR: Bot file not found: $bot_file"
        exit 1
    fi
done
echo "✓ All 6 bot files present"
echo ""

echo "Checking for existing processes..."
for i in "${!APPROVED_BOTS[@]}"; do
    bot_file="${APPROVED_BOTS[$i]}"
    symbol="${SYMBOLS[$i]}"

    existing=$(check_existing_process "$bot_file" "$symbol" 2>/dev/null)
    status=$?

    if [ $status -eq 0 ]; then
        echo "  $symbol: no existing process"
    elif [ $status -eq 2 ]; then
        echo "  $symbol: existing process (PID $existing) - SKIPPING START"
    else
        echo "ERROR: Duplicate $symbol processes detected"
        exit 1
    fi
done
echo ""

echo "Starting bots..."
for i in "${!APPROVED_BOTS[@]}"; do
    bot_file="${APPROVED_BOTS[$i]}"
    symbol="${SYMBOLS[$i]}"

    existing=$(check_existing_process "$bot_file" "$symbol" 2>/dev/null)
    status=$?

    if [ $status -eq 2 ]; then
        continue
    fi

    log_file="$LOG_DIR/${bot_file%.py}.log"
    nohup python3 "$bot_file" > "$log_file" 2>&1 &
    pid=$!

    sleep 2

    if ! ps -p "$pid" > /dev/null 2>&1; then
        echo "ERROR: $symbol (PID $pid) failed to start"
        exit 1
    fi

    if [ ! -f "$log_file" ]; then
        echo "ERROR: $symbol log file not created: $log_file"
        exit 1
    fi

    echo "✓ $symbol started (PID $pid)"
done

echo ""
echo "========== STARTUP COMPLETE =========="
