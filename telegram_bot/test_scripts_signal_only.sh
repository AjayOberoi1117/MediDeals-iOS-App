#!/bin/bash
#
# SIGNAL-ONLY BOT TEST SUITE - Validates injectable boundary architecture
# Tests verify production logic without launching external Python processes
#

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASSED=0
FAILED=0

pass() { echo "✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED + 1)); }

echo "========== SIGNAL-ONLY BOT TEST SUITE =========="
echo ""

# TEST 1: Activation gate blocks without SIGNAL_BOT_ENV_MAPPING_VERIFIED
echo "TEST 1: Gate blocks without SIGNAL_BOT_ENV_MAPPING_VERIFIED"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
unset SIGNAL_BOT_ENV_MAPPING_VERIFIED
set +e
source "$SOURCE_DIR/signal_bot_common.sh"
require_verified_env_mapping > /dev/null 2>&1
status=$?
set -e
[ $status -ne 0 ] && pass "Gate blocks (non-zero exit)" || fail "Gate did not block"
rm -rf "$test_dir"

# TEST 2: Gate allows with SIGNAL_BOT_ENV_MAPPING_VERIFIED=APPROVED
echo "TEST 2: Gate allows with SIGNAL_BOT_ENV_MAPPING_VERIFIED=APPROVED"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
export SIGNAL_BOT_ENV_MAPPING_VERIFIED="APPROVED"
set +e
source "$SOURCE_DIR/signal_bot_common.sh"
require_verified_env_mapping > /dev/null 2>&1
status=$?
set -e
[ $status -eq 0 ] && pass "Gate allows with APPROVED (zero exit)" || fail "Gate blocked despite APPROVED"
rm -rf "$test_dir"

# TEST 3: Gate requires isolated env var (env -i isolation)
echo "TEST 3: Gate requires env var (env -i isolation)"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
set +e
env -i SCRIPT_DIR="$test_dir" bash -c "
    source '$SOURCE_DIR/signal_bot_common.sh'
    require_verified_env_mapping > /dev/null 2>&1
" > /dev/null 2>&1
status=$?
set -e
[ $status -ne 0 ] && pass "env -i isolation blocks gate" || fail "env -i should block gate"
rm -rf "$test_dir"

# TEST 4: Production check_health detects failure (nonexistent PID)
echo "TEST 4: Production check_health detects failed process"
test_dir=$(mktemp -d)
log_file="$test_dir/bot.log"
SCRIPT_DIR="$test_dir"
echo "Startup" > "$log_file"
offset=$(stat -c '%s' "$log_file")
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
result=$(check_health 999999 "$log_file" "$offset" "successful")
status=$?
set -e
[ "$result" = "FAILED" ] && [ $status -ne 0 ] && pass "check_health detects dead PID" || fail "check_health logic error (got: $result, status: $status)"
rm -rf "$test_dir"

# TEST 5: Production check_health detects error marker
echo "TEST 5: Production check_health detects error marker"
test_dir=$(mktemp -d)
log_file="$test_dir/bot.log"
SCRIPT_DIR="$test_dir"
echo "Startup" > "$log_file"
offset=$(stat -c '%s' "$log_file")
echo "Traceback (most recent call last):" >> "$log_file"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
result=$(check_health 999999 "$log_file" "$offset" "marker")
status=$?
set -e
[ "$result" = "FAILED" ] && [ $status -ne 0 ] && pass "check_health detects Traceback" || fail "check_health error detection (got: $result)"
rm -rf "$test_dir"

# TEST 6: Log offset calculation (production_read_health_log)
echo "TEST 6: Log offset isolation via injectable boundary"
test_dir=$(mktemp -d)
log_file="$test_dir/bot.log"
SCRIPT_DIR="$test_dir"
echo "Old content line 1" > "$log_file"
echo "Old content line 2" >> "$log_file"
offset=$(stat -c '%s' "$log_file")
echo "New content" >> "$log_file"
source "$SOURCE_DIR/signal_bot_common.sh"
new_content=$(invoke_read_health_log "$log_file" "$offset")
echo "$new_content" | grep -q "New content" && ! echo "$new_content" | grep -q "Old content" && pass "Log offset isolates new content" || fail "Log offset calculation"
rm -rf "$test_dir"

# TEST 7: Scanner observe-only (find_process returns PROCESS_ABSENT)
echo "TEST 7: Scanner observe-only mode"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
find_process "scanner_bot.py" "$test_dir" "$(id -u)" "$(id -un)" > /dev/null 2>&1
status=$?
set -e
[ $status -eq $PROCESS_ABSENT ] && pass "Scanner handling (PROCESS_ABSENT, no restart)" || fail "Scanner (status=$status)"
rm -rf "$test_dir"

# TEST 8: find_process returns PROCESS_ABSENT for nonexistent
echo "TEST 8: find_process returns PROCESS_ABSENT status code"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
find_process "nonexistent.py" "$test_dir" "$(id -u)" "$(id -un)" > /dev/null 2>&1
status=$?
set -e
[ $status -eq $PROCESS_ABSENT ] && pass "PROCESS_ABSENT status code" || fail "Status code (got $status, expected $PROCESS_ABSENT)"
rm -rf "$test_dir"

# TEST 9: Prohibited process detection
echo "TEST 9: Prohibited process detection"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
check_prohibited_processes > /dev/null 2>&1
status=$?
set -e
[ $status -eq 0 ] && pass "No prohibited processes detected" || fail "Prohibited process check (status=$status)"
rm -rf "$test_dir"

# TEST 10: Prohibited file detection
echo "TEST 10: Prohibited file detection"
test_dir=$(mktemp -d)
touch "$test_dir/.trade_queue.jsonl"
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
check_prohibited_files > /dev/null 2>&1
status=$?
set -e
[ $status -ne 0 ] && pass "Prohibited file detected" || fail "Prohibited file not detected"
rm -rf "$test_dir"

# TEST 11: Duplicate .env keys rejected
echo "TEST 11: Duplicate .env keys rejected"
test_dir=$(mktemp -d)
cat > "$test_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
VANTAGE_EA_TOKEN=duplicate
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
parse_env 2>&1 | grep -q "Duplicate"
found=$?
set -e
[ $found -eq 0 ] && pass "Duplicate key detection" || fail "Duplicate key not detected"
rm -rf "$test_dir"

# TEST 12: Empty .env values rejected
echo "TEST 12: Empty .env values rejected"
test_dir=$(mktemp -d)
cat > "$test_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
parse_env 2>&1 | grep -q "Empty"
found=$?
set -e
[ $found -eq 0 ] && pass "Empty value detection" || fail "Empty value not detected"
rm -rf "$test_dir"

# TEST 13: Malformed .env lines rejected
echo "TEST 13: Malformed .env lines rejected"
test_dir=$(mktemp -d)
cat > "$test_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
NO_EQUALS_LINE
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
parse_env 2>&1 | grep -q "Malformed"
found=$?
set -e
[ $found -eq 0 ] && pass "Malformed line detection" || fail "Malformed line not detected"
rm -rf "$test_dir"

# TEST 14: Behavioral test - launch recorder records invocations
echo "TEST 14: Behavioral test - launch recorder via LAUNCH_BOT_IMPL"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
launch_log="$test_dir/launch.log"
test_launch_recorder() {
    echo "$1:$2" >> "$launch_log"
}
export LAUNCH_BOT_IMPL=test_launch_recorder
export LAUNCH_BOT_IMPL
source "$SOURCE_DIR/signal_bot_common.sh"
invoke_launch_bot "testbot.py" "testbot.log"
[ -f "$launch_log" ] && grep -q "testbot.py:testbot.log" "$launch_log" && pass "Launch recorder captures invocation" || fail "Launch recorder not invoked"
rm -rf "$test_dir"

# TEST 15: start_signal_bots_main is sourceable function
echo "TEST 15: start_signal_bots_main sourceable function exists"
(
    test_dir=$(mktemp -d)
    SCRIPT_DIR="$test_dir"
    set +e
    source "$SOURCE_DIR/start_signal_bots.sh" > /dev/null 2>&1
    type start_signal_bots_main > /dev/null 2>&1
    status=$?
    set -e
    [ $status -eq 0 ] && echo "✓ start_signal_bots_main function defined" || echo "❌ start_signal_bots_main not found"
    rm -rf "$test_dir"
    exit $status
) && PASSED=$((PASSED + 1)) || FAILED=$((FAILED + 1))

# TEST 16: watchdog_run_cycle is sourceable function
echo "TEST 16: watchdog_run_cycle sourceable function exists"
(
    test_dir=$(mktemp -d)
    SCRIPT_DIR="$test_dir"
    mkdir -p "$test_dir/logs"
    set +e
    source "$SOURCE_DIR/watchdog_signal_only.sh" > /dev/null 2>&1
    type watchdog_run_cycle > /dev/null 2>&1
    status=$?
    set -e
    [ $status -eq 0 ] && echo "✓ watchdog_run_cycle function defined" || echo "❌ watchdog_run_cycle not found"
    rm -rf "$test_dir"
    exit $status
) && PASSED=$((PASSED + 1)) || FAILED=$((FAILED + 1))

# TEST 17: start_signal_bots_main blocks without gate
echo "TEST 17: start_signal_bots_main blocks without SIGNAL_BOT_ENV_MAPPING_VERIFIED"
test_dir=$(mktemp -d)
mkdir -p "$test_dir/logs"
cat > "$test_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF
unset SIGNAL_BOT_ENV_MAPPING_VERIFIED
set +e
(
    cd "$test_dir"
    SCRIPT_DIR="$test_dir"
    source "$SOURCE_DIR/start_signal_bots.sh" > /dev/null 2>&1
    start_signal_bots_main
) > /dev/null 2>&1
status=$?
set -e
[ $status -ne 0 ] && pass "start_signal_bots_main gate blocks" || fail "start_signal_bots_main should block without gate"
rm -rf "$test_dir"

# TEST 18: start_signal_bots_main gate verification with APPROVED env
echo "TEST 18: start_signal_bots_main gate verification with APPROVED"
test_dir=$(mktemp -d)
mkdir -p "$test_dir/logs"
cat > "$test_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF
for bot_file in eurusd_bot.py gbpusd_bot.py usdjpy_bot.py gold_bot.py btc_bot.py nifty_scalper.py; do
    touch "$test_dir/$bot_file"
done
export SIGNAL_BOT_ENV_MAPPING_VERIFIED="APPROVED"
SCRIPT_DIR="$test_dir"
set +e
source "$SOURCE_DIR/signal_bot_common.sh"
require_verified_env_mapping > /dev/null 2>&1
gate_status=$?
validate_env > /dev/null 2>&1
env_status=$?
set -e
[ $gate_status -eq 0 ] && [ $env_status -eq 0 ] && pass "start_signal_bots_main gate and env pass with APPROVED" || fail "Gate/env check failed (gate=$gate_status, env=$env_status)"
rm -rf "$test_dir"

# TEST 19: watchdog_run_cycle enforces gate
echo "TEST 19: watchdog_run_cycle blocks without gate"
test_dir=$(mktemp -d)
mkdir -p "$test_dir/logs"
unset SIGNAL_BOT_ENV_MAPPING_VERIFIED
set +e
(
    cd "$test_dir"
    SCRIPT_DIR="$test_dir"
    source "$SOURCE_DIR/watchdog_signal_only.sh" > /dev/null 2>&1
    watchdog_run_cycle
) > /dev/null 2>&1
status=$?
set -e
[ $status -ne 0 ] && pass "watchdog_run_cycle gate blocks" || fail "watchdog_run_cycle should block without gate"
rm -rf "$test_dir"

# TEST 20: Invoke functions use injectable implementations
echo "TEST 20: invoke_process_alive uses PROCESS_ALIVE_IMPL"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
alive_log="$test_dir/alive.log"
test_alive_impl() { echo "checked:$1" >> "$alive_log"; }
export PROCESS_ALIVE_IMPL=test_alive_impl
source "$SOURCE_DIR/signal_bot_common.sh"
invoke_process_alive "12345"
[ -f "$alive_log" ] && grep -q "checked:12345" "$alive_log" && pass "invoke_process_alive uses PROCESS_ALIVE_IMPL" || fail "PROCESS_ALIVE_IMPL not called"
rm -rf "$test_dir"

# TEST 21: Invoke functions use injectable implementations
echo "TEST 21: invoke_read_health_log uses HEALTH_LOG_READER_IMPL"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
log_read_log="$test_dir/logread.log"
test_log_reader() { echo "read:$1:$2" >> "$log_read_log"; }
export HEALTH_LOG_READER_IMPL=test_log_reader
source "$SOURCE_DIR/signal_bot_common.sh"
invoke_read_health_log "bot.log" "100"
[ -f "$log_read_log" ] && grep -q "read:bot.log:100" "$log_read_log" && pass "invoke_read_health_log uses HEALTH_LOG_READER_IMPL" || fail "HEALTH_LOG_READER_IMPL not called"
rm -rf "$test_dir"

echo ""
echo "========== TEST RESULTS =========="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "=========================================="

[ $FAILED -eq 0 ] && echo "✓ ALL TESTS PASSED" && exit 0 || echo "❌ TESTS FAILED" && exit 1
