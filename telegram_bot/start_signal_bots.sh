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

source "$SCRIPT_DIR/signal_bot_common.sh"

check_existing_process() {
    local bot_file="$1"
    local pid found_pids=()

    while IFS= read -r pid; do
        if [ -n "$pid" ] && validate_process "$pid" "$bot_file" "$SCRIPT_DIR"; then
            found_pids+=("$pid")
        fi
    done < <(pgrep -f "python3" 2>/dev/null || true)

    local count=${#found_pids[@]}
    if [ $count -eq 0 ]; then
        return 0
    elif [ $count -eq 1 ]; then
        echo "${found_pids[0]}"
        return 2
    else
        return 1
    fi
}

main() {
    echo "========== SIGNAL-ONLY BOT STARTUP =========="
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Host: $(hostname)"
    echo "Directory: $(pwd)"
    echo ""

    if ! validate_env; then
        echo "ERROR: Environment validation failed"
        return 1
    fi

    echo "Validating bot files..."
    for bot_file in "${APPROVED_BOTS[@]}"; do
        if [ ! -f "$bot_file" ]; then
            echo "ERROR: Bot file not found: $bot_file"
            return 1
        fi
    done
    echo "✓ All 6 bot files present"
    echo ""

    echo "Checking for existing processes..."
    for i in "${!APPROVED_BOTS[@]}"; do
        bot_file="${APPROVED_BOTS[$i]}"
        symbol="${SYMBOLS[$i]}"

        existing=$(check_existing_process "$bot_file" 2>/dev/null) || {
            status=$?
            if [ $status -eq 1 ]; then
                echo "ERROR: Duplicate $symbol processes detected"
                return 1
            fi
            existing=""
        }
        status=$?

        if [ $status -eq 0 ]; then
            echo "  $symbol: no existing process"
        elif [ $status -eq 2 ]; then
            echo "  $symbol: existing process (PID $existing) - SKIPPING START"
        fi
    done
    echo ""

    echo "Starting bots..."
    for i in "${!APPROVED_BOTS[@]}"; do
        bot_file="${APPROVED_BOTS[$i]}"
        symbol="${SYMBOLS[$i]}"

        existing=$(check_existing_process "$bot_file" 2>/dev/null) || {
            status=$?
            if [ $status -eq 1 ]; then
                return 1
            fi
            existing=""
        }
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
            return 1
        fi

        if [ ! -f "$log_file" ]; then
            echo "ERROR: $symbol log file not created: $log_file"
            return 1
        fi

        echo "✓ $symbol started (PID $pid)"
    done

    echo ""
    echo "========== STARTUP COMPLETE =========="
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
