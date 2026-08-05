#!/bin/bash
#
# Signal-Only Bot Common Library
# Sourceable functions for startup and watchdog validation
#
# Do not execute directly. Source this in other scripts.
#

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

PROHIBITED_PROCESSES=("trader.py" "MT5Trader" "forex_scalper" "token_updater" "mac_trade_writer" "wine")
PROHIBITED_FILES=(".trade_queue.jsonl" "mt5_signals.csv")

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
    local pid="$1" bot_file="$2" expected_script_dir="$3"
    local exe cmdline cwd

    if ! ps -p "$pid" > /dev/null 2>&1; then
        return 1
    fi

    exe=$(readlink "/proc/$pid/exe" 2>/dev/null || echo "")
    if [[ ! "$exe" =~ /usr/bin/python ]]; then
        return 1
    fi

    IFS=$'\0' read -rd '' -a cmdline_arr < "/proc/$pid/cmdline" 2>/dev/null || return 1

    if [ -z "${cmdline_arr[1]:-}" ]; then
        return 1
    fi

    local cmdline_arg="${cmdline_arr[1]}"
    if [[ "$cmdline_arg" != "$expected_script_dir/$bot_file" ]]; then
        if [[ "$cmdline_arg" == /* ]]; then
            return 1
        fi
        if [ "${cmdline_arg##*/}" != "$bot_file" ]; then
            return 1
        fi
        if [ "$(cd "$(dirname "$cmdline_arg")" && pwd)" != "$expected_script_dir" ]; then
            return 1
        fi
    fi

    cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null || echo "")
    if [ "$cwd" != "$expected_script_dir" ]; then
        return 1
    fi

    return 0
}

find_all_processes() {
    local bot_file="$1" expected_script_dir="$2"
    local pid found_pids=()

    while IFS= read -r pid; do
        if [ -n "$pid" ] && validate_process "$pid" "$bot_file" "$expected_script_dir"; then
            found_pids+=("$pid")
        fi
    done < <(pgrep -f "python3" 2>/dev/null || true)

    if [ ${#found_pids[@]} -eq 0 ]; then
        return 0
    fi

    for pid in "${found_pids[@]}"; do
        echo "$pid"
    done
    return 0
}

check_prohibited_processes() {
    local item
    for item in "${PROHIBITED_PROCESSES[@]}"; do
        if pgrep -f "$item" >/dev/null 2>&1; then
            return 1
        fi
    done
    return 0
}

check_prohibited_files() {
    local file item
    for item in "${PROHIBITED_FILES[@]}"; do
        file="$SCRIPT_DIR/$item"
        if [ -f "$file" ]; then
            return 1
        fi
    done
    return 0
}

check_health() {
    local pid="$1" log_file="$2" timeout=5 elapsed=0 start_size=0

    if [ -f "$log_file" ]; then
        start_size=$(stat -c '%s' "$log_file" 2>/dev/null || echo 0)
    fi

    while [ $elapsed -lt $timeout ]; do
        if ! ps -p "$pid" > /dev/null 2>&1; then
            return 1
        fi

        if [ -f "$log_file" ]; then
            local current_size=$(stat -c '%s' "$log_file" 2>/dev/null || echo 0)
            if [ "$current_size" -gt "$start_size" ]; then
                if tail -n +1 "$log_file" | grep -q "Error\|ERROR\|Traceback\|Exception"; then
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
