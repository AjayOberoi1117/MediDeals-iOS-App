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

EXPECTED_UID="$(id -u)"
EXPECTED_USERNAME="$(id -un)"

startup_launch_bot() {
    local bot_file="$1" symbol="$2"
    local log_file="$LOG_DIR/${bot_file%.py}.log"

    local pid
    pid=$(invoke_launch_bot "$bot_file" "$log_file")

    sleep 0.5

    if [ -f "$log_file" ]; then
        echo "✓ $symbol started (PID $pid)"
        return 0
    fi

    if ! invoke_process_alive "$pid" > /dev/null 2>&1; then
        echo "ERROR: $symbol (PID $pid) failed to start"
        return 1
    fi

    echo "✓ $symbol started (PID $pid)"
    return 0
}

start_signal_bots_main() {
    echo "========== SIGNAL-ONLY BOT STARTUP =========="
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Host: $(hostname)"
    echo "Directory: $(pwd)"
    echo "User: $EXPECTED_USERNAME (UID $EXPECTED_UID)"
    echo ""

    if ! require_verified_env_mapping; then
        echo "ERROR: Environment mapping not verified"
        return 1
    fi

    if ! validate_env; then
        echo "ERROR: Environment validation failed"
        return 1
    fi

    if ! check_prohibited_processes; then
        echo "ERROR: Prohibited process detected - startup blocked"
        return 1
    fi

    if ! check_prohibited_files; then
        echo "ERROR: Prohibited file detected - startup blocked"
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

        set +e
        existing=$(find_process "$bot_file" "$SCRIPT_DIR" "$EXPECTED_UID" "$EXPECTED_USERNAME" 2>/dev/null)
        status=$?
        set -e

        case "$status" in
            $PROCESS_ABSENT)
                echo "  $symbol: no existing process"
                ;;
            $PROCESS_SINGLE)
                echo "  $symbol: existing process (PID $existing) - SKIPPING START"
                ;;
            $PROCESS_DUPLICATE)
                echo "ERROR: Duplicate $symbol processes detected"
                return 1
                ;;
            $PROCESS_ERROR)
                echo "ERROR: Process validation error for $symbol"
                return 1
                ;;
        esac
    done
    echo ""

    echo "Starting bots..."
    for i in "${!APPROVED_BOTS[@]}"; do
        bot_file="${APPROVED_BOTS[$i]}"
        symbol="${SYMBOLS[$i]}"

        set +e
        existing=$(find_process "$bot_file" "$SCRIPT_DIR" "$EXPECTED_UID" "$EXPECTED_USERNAME" 2>/dev/null)
        status=$?
        set -e

        if [ "$status" != "$PROCESS_ABSENT" ]; then
            continue
        fi

        if ! startup_launch_bot "$bot_file" "$symbol"; then
            return 1
        fi
    done

    echo ""
    echo "========== STARTUP COMPLETE =========="
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    start_signal_bots_main "$@"
fi
