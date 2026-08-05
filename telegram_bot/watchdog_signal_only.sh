#!/bin/bash
#
# Signal-Only Watchdog — Monitor and auto-restart approved bots
# Strict validation: no process termination, observe-only for scanner
# FAILURE PROPAGATION: returns non-zero when any managed bot fails
#
set -e

SCRIPT_DIR="${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
cd "$SCRIPT_DIR"

WATCHDOG_LOG="$LOG_DIR/watchdog.log"

source "$SCRIPT_DIR/signal_bot_common.sh"

EXPECTED_UID="$(id -u)"
EXPECTED_USERNAME="$(id -un)"

CYCLE_HEALTHY=0
CYCLE_FAILED=1

log_msg() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$WATCHDOG_LOG"
}

monitor_scanner() {
    set +e
    local pid
    pid=$(find_process "$SCANNER_BOT" "$SCRIPT_DIR" "$EXPECTED_UID" "$EXPECTED_USERNAME" 2>/dev/null)
    local status=$?
    set -e

    case "$status" in
        $PROCESS_ABSENT)
            log_msg "OBSERVE: Scanner not running (no action)"
            return $CYCLE_HEALTHY
            ;;
        $PROCESS_SINGLE)
            log_msg "OBSERVE: Scanner running (PID $pid, no action)"
            return $CYCLE_HEALTHY
            ;;
        $PROCESS_DUPLICATE)
            log_msg "CRITICAL: Multiple scanner instances (no action)"
            return $CYCLE_HEALTHY
            ;;
        *)
            log_msg "OBSERVE: Scanner validation error"
            return $CYCLE_HEALTHY
            ;;
    esac
}

restart_bot() {
    local bot_file="$1" symbol="$2"

    if [ ! -f "$bot_file" ]; then
        log_msg "RESTART FAILED: Bot file not found: $bot_file"
        return $CYCLE_FAILED
    fi

    if ! require_verified_env_mapping; then
        log_msg "RESTART BLOCKED: Environment mapping unverified for $symbol"
        return $CYCLE_FAILED
    fi

    log_file="$LOG_DIR/${bot_file%.py}.log"
    log_msg "RESTART: $symbol ($bot_file)"

    start_offset=$(stat -c '%s' "$log_file" 2>/dev/null || echo 0)

    local pid
    pid=$(invoke_launch_bot "$bot_file" "$log_file")

    health_result=$(check_health "$pid" "$log_file" "$start_offset" "")
    local health_status=$?

    case "$health_result" in
        HEALTHY)
            log_msg "RESTART SUCCESS: $symbol (PID $pid)"
            return $CYCLE_HEALTHY
            ;;
        ALIVE_UNVERIFIED)
            log_msg "RESTART UNVERIFIED: $symbol (PID $pid) alive but unverified"
            return $CYCLE_FAILED
            ;;
        FAILED)
            log_msg "RESTART FAILED: $symbol (PID $pid)"
            return $CYCLE_FAILED
            ;;
    esac

    return $CYCLE_FAILED
}

monitor_bot() {
    local bot_file="$1" symbol="$2"

    set +e
    local pid
    pid=$(find_process "$bot_file" "$SCRIPT_DIR" "$EXPECTED_UID" "$EXPECTED_USERNAME" 2>/dev/null)
    local status=$?
    set -e

    case "$status" in
        $PROCESS_ABSENT)
            log_msg "ALERT: $symbol is not running"

            if ! validate_env; then
                log_msg "SKIP RESTART: .env validation failed for $symbol"
                return $CYCLE_FAILED
            fi

            restart_bot "$bot_file" "$symbol"
            return $?
            ;;
        $PROCESS_SINGLE)
            if invoke_process_alive "$pid" > /dev/null 2>&1; then
                return $CYCLE_HEALTHY
            else
                log_msg "ALERT: $symbol crashed (PID $pid)"

                if ! validate_env; then
                    log_msg "SKIP RESTART: .env validation failed for $symbol"
                    return $CYCLE_FAILED
                fi

                restart_bot "$bot_file" "$symbol"
                return $?
            fi
            ;;
        $PROCESS_DUPLICATE)
            log_msg "CRITICAL: Multiple $symbol processes detected - manual review required"
            return $CYCLE_FAILED
            ;;
        $PROCESS_ERROR)
            log_msg "ERROR: Process validation error for $symbol"
            return $CYCLE_FAILED
            ;;
    esac

    return $CYCLE_FAILED
}

run_cycle() {
    log_msg "========== WATCHDOG CYCLE =========="

    if ! check_prohibited_processes; then
        log_msg "CRITICAL: Prohibited process detected - blocking all restarts"
        log_msg "========== CYCLE FAILED =========="
        return $CYCLE_FAILED
    fi

    if ! check_prohibited_files; then
        log_msg "CRITICAL: Prohibited file detected - blocking all restarts"
        log_msg "========== CYCLE FAILED =========="
        return $CYCLE_FAILED
    fi

    local cycle_status=$CYCLE_HEALTHY

    for i in "${!APPROVED_BOTS[@]}"; do
        bot_file="${APPROVED_BOTS[$i]}"
        symbol="${SYMBOLS[$i]}"

        if ! monitor_bot "$bot_file" "$symbol"; then
            cycle_status=$CYCLE_FAILED
        fi
    done

    monitor_scanner

    if [ $cycle_status -eq $CYCLE_HEALTHY ]; then
        log_msg "========== CYCLE HEALTHY =========="
    else
        log_msg "========== CYCLE FAILED =========="
    fi

    return $cycle_status
}

watchdog_run_cycle() {
    if [ "${1:-}" = "--once" ]; then
        run_cycle
        return $?
    fi

    log_msg "Watchdog started (dry-run mode)"
    run_cycle
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    watchdog_run_cycle "$@"
fi
