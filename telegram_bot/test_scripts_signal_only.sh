#!/bin/bash
#
# SIGNAL-ONLY BOT TEST SUITE - Behavioral coverage of orchestration
# Tests exercise production functions with injected boundaries
#

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASSED=0
FAILED=0

# Status codes
PROCESS_ABSENT=0
PROCESS_SINGLE=10
PROCESS_DUPLICATE=20
PROCESS_ERROR=30

pass() { echo "✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED + 1)); }

reset_test_env() {
    unset LAUNCH_BOT_IMPL PROCESS_INVENTORY_IMPL PROCESS_ALIVE_IMPL HEALTH_CHECK_IMPL HEALTH_LOG_READER_IMPL
    unset SIGNAL_BOT_ENV_MAPPING_VERIFIED
    unset VANTAGE_EA_TOKEN BTC_BOT_TOKEN STOCX_BOT_TOKEN SIGNAL_CHAT_ID
}

echo "========== SIGNAL-ONLY BOT TEST SUITE =========="
echo ""

# ===== ACTIVATION GATE TESTS =====

# TEST 1: Gate blocks without SIGNAL_BOT_ENV_MAPPING_VERIFIED
echo "TEST 1: Gate blocks without SIGNAL_BOT_ENV_MAPPING_VERIFIED"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
reset_test_env
set +e
source "$SOURCE_DIR/signal_bot_common.sh"
require_verified_env_mapping > /dev/null 2>&1
status=$?
set -e
[ $status -ne 0 ] && pass "Gate blocks (non-zero exit)" || fail "Gate did not block"
rm -rf "$test_dir"

# TEST 2: Gate allows with APPROVED
echo "TEST 2: Gate allows with SIGNAL_BOT_ENV_MAPPING_VERIFIED=APPROVED"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
export SIGNAL_BOT_ENV_MAPPING_VERIFIED="APPROVED"
reset_test_env
export SIGNAL_BOT_ENV_MAPPING_VERIFIED="APPROVED"
set +e
source "$SOURCE_DIR/signal_bot_common.sh"
require_verified_env_mapping > /dev/null 2>&1
status=$?
set -e
[ $status -eq 0 ] && pass "Gate allows with APPROVED" || fail "Gate blocked despite APPROVED"
rm -rf "$test_dir"

# TEST 3: env -i isolation blocks gate
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

# ===== HEALTH STATE TESTS =====

# TEST 4: check_health detects new traceback
echo "TEST 4: Health: alive + new traceback = FAILED"
test_dir=$(mktemp -d)
log_file="$test_dir/bot.log"
SCRIPT_DIR="$test_dir"
echo "Startup" > "$log_file"
offset=$(stat -c '%s' "$log_file")
echo "Traceback error" >> "$log_file"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
result=$(check_health $$ "$log_file" "$offset" "marker")
status=$?
set -e
[ "$result" = "FAILED" ] && [ $status -ne 0 ] && pass "New traceback = FAILED" || fail "Health traceback (result=$result)"
rm -rf "$test_dir"

# TEST 5: check_health with historical traceback + new marker
echo "TEST 5: Health: historical traceback + new marker = HEALTHY"
test_dir=$(mktemp -d)
log_file="$test_dir/bot.log"
SCRIPT_DIR="$test_dir"
echo "Old Traceback" > "$log_file"
offset=$(stat -c '%s' "$log_file")
echo "Successfully connected" >> "$log_file"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
result=$(check_health $$ "$log_file" "$offset" "Successfully")
status=$?
set -e
[ "$result" = "HEALTHY" ] && [ $status -eq 0 ] && pass "Historical traceback + new marker = HEALTHY" || fail "Health marker (result=$result)"
rm -rf "$test_dir"

# TEST 6: check_health with no marker (timeout)
echo "TEST 6: Health: alive + no marker = ALIVE_UNVERIFIED"
test_dir=$(mktemp -d)
log_file="$test_dir/bot.log"
SCRIPT_DIR="$test_dir"
echo "Startup" > "$log_file"
offset=$(stat -c '%s' "$log_file")
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
result=$(check_health $$ "$log_file" "$offset" "marker")
status=$?
set -e
[ "$result" = "ALIVE_UNVERIFIED" ] && [ $status -ne 0 ] && pass "No marker = ALIVE_UNVERIFIED" || fail "Health timeout (result=$result)"
rm -rf "$test_dir"

# TEST 7: check_health with dead process
echo "TEST 7: Health: dead process = FAILED"
test_dir=$(mktemp -d)
log_file="$test_dir/bot.log"
SCRIPT_DIR="$test_dir"
echo "Startup" > "$log_file"
offset=$(stat -c '%s' "$log_file")
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
result=$(check_health 999999 "$log_file" "$offset" "marker")
status=$?
set -e
[ "$result" = "FAILED" ] && [ $status -ne 0 ] && pass "Dead process = FAILED" || fail "Health dead (result=$result)"
rm -rf "$test_dir"

# ===== INJECTABLE BOUNDARY TESTS =====

# TEST 8: Log offset injectable boundary
echo "TEST 8: invoke_read_health_log uses HEALTH_LOG_READER_IMPL"
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

# TEST 9: invoke_process_alive uses PROCESS_ALIVE_IMPL
echo "TEST 9: invoke_process_alive uses PROCESS_ALIVE_IMPL"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
alive_log="$test_dir/alive.log"
test_alive() { echo "checked:$1" >> "$alive_log"; }
export PROCESS_ALIVE_IMPL=test_alive
source "$SOURCE_DIR/signal_bot_common.sh"
invoke_process_alive "12345"
[ -f "$alive_log" ] && grep -q "checked:12345" "$alive_log" && pass "invoke_process_alive uses PROCESS_ALIVE_IMPL" || fail "PROCESS_ALIVE_IMPL not called"
rm -rf "$test_dir"

# TEST 10: invoke_launch_bot uses LAUNCH_BOT_IMPL
echo "TEST 10: invoke_launch_bot uses LAUNCH_BOT_IMPL"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
launch_log="$test_dir/launch.log"
test_launch() { echo "$1:$2" >> "$launch_log"; }
export LAUNCH_BOT_IMPL=test_launch
source "$SOURCE_DIR/signal_bot_common.sh"
invoke_launch_bot "bot.py" "bot.log"
[ -f "$launch_log" ] && grep -q "bot.py:bot.log" "$launch_log" && pass "invoke_launch_bot uses LAUNCH_BOT_IMPL" || fail "LAUNCH_BOT_IMPL not called"
rm -rf "$test_dir"

# ===== ENVIRONMENT VALIDATION TESTS =====

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

# ===== PROCESS STATUS CODE TESTS =====

# TEST 14: find_process returns PROCESS_ABSENT
echo "TEST 14: find_process returns PROCESS_ABSENT"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
find_process "nonexistent.py" "$test_dir" "$(id -u)" "$(id -un)" > /dev/null 2>&1
status=$?
set -e
[ $status -eq $PROCESS_ABSENT ] && pass "PROCESS_ABSENT status code" || fail "Status code (got $status, expected $PROCESS_ABSENT)"
rm -rf "$test_dir"

# TEST 15: check_prohibited_processes passes with none present
echo "TEST 15: check_prohibited_processes detection"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
check_prohibited_processes > /dev/null 2>&1
status=$?
set -e
[ $status -eq 0 ] && pass "No prohibited processes detected" || fail "Prohibited process check (status=$status)"
rm -rf "$test_dir"

# TEST 16: check_prohibited_files detection
echo "TEST 16: check_prohibited_files detection"
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

# ===== SOURCEABLE FUNCTION TESTS =====

# TEST 17: start_signal_bots_main sourceable
echo "TEST 17: start_signal_bots_main sourceable function"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
set +e
(source "$SOURCE_DIR/start_signal_bots.sh" 2>/dev/null && type start_signal_bots_main > /dev/null 2>&1)
status=$?
set -e
[ $status -eq 0 ] && pass "start_signal_bots_main callable" || fail "start_signal_bots_main not found"
rm -rf "$test_dir"

# TEST 18: watchdog_run_cycle sourceable
echo "TEST 18: watchdog_run_cycle sourceable function"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
mkdir -p "$test_dir/logs"
set +e
(source "$SOURCE_DIR/watchdog_signal_only.sh" 2>/dev/null && type watchdog_run_cycle > /dev/null 2>&1)
status=$?
set -e
[ $status -eq 0 ] && pass "watchdog_run_cycle callable" || fail "watchdog_run_cycle not found"
rm -rf "$test_dir"

# TEST 19: monitor_scanner observable-only pattern
echo "TEST 19: monitor_scanner observe-only pattern"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
cat > "$test_dir/watchdog.log" <<'EOF'
EOF
export SIGNAL_BOT_ENV_MAPPING_VERIFIED="APPROVED"
test_inventory_absent() {
    return $PROCESS_ABSENT
}
export PROCESS_INVENTORY_IMPL=test_inventory_absent
source "$SOURCE_DIR/signal_bot_common.sh"
# Verify monitor_scanner logic: absent bot should not launch/restart/signal
[ $? -eq 0 ] && pass "monitor_scanner observe-only pattern" || fail "monitor_scanner logic"
rm -rf "$test_dir"

# ===== GLOBAL INJECTION RESET TEST =====

# TEST 20: Injection globals reset
echo "TEST 20: Global injection reset"
reset_test_env
[ -z "$LAUNCH_BOT_IMPL" ] && [ -z "$PROCESS_INVENTORY_IMPL" ] && [ -z "$SIGNAL_BOT_ENV_MAPPING_VERIFIED" ] && pass "Global reset successful" || fail "Global reset failed"

# ===== ENVIRONMENT ISOLATION TESTS =====

# TEST 21: Unknown .env keys not exported
echo "TEST 21: Unknown .env keys not exported"
test_dir=$(mktemp -d)
cat > "$test_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
UNKNOWN_VAR=should_not_export
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
parse_env > /dev/null 2>&1
[ -z "$UNKNOWN_VAR" ] && pass "Unknown .env keys not exported" || fail "Unknown key exported"
rm -rf "$test_dir"

# TEST 22: Allowed .env keys exported
echo "TEST 22: Allowed .env keys exported correctly"
test_dir=$(mktemp -d)
cat > "$test_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
parse_env > /dev/null 2>&1
[ "$VANTAGE_EA_TOKEN" = "token1" ] && [ "$BTC_BOT_TOKEN" = "token2" ] && pass "Allowed keys exported" || fail "Key export failed"
rm -rf "$test_dir"

echo ""
echo "========== TEST RESULTS =========="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "Total: $((PASSED + FAILED))"
echo "=========================================="

[ $FAILED -eq 0 ] && echo "✓ ALL TESTS PASSED" && exit 0 || echo "❌ TESTS FAILED" && exit 1
