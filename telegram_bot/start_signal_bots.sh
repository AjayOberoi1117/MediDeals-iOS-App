#!/bin/bash
#
# Start Signal-Only Bots for Forex, Gold, Crypto, and Nifty Trading
# - Starts exactly 6 approved signal bots (no broker execution)
# - Validates existing processes before launching
# - Duplicate symbol protection
# - Signal-only compliance: no queue_trade() calls
#
# Usage: ./start_signal_bots.sh
#

set -e

SCRIPT_DIR="${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
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

SIGNAL_ONLY_SYMBOLS=("EURUSD" "GBPUSD" "USDJPY" "XAUUSD" "BTCUSD" "NIFTY")
REQUIRED_ENV_VARS=("VANTAGE_EA_TOKEN" "BTC_BOT_TOKEN" "SIGNAL_CHAT_ID")

validate_env() {
    if [ ! -f "$SCRIPT_DIR/.env" ]; then
        echo "ERROR: .env not found at $SCRIPT_DIR/.env" >&2
        return 1
    fi

    local var
    local missing=0

    for var in "${REQUIRED_ENV_VARS[@]}"; do
        if ! grep -q "^${var}=" "$SCRIPT_DIR/.env"; then
            echo "ERROR: Required variable $var not found in .env" >&2
            missing=$((missing + 1))
        fi
    done

    if [ $missing -gt 0 ]; then
        return 1
    fi

    return 0
}

parse_and_export_env() {
    local line
    local key
    local value

    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        if [ -z "$line" ] || [[ "$line" == \#* ]]; then
            continue
        fi

        if [[ ! "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            echo "ERROR: Malformed .env line: $line" >&2
            return 1
        fi

        key="${line%%=*}"
        value="${line#*=}"

        if [ -z "$value" ]; then
            echo "ERROR: Empty value for required variable: $key" >&2
            return 1
        fi

        export "$key"="$value"
    done < "$SCRIPT_DIR/.env"

    return 0
}

validate_process() {
    local pid="$1"
    local bot_file="$2"
    local expected_owner="${3:-root}"

    if ! ps -p "$pid" > /dev/null 2>&1; then
        return 1
    fi

    local exe
    exe=$(readlink "/proc/$pid/exe" 2>/dev/null || echo "")
    if [ "$exe" != "/usr/bin/python3" ] && [ "$exe" != "/usr/bin/python" ]; then
        return 1
    fi

    local cmdline
    cmdline=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ' || echo "")

    if ! echo "$cmdline" | grep -q "$bot_file"; then
        return 1
    fi

    local cwd
    cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null || echo "")
    if [ "$cwd" != "$SCRIPT_DIR" ]; then
        return 1
    fi

    return 0
}

find_existing_process() {
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

check_existing_processes() {
    local bot_file="$1"
    local symbol="$2"
    local existing_pids=()
    local pid

    while IFS= read -r pid; do
        if [ -n "$pid" ]; then
            if validate_process "$pid" "$bot_file"; then
                existing_pids+=("$pid")
            fi
        fi
    done < <(pgrep -f "python3.*${bot_file}" 2>/dev/null || true)

    if [ ${#existing_pids[@]} -eq 0 ]; then
        return 0
    fi

    if [ ${#existing_pids[@]} -eq 1 ]; then
        echo "ALERT: $symbol ($bot_file) already running at PID ${existing_pids[0]}"
        return 2
    fi

    echo "ERROR: Multiple $symbol processes detected: ${existing_pids[*]}"
    return 1
}

started_in_this_invocation() {
    local symbol="$1"
    local index
    for index in "${!STARTED_SYMBOLS[@]}"; do
        if [ "${STARTED_SYMBOLS[$index]}" = "$symbol" ]; then
            return 0
        fi
    done
    return 1
}

STARTED_SYMBOLS=()
STARTED_PIDS=()

echo "=========================================="
echo "SIGNAL-ONLY BOT STARTUP"
echo "=========================================="
echo "Host: $(hostname)"
echo "Directory: $(pwd)"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo ""

if ! validate_env; then
    echo "ERROR: Environment validation failed"
    exit 1
fi

if ! parse_and_export_env; then
    echo "ERROR: Failed to parse .env"
    exit 1
fi

echo "Validating bot files..."
for bot_file in "${APPROVED_BOTS[@]}"; do
    if [ ! -f "$SCRIPT_DIR/$bot_file" ]; then
        echo "ERROR: Bot file not found: $SCRIPT_DIR/$bot_file"
        exit 1
    fi
done
echo "✓ All 6 bot files present"
echo ""

echo "Checking for existing processes..."
DUPLICATE_DETECTED=0
for i in "${!APPROVED_BOTS[@]}"; do
    bot_file="${APPROVED_BOTS[$i]}"
    symbol="${SIGNAL_ONLY_SYMBOLS[$i]}"

    check_existing_processes "$bot_file" "$symbol"
    status=$?

    if [ $status -eq 1 ]; then
        DUPLICATE_DETECTED=1
        break
    elif [ $status -eq 2 ]; then
        echo "SKIPPING: $symbol is already running"
        STARTED_SYMBOLS+=("$symbol")
        continue
    fi
done

if [ $DUPLICATE_DETECTED -eq 1 ]; then
    echo "ERROR: Cannot proceed with duplicate processes detected"
    exit 1
fi

echo ""
echo "Starting bots..."
for i in "${!APPROVED_BOTS[@]}"; do
    bot_file="${APPROVED_BOTS[$i]}"
    symbol="${SIGNAL_ONLY_SYMBOLS[$i]}"

    if started_in_this_invocation "$symbol"; then
        continue
    fi

    STARTED_SYMBOLS+=("$symbol")

    if [ ! -f "$SCRIPT_DIR/$bot_file" ]; then
        echo "ERROR: File not found: $bot_file"
        exit 1
    fi

    log_file="$LOG_DIR/${bot_file%.py}.log"
    nohup python3 "$SCRIPT_DIR/$bot_file" > "$log_file" 2>&1 &
    pid=$!
    STARTED_PIDS+=("$pid")

    sleep 1

    if ps -p "$pid" > /dev/null 2>&1; then
        if [ -f "$log_file" ]; then
            echo "✓ $symbol ($bot_file) started at PID $pid"
            echo "  Log: $log_file"
        else
            echo "ERROR: $symbol started but log not found: $log_file"
            exit 1
        fi
    else
        echo "ERROR: $symbol ($bot_file) failed to start (PID $pid)"
        exit 1
    fi
done

echo ""
echo "=========================================="
echo "STARTUP COMPLETE"
echo "=========================================="
echo "Started bots: ${STARTED_SYMBOLS[*]}"
echo "PIDs: ${STARTED_PIDS[*]}"
echo "Log directory: $LOG_DIR"
echo ""
