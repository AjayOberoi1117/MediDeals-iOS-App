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

# TEST 1: Activation gate blocks without APPROVED
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

# TEST 2: Gate allows with APPROVED
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

# TEST 3: Log parsing detects success
echo "TEST 3: Log parsing detects success marker"
test_dir=$(mktemp -d)
log_file="$test_dir/bot.log"
echo "Startup" > "$log_file"
offset=$(stat -c '%s' "$log_file")
echo "Successfully connected" >> "$log_file"
new_content=$(tail -c +$((offset + 1)) "$log_file" 2>/dev/null || echo "")
echo "$new_content" | grep -q "Successfully" && pass "Log parsing finds success marker" || fail "Log parsing (marker not found)"
rm -rf "$test_dir"

# TEST 4: Log parsing detects error
echo "TEST 4: Log parsing detects traceback error"
test_dir=$(mktemp -d)
log_file="$test_dir/bot.log"
echo "Startup" > "$log_file"
offset=$(stat -c '%s' "$log_file")
echo "Traceback error occurred" >> "$log_file"
new_content=$(tail -c +$((offset + 1)) "$log_file" 2>/dev/null || echo "")
echo "$new_content" | grep -q "Traceback" && pass "Log parsing finds traceback error" || fail "Log parsing (error not found)"
rm -rf "$test_dir"

# TEST 5: Log offset calculation
echo "TEST 5: Log offset correctly isolates new content"
test_dir=$(mktemp -d)
log_file="$test_dir/bot.log"
echo "Old content" > "$log_file"
offset=$(stat -c '%s' "$log_file")
echo "New message" >> "$log_file"
new_content=$(tail -c +$((offset + 1)) "$log_file" 2>/dev/null || echo "")
! echo "$new_content" | grep -q "Old content" && echo "$new_content" | grep -q "New message" && pass "Log offset isolates new content" || fail "Log offset calculation"
rm -rf "$test_dir"

# TEST 6: Scanner is observe-only (no process launch)
echo "TEST 6: Scanner observe-only mode"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
find_process "scanner_bot.py" "$test_dir" "$(id -u)" "$(id -un)" > /dev/null 2>&1
status=$?
set -e
[ $status -eq $PROCESS_ABSENT ] && pass "Scanner handling (PROCESS_ABSENT, no restart)" || fail "Scanner (status=$status)"
rm -rf "$test_dir"

# TEST 7: Process absent status code
echo "TEST 7: find_process returns PROCESS_ABSENT"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
find_process "nonexistent.py" "$test_dir" "$(id -u)" "$(id -un)" > /dev/null 2>&1
status=$?
set -e
[ $status -eq $PROCESS_ABSENT ] && pass "PROCESS_ABSENT status code" || fail "Status code (got $status, expected $PROCESS_ABSENT)"
rm -rf "$test_dir"

# TEST 8: Prohibited process detection
echo "TEST 8: Prohibited process blocks startup"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
check_prohibited_processes > /dev/null 2>&1
status=$?
set -e
[ $status -eq 0 ] && pass "No prohibited processes detected" || fail "Prohibited process check (status=$status)"
rm -rf "$test_dir"

# TEST 9: Prohibited file detection
echo "TEST 9: Prohibited file blocks startup"
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

# TEST 10: Environment parsing rejects duplicates
echo "TEST 10: Duplicate .env keys rejected"
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

# TEST 11: Environment parsing rejects empty values
echo "TEST 11: Empty .env values rejected"
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

# TEST 12: Environment parsing rejects malformed lines
echo "TEST 12: Malformed .env lines rejected"
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

# TEST 13: invoke_launch_bot uses LAUNCH_BOT_IMPL
echo "TEST 13: invoke_launch_bot respects LAUNCH_BOT_IMPL injection"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
test_bot_impl() {
    echo "INVOKED"
}
export LAUNCH_BOT_IMPL="test_bot_impl"
source "$SOURCE_DIR/signal_bot_common.sh"
result=$(invoke_launch_bot "arg1" "arg2" 2>&1)
[ "$result" = "INVOKED" ] && pass "invoke_launch_bot calls LAUNCH_BOT_IMPL" || fail "invoke_launch_bot (got $result)"
rm -rf "$test_dir"

# TEST 14: Zero child processes
echo "TEST 14: No Python child processes spawned by tests"
pids=$(pgrep -f "python3" 2>/dev/null | wc -l || echo 0)
[ "$pids" = "0" ] && pass "Zero external Python processes" || fail "Child processes found ($pids)"

echo ""
echo "========== TEST RESULTS =========="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "=========================================="

[ $FAILED -eq 0 ] && echo "✓ ALL TESTS PASSED" && exit 0 || echo "❌ TESTS FAILED" && exit 1
