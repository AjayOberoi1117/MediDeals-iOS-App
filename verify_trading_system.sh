#!/usr/bin/env bash
################################################################################
# Verify Trading System - Runtime Gate Verification
# ==================================================
#
# Outputs PASS/FAIL status for each of 19 runtime verification gates.
# Designed for automation (exit code 0 = all pass, 1 = failures).
#
# Usage:
#   bash verify_trading_system.sh
#   bash verify_trading_system.sh --json       (JSON output)
#   bash verify_trading_system.sh --verbose    (detailed output)
#
# Output:
#   [PASS] Gate 1: Xvfb running
#   [FAIL] Gate 2: MT5 terminal running
#   ...
#   Summary: 18/19 gates passed
#
# Exit Code:
#   0 = all gates pass
#   1 = one or more gates fail
#
################################################################################

set -euo pipefail

################################################################################
# CONFIG
################################################################################

BOT_DIR="/root/MediDeals-iOS-App/telegram_bot"
BRIDGE_PORT=18812
LOG_DIR="${BOT_DIR}/logs"

# Output format
FORMAT="text"  # text, json, verbose
VERBOSE=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            FORMAT="json"
            shift
            ;;
        --verbose)
            VERBOSE=1
            shift
            ;;
        *)
            shift
            ;;
    esac
done

################################################################################
# STATE
################################################################################

declare -a GATES
declare -a RESULTS

PASS_COUNT=0
FAIL_COUNT=0

################################################################################
# FUNCTIONS
################################################################################

record_gate() {
    local gate_num=$1
    local gate_name=$2
    local result=$3
    local detail=${4:-""}

    GATES+=("$gate_num:$gate_name")
    RESULTS+=("$result")

    if [[ "$result" == "PASS" ]]; then
        ((PASS_COUNT++))
        if [[ $VERBOSE -eq 1 ]]; then
            echo "[PASS] Gate $gate_num: $gate_name"
            if [[ -n "$detail" ]]; then
                echo "       $detail"
            fi
        fi
    else
        ((FAIL_COUNT++))
        if [[ $VERBOSE -eq 1 ]]; then
            echo "[FAIL] Gate $gate_num: $gate_name"
            if [[ -n "$detail" ]]; then
                echo "       $detail"
            fi
        fi
    fi
}

output_text() {
    echo ""
    for i in "${!GATES[@]}"; do
        local gate="${GATES[$i]}"
        local result="${RESULTS[$i]}"
        local gate_num=$(echo "$gate" | cut -d: -f1)
        local gate_name=$(echo "$gate" | cut -d: -f2-)

        if [[ "$result" == "PASS" ]]; then
            echo "[PASS] Gate $gate_num: $gate_name"
        else
            echo "[FAIL] Gate $gate_num: $gate_name"
        fi
    done

    echo ""
    echo "Summary: $PASS_COUNT/19 gates passed"
    echo ""

    if [[ $FAIL_COUNT -gt 0 ]]; then
        echo "Failed gates: $FAIL_COUNT"
        exit 1
    else
        echo "All gates passed ✓"
        exit 0
    fi
}

output_json() {
    local json_gates="["
    for i in "${!GATES[@]}"; do
        local gate="${GATES[$i]}"
        local result="${RESULTS[$i]}"
        local gate_num=$(echo "$gate" | cut -d: -f1)
        local gate_name=$(echo "$gate" | cut -d: -f2-)

        if [[ $i -gt 0 ]]; then
            json_gates="$json_gates,"
        fi

        json_gates="$json_gates{\"gate\":$gate_num,\"name\":\"$gate_name\",\"status\":\"$result\"}"
    done
    json_gates="$json_gates]"

    local overall="PASS"
    if [[ $FAIL_COUNT -gt 0 ]]; then
        overall="FAIL"
    fi

    echo "{\"overall\":\"$overall\",\"passed\":$PASS_COUNT,\"failed\":$FAIL_COUNT,\"total\":19,\"gates\":$json_gates}"

    if [[ $FAIL_COUNT -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

################################################################################
# VERIFICATION GATES
################################################################################

gate_1_xvfb() {
    if pgrep -x Xvfb >/dev/null 2>&1; then
        record_gate 1 "Xvfb running" "PASS"
    else
        record_gate 1 "Xvfb running" "FAIL" "No Xvfb process found"
    fi
}

gate_2_mt5_terminal() {
    if pgrep -f "terminal64.exe" >/dev/null 2>&1; then
        record_gate 2 "MT5 terminal running" "PASS"
    else
        record_gate 2 "MT5 terminal running" "FAIL" "No terminal64.exe process found"
    fi
}

gate_3_wine_server() {
    if pgrep -f "wine_server\.py" >/dev/null 2>&1; then
        record_gate 3 "wine_server.py running" "PASS"
    else
        record_gate 3 "wine_server.py running" "FAIL" "No wine_server.py process found"
    fi
}

gate_4_bridge_listening() {
    if timeout 2 bash -c "</dev/tcp/localhost/${BRIDGE_PORT}" 2>/dev/null; then
        record_gate 4 "Bridge port 18812 listening" "PASS"
    else
        record_gate 4 "Bridge port 18812 listening" "FAIL" "Bridge port not responding"
    fi
}

gate_5_trader_running() {
    if pgrep -f "python3.*trader\.py" >/dev/null 2>&1; then
        record_gate 5 "trader.py running" "PASS"
    else
        record_gate 5 "trader.py running" "FAIL" "No trader.py process found"
    fi
}

gate_6_forex_scalper() {
    if pgrep -f "python3.*forex_scalper\.py" >/dev/null 2>&1; then
        record_gate 6 "forex_scalper.py running" "PASS"
    else
        record_gate 6 "forex_scalper.py running" "FAIL" "No forex_scalper.py process found"
    fi
}

gate_7_gold_bot() {
    if pgrep -f "python3.*gold_bot\.py" >/dev/null 2>&1; then
        record_gate 7 "gold_bot.py running" "PASS"
    else
        record_gate 7 "gold_bot.py running" "FAIL" "No gold_bot.py process found"
    fi
}

gate_8_btc_bot() {
    if pgrep -f "python3.*btc_bot\.py" >/dev/null 2>&1; then
        record_gate 8 "btc_bot.py running" "PASS"
    else
        record_gate 8 "btc_bot.py running" "FAIL" "No btc_bot.py process found"
    fi
}

gate_9_nifty_scalper() {
    if pgrep -f "python3.*nifty_scalper\.py" >/dev/null 2>&1; then
        record_gate 9 "nifty_scalper.py running" "PASS"
    else
        record_gate 9 "nifty_scalper.py running" "FAIL" "No nifty_scalper.py process found"
    fi
}

gate_10_token_updater() {
    if pgrep -f "python3.*token_updater_bot\.py" >/dev/null 2>&1; then
        record_gate 10 "token_updater_bot.py running" "PASS"
    else
        record_gate 10 "token_updater_bot.py running" "FAIL" "No token_updater_bot.py process found"
    fi
}

gate_11_single_trader() {
    local count=$(pgrep -f "python3.*trader\.py" 2>/dev/null | wc -l)
    if [[ $count -eq 1 ]]; then
        record_gate 11 "Single trader.py instance" "PASS"
    else
        record_gate 11 "Single trader.py instance" "FAIL" "Found $count instances"
    fi
}

gate_12_single_forex() {
    local count=$(pgrep -f "python3.*forex_scalper\.py" 2>/dev/null | wc -l)
    if [[ $count -eq 1 ]]; then
        record_gate 12 "Single forex_scalper.py instance" "PASS"
    else
        record_gate 12 "Single forex_scalper.py instance" "FAIL" "Found $count instances"
    fi
}

gate_13_single_gold() {
    local count=$(pgrep -f "python3.*gold_bot\.py" 2>/dev/null | wc -l)
    if [[ $count -eq 1 ]]; then
        record_gate 13 "Single gold_bot.py instance" "PASS"
    else
        record_gate 13 "Single gold_bot.py instance" "FAIL" "Found $count instances"
    fi
}

gate_14_env_permissions() {
    local perms=$(stat -c %a "${BOT_DIR}/.env" 2>/dev/null || echo "unknown")
    if [[ "$perms" == "600" ]]; then
        record_gate 14 ".env permissions secure (600)" "PASS"
    else
        record_gate 14 ".env permissions secure (600)" "FAIL" "Permissions are $perms"
    fi
}

gate_15_log_errors() {
    local error_count=$(tail -100 "$LOG_DIR"/*.log 2>/dev/null | grep -ic "error\|failed\|exception" || echo 0)
    if [[ $error_count -lt 10 ]]; then
        record_gate 15 "Log errors under threshold" "PASS" "Found $error_count errors"
    else
        record_gate 15 "Log errors under threshold" "FAIL" "Found $error_count errors"
    fi
}

gate_16_bridge_responsive() {
    if python3 -c "import socket; s = socket.socket(); s.connect(('localhost', $BRIDGE_PORT)); s.close()" 2>/dev/null; then
        record_gate 16 "Bridge responsive" "PASS"
    else
        record_gate 16 "Bridge responsive" "FAIL" "Cannot connect to bridge"
    fi
}

gate_17_trade_queue() {
    if [[ -f "${BOT_DIR}/.trade_queue.jsonl" ]] || touch "${BOT_DIR}/.trade_queue.jsonl" 2>/dev/null; then
        record_gate 17 ".trade_queue.jsonl accessible" "PASS"
    else
        record_gate 17 ".trade_queue.jsonl accessible" "FAIL" "Cannot create/access file"
    fi
}

gate_18_india_safety() {
    if [[ -f "${BOT_DIR}/trader.py" ]]; then
        if grep -q "TRADEABLE" "${BOT_DIR}/trader.py" 2>/dev/null; then
            local india_safe=true
            for symbol in NIFTY BANKNIFTY FINNIFTY; do
                if grep "TRADEABLE" "${BOT_DIR}/trader.py" 2>/dev/null | grep -qi "$symbol"; then
                    india_safe=false
                    break
                fi
            done
            if [[ "$india_safe" == true ]]; then
                record_gate 18 "India symbols not in TRADEABLE" "PASS"
            else
                record_gate 18 "India symbols not in TRADEABLE" "FAIL" "India symbol found in TRADEABLE"
            fi
        else
            record_gate 18 "India symbols not in TRADEABLE" "PASS" "No TRADEABLE list (safe default)"
        fi
    else
        record_gate 18 "India symbols not in TRADEABLE" "FAIL" "trader.py not found"
    fi
}

gate_19_boot_persistence() {
    if crontab -l 2>/dev/null | grep -q "start_trading_system.sh"; then
        record_gate 19 "Boot persistence enabled" "PASS"
    else
        record_gate 19 "Boot persistence enabled" "FAIL" "Not found in crontab"
    fi
}

################################################################################
# MAIN
################################################################################

main() {
    # Run all gates
    gate_1_xvfb
    gate_2_mt5_terminal
    gate_3_wine_server
    gate_4_bridge_listening
    gate_5_trader_running
    gate_6_forex_scalper
    gate_7_gold_bot
    gate_8_btc_bot
    gate_9_nifty_scalper
    gate_10_token_updater
    gate_11_single_trader
    gate_12_single_forex
    gate_13_single_gold
    gate_14_env_permissions
    gate_15_log_errors
    gate_16_bridge_responsive
    gate_17_trade_queue
    gate_18_india_safety
    gate_19_boot_persistence

    # Output results
    if [[ "$FORMAT" == "json" ]]; then
        output_json
    else
        output_text
    fi
}

main "$@"
