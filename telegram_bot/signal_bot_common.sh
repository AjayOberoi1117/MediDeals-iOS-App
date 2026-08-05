#!/bin/bash
#
# Signal-Only Bot Common Library
# Sourceable functions for startup and watchdog validation
#

# Status code constants
PROCESS_ABSENT=0
PROCESS_SINGLE=10
PROCESS_DUPLICATE=20
PROCESS_ERROR=30

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

PROHIBITED_PROCESS_NAMES=("trader.py" "forex_scalper.py" "token_updater_bot.py" "mac_trade_writer.py" "wine" "wine64" "MT5Trader" "terminal64.exe")
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
    local pid="$1" bot_file="$2" expected_script_dir="$3" expected_uid="$4" expected_username="$5"
    local exe cmdline cwd proc_uid proc_user cmdline_arg

    if ! ps -p "$pid" > /dev/null 2>&1; then
        return 1
    fi

    exe=$(readlink "/proc/$pid/exe" 2>/dev/null || echo "")
    if [[ ! "$exe" =~ /usr/bin/python ]]; then
        return 1
    fi

    cmdline_arg=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | awk '{print $2}')
    if [ -z "$cmdline_arg" ]; then
        return 1
    fi

    if [[ "$cmdline_arg" != "$expected_script_dir/$bot_file" ]]; then
        if [[ "$cmdline_arg" == /* ]]; then
            return 1
        fi
        if [ "${cmdline_arg##*/}" != "$bot_file" ]; then
            return 1
        fi
        if [ "$(cd "$(dirname "$cmdline_arg")" 2>/dev/null && pwd)" != "$expected_script_dir" ]; then
            return 1
        fi
    fi

    cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null || echo "")
    if [ "$cwd" != "$expected_script_dir" ]; then
        return 1
    fi

    if [ -n "$expected_uid" ]; then
        proc_uid=$(stat -c '%u' "/proc/$pid" 2>/dev/null || echo "")
        if [ "$proc_uid" != "$expected_uid" ]; then
            return 1
        fi
    fi

    if [ -n "$expected_username" ]; then
        proc_user=$(stat -c '%U' "/proc/$pid" 2>/dev/null || echo "")
        if [ "$proc_user" != "$expected_username" ]; then
            return 1
        fi
    fi

    return 0
}

find_process() {
    local bot_file="$1" script_dir="$2" expected_uid="$3" expected_username="$4"
    local pid found_pids=()

    if [ -z "$script_dir" ] || [ -z "$expected_uid" ] || [ -z "$expected_username" ]; then
        echo "ERROR: find_process requires script_dir, expected_uid, expected_username" >&2
        return $PROCESS_ERROR
    fi

    while IFS= read -r pid; do
        if [ -n "$pid" ] && validate_process "$pid" "$bot_file" "$script_dir" "$expected_uid" "$expected_username"; then
            found_pids+=("$pid")
        fi
    done < <(pgrep -f "python3" 2>/dev/null || true)

    local count=${#found_pids[@]}
    if [ $count -eq 0 ]; then
        return $PROCESS_ABSENT
    elif [ $count -eq 1 ]; then
        echo "${found_pids[0]}"
        return $PROCESS_SINGLE
    else
        return $PROCESS_DUPLICATE
    fi
}

check_prohibited_processes() {
    local item pid exe cmdline

    while IFS= read -r pid; do
        if [ -z "$pid" ] || ! ps -p "$pid" > /dev/null 2>&1; then
            continue
        fi

        exe=$(readlink "/proc/$pid/exe" 2>/dev/null || echo "")
        cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || echo "")

        for item in "${PROHIBITED_PROCESS_NAMES[@]}"; do
            if [[ "$cmdline" =~ $item ]]; then
                if [[ "$exe" =~ python ]] || [[ "$exe" =~ wine ]] || [[ "$exe" =~ MT5Trader ]] || [[ "$exe" =~ terminal ]]; then
                    return 1
                fi
            fi
        done
    done < <(pgrep -a . 2>/dev/null | awk '{print $1}' || true)

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
    local pid="$1" log_file="$2" start_offset="$3" expected_marker="$4"
    local timeout=5 elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if ! ps -p "$pid" > /dev/null 2>&1; then
            echo "FAILED"
            return 1
        fi

        if [ -f "$log_file" ] && [ -n "$expected_marker" ]; then
            local new_content
            new_content=$(tail -c +$((start_offset + 1)) "$log_file" 2>/dev/null || echo "")

            if echo "$new_content" | grep -q "Error\|ERROR\|Traceback\|Exception"; then
                echo "FAILED"
                return 1
            fi

            if echo "$new_content" | grep -q "$expected_marker"; then
                echo "HEALTHY"
                return 0
            fi
        fi

        sleep 1
        elapsed=$((elapsed + 1))
    done

    if ps -p "$pid" > /dev/null 2>&1; then
        echo "ALIVE_UNVERIFIED"
        return 1
    fi

    echo "FAILED"
    return 1
}
