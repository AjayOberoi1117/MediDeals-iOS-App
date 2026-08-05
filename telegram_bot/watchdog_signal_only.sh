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

source "$SCRIPT_DIR/signal_bot_common.sh"

log_msg() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$WATCHDOG_LOG"
}

monitor_scanner() {
    local pids=()
    local pid

    while IFS= read -r pid; do
        pids+=("$pid")
    done < <(find_all_processes "$SCANNER_BOT" "$SCRIPT_DIR")

    if [ ${#pids[@]} -eq 0 ]; then
        log_msg "OBSERVE: Scanner not running (no action)"
        return 0
    fi

    for pid in "${pids[@]}"; do
        if ps -p "$pid" > /dev/null 2>&1; then
            log_msg "OBSERVE: Scanner running (PID $pid, no action)"
        else
            log_msg "OBSERVE: Scanner crashed (no auto-restart)"
        fi
    done

    return 0
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

monitor_bot() {
    local bot_file="$1" symbol="$2"
    local pids=()
    local pid

    while IFS= read -r pid; do
        pids+=("$pid")
    done < <(find_all_processes "$bot_file" "$SCRIPT_DIR")

    local count=${#pids[@]}

    if [ $count -eq 0 ]; then
        log_msg "ALERT: $symbol is not running"

        if ! validate_env; then
            log_msg "SKIP RESTART: .env validation failed for $symbol"
            return 1
        fi

        restart_bot "$bot_file" "$symbol"
        return $?
    elif [ $count -eq 1 ]; then
        pid="${pids[0]}"
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
    else
        log_msg "CRITICAL: Multiple $symbol processes detected: ${pids[*]}"
        log_msg "CRITICAL: Manual review required - no restart attempted"
        return 1
    fi
}

run_cycle() {
    log_msg "========== WATCHDOG CYCLE =========="

    if ! check_prohibited_processes; then
        log_msg "CRITICAL: Prohibited process detected - blocking all restarts"
        log_msg "========== CYCLE COMPLETE =========="
        return 1
    fi

    if ! check_prohibited_files; then
        log_msg "CRITICAL: Prohibited file detected - blocking all restarts"
        log_msg "========== CYCLE COMPLETE =========="
        return 1
    fi

    for i in "${!APPROVED_BOTS[@]}"; do
        bot_file="${APPROVED_BOTS[$i]}"
        symbol="${SYMBOLS[$i]}"

        monitor_bot "$bot_file" "$symbol" || true
    done

    monitor_scanner

    log_msg "========== CYCLE COMPLETE =========="
    return 0
}

main() {
    if [ "${1:-}" = "--once" ]; then
        run_cycle
        return $?
    fi

    log_msg "Watchdog started (dry-run mode)"
    run_cycle
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
