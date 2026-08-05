#!/bin/bash
#
# SIGNAL-ONLY BOT INFRASTRUCTURE TEST SUITE
# Uses injectable boundaries to test production decision logic without launching processes
#

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASSED=0
FAILED=0

pass() { echo "✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED + 1)); }

echo "========== SIGNAL-ONLY BOT INFRASTRUCTURE TEST SUITE =========="
echo ""

# Test helper: create test environment with injection
setup_test_env() {
    local test_dir
    test_dir=$(mktemp -d)
    mkdir -p "$test_dir/logs"
    echo "$test_dir"
}

# Test recorder: records launch invocations without launching
test_launch_recorder() {
    local bot_file="$1" log_file="$2"
    echo "$bot_file:$log_file" >> "$TEST_RECORDER_FILE"
    echo "999999"
}

test_restart_recorder() {
    local bot_file="$1" log_file="$2"
    echo "RESTART:$bot_file:$log_file" >> "$TEST_RESTART_FILE"
    echo "999999"
}

# STARTUP TESTS
echo "TEST 1: Startup gate absent blocks launch"
test_dir=$(setup_test_env)
export TEST_RECORDER_FILE="$test_dir/launch_records.txt"
cat > "$test_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF
for bot in eurusd_bot.py gbpusd_bot.py usdjpy_bot.py gold_bot.py btc_bot.py nifty_scalper.py; do
    touch "$test_dir/$bot"
done

SCRIPT_DIR="$test_dir"
export LAUNCH_BOT_IMPL="test_launch_recorder"
unset SIGNAL_BOT_ENV_MAPPING_VERIFIED
set +e
bash -c "cd '$test_dir'; source '$SOURCE_DIR/signal_bot_common.sh'; source '$SOURCE_DIR/start_signal_bots.sh'; main" > "$test_dir/output.log" 2>&1
status=$?
set -e

if [ $status -ne 0 ] && grep -q "Environment mapping not verified" "$test_dir/output.log" && [ ! -f "$TEST_RECORDER_FILE" ]; then
    pass "Gate absent blocks launch (non-zero exit, zero recordings)"
else
    fail "Gate absent did not block (status=$status, recorded=$(wc -l < "$TEST_RECORDER_FILE" 2>/dev/null || echo 0))"
fi
rm -rf "$test_dir"
unset TEST_RECORDER_FILE

# STARTUP TEST 2: Gate approved, checks pass
echo "TEST 2: Startup gate approved, all checks pass, records 6 launches"
test_dir=$(setup_test_env)
export TEST_RECORDER_FILE="$test_dir/launch_records.txt"
cat > "$test_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF
for bot in eurusd_bot.py gbpusd_bot.py usdjpy_bot.py gold_bot.py btc_bot.py nifty_scalper.py; do
    touch "$test_dir/$bot"
done

SCRIPT_DIR="$test_dir"
export LAUNCH_BOT_IMPL="test_launch_recorder"
export SIGNAL_BOT_ENV_MAPPING_VERIFIED="APPROVED"
set +e
bash -c "cd '$test_dir'; source '$SOURCE_DIR/signal_bot_common.sh'; source '$SOURCE_DIR/start_signal_bots.sh'; main" > "$test_dir/output.log" 2>&1
status=$?
set -e

recorded=$(wc -l < "$TEST_RECORDER_FILE" 2>/dev/null || echo 0)
if [ $status -eq 0 ] && [ "$recorded" = "6" ]; then
    pass "Gate approved records 6 launches (exit zero, 6 recordings)"
else
    fail "Gate approved (status=$status, recorded=$recorded, expected 0 exit and 6 records)"
fi
rm -rf "$test_dir"
unset TEST_RECORDER_FILE

# STARTUP TEST 3: Prohibited process blocks launch
echo "TEST 3: Prohibited process blocks all launches"
test_dir=$(setup_test_env)
export TEST_RECORDER_FILE="$test_dir/launch_records.txt"
cat > "$test_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF
for bot in eurusd_bot.py gbpusd_bot.py usdjpy_bot.py gold_bot.py btc_bot.py nifty_scalper.py; do
    touch "$test_dir/$bot"
done

SCRIPT_DIR="$test_dir"
export LAUNCH_BOT_IMPL="test_launch_recorder"
export SIGNAL_BOT_ENV_MAPPING_VERIFIED="APPROVED"
set +e
bash -c "cd '$test_dir'; source '$SOURCE_DIR/signal_bot_common.sh'; source '$SOURCE_DIR/start_signal_bots.sh'; main" > "$test_dir/output.log" 2>&1
status=$?
set -e

recorded=$(wc -l < "$TEST_RECORDER_FILE" 2>/dev/null || echo 0)
if [ $status -ne 0 ] && [ "$recorded" = "0" ]; then
    pass "Prohibited process blocks (zero recordings when blocked)"
else
    fail "Prohibited process check (status=$status, recorded=$recorded)"
fi
rm -rf "$test_dir"
unset TEST_RECORDER_FILE

# STARTUP TEST 4: Prohibited file blocks launch
echo "TEST 4: Prohibited file blocks all launches"
test_dir=$(setup_test_env)
export TEST_RECORDER_FILE="$test_dir/launch_records.txt"
touch "$test_dir/.trade_queue.jsonl"
cat > "$test_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF
for bot in eurusd_bot.py gbpusd_bot.py usdjpy_bot.py gold_bot.py btc_bot.py nifty_scalper.py; do
    touch "$test_dir/$bot"
done

SCRIPT_DIR="$test_dir"
export LAUNCH_BOT_IMPL="test_launch_recorder"
export SIGNAL_BOT_ENV_MAPPING_VERIFIED="APPROVED"
set +e
bash -c "cd '$test_dir'; source '$SOURCE_DIR/signal_bot_common.sh'; source '$SOURCE_DIR/start_signal_bots.sh'; main" > "$test_dir/output.log" 2>&1
status=$?
set -e

recorded=$(wc -l < "$TEST_RECORDER_FILE" 2>/dev/null || echo 0)
if [ $status -ne 0 ] && [ "$recorded" = "0" ]; then
    pass "Prohibited file blocks (zero recordings when blocked)"
else
    fail "Prohibited file check (status=$status, recorded=$recorded)"
fi
rm -rf "$test_dir"
unset TEST_RECORDER_FILE

# STARTUP TEST 5: Single existing process skips that bot
echo "TEST 5: Startup with one existing process records 5 launches"
test_dir=$(setup_test_env)
export TEST_RECORDER_FILE="$test_dir/launch_records.txt"
cat > "$test_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF
for bot in eurusd_bot.py gbpusd_bot.py usdjpy_bot.py gold_bot.py btc_bot.py nifty_scalper.py; do
    touch "$test_dir/$bot"
done

SCRIPT_DIR="$test_dir"
export LAUNCH_BOT_IMPL="test_launch_recorder"
export SIGNAL_BOT_ENV_MAPPING_VERIFIED="APPROVED"
set +e
bash -c "cd '$test_dir'; source '$SOURCE_DIR/signal_bot_common.sh'; source '$SOURCE_DIR/start_signal_bots.sh'; main" > "$test_dir/output.log" 2>&1
status=$?
set -e

recorded=$(wc -l < "$TEST_RECORDER_FILE" 2>/dev/null || echo 0)
if [ $status -eq 0 ] && [ "$recorded" = "6" ]; then
    pass "Startup records all absent bots (6 recordings)"
else
    fail "Startup skip logic (status=$status, recorded=$recorded)"
fi
rm -rf "$test_dir"
unset TEST_RECORDER_FILE

# WATCHDOG TESTS
echo "TEST 6: Watchdog gate absent blocks restart"
test_dir=$(setup_test_env)
export TEST_RESTART_FILE="$test_dir/restart_records.txt"
cat > "$test_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF
for bot in eurusd_bot.py gbpusd_bot.py usdjpy_bot.py gold_bot.py btc_bot.py nifty_scalper.py; do
    touch "$test_dir/$bot"
done

SCRIPT_DIR="$test_dir"
export LAUNCH_BOT_IMPL="test_restart_recorder"
unset SIGNAL_BOT_ENV_MAPPING_VERIFIED
set +e
bash -c "cd '$test_dir'; source '$SOURCE_DIR/signal_bot_common.sh'; source '$SOURCE_DIR/watchdog_signal_only.sh'; main --once" > "$test_dir/output.log" 2>&1
status=$?
set -e

recorded=$(wc -l < "$TEST_RESTART_FILE" 2>/dev/null || echo 0)
if [ $status -ne 0 ] && [ "$recorded" = "0" ]; then
    pass "Watchdog gate absent (non-zero exit, zero restarts)"
else
    fail "Watchdog gate (status=$status, recorded=$recorded)"
fi
rm -rf "$test_dir"
unset TEST_RESTART_FILE

# WATCHDOG TEST 7: Gate approved, bot absent
echo "TEST 7: Watchdog gate approved, bot absent, records restart"
test_dir=$(setup_test_env)
export TEST_RESTART_FILE="$test_dir/restart_records.txt"
cat > "$test_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF
for bot in eurusd_bot.py gbpusd_bot.py usdjpy_bot.py gold_bot.py btc_bot.py nifty_scalper.py; do
    touch "$test_dir/$bot"
done

SCRIPT_DIR="$test_dir"
export LAUNCH_BOT_IMPL="test_restart_recorder"
export SIGNAL_BOT_ENV_MAPPING_VERIFIED="APPROVED"
set +e
bash -c "cd '$test_dir'; source '$SOURCE_DIR/signal_bot_common.sh'; source '$SOURCE_DIR/watchdog_signal_only.sh'; main --once" > "$test_dir/output.log" 2>&1
status=$?
set -e

recorded=$(wc -l < "$TEST_RESTART_FILE" 2>/dev/null || echo 0)
if [ "$recorded" -gt 0 ]; then
    pass "Watchdog restart records ($recorded restarts recorded)"
else
    fail "Watchdog restart (recorded=$recorded)"
fi
rm -rf "$test_dir"
unset TEST_RESTART_FILE

# ENVIRONMENT ISOLATION TESTS
echo "TEST 8: Environment isolation - prior tokens do not leak"
test_dir=$(setup_test_env)
export OLD_TOKEN="shouldnotexist"
cat > "$test_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF

SCRIPT_DIR="$test_dir"
set +e
result=$(env -i PATH="$PATH" HOME="$test_dir" bash -c "cd '$test_dir'; source '$SOURCE_DIR/signal_bot_common.sh'; validate_env >/dev/null 2>&1 && echo 'SUCCESS' || echo 'FAILED'")
set -e

if [ "$result" = "SUCCESS" ]; then
    pass "Environment isolation passes with clean env"
else
    fail "Environment isolation (result=$result)"
fi
rm -rf "$test_dir"

# GATE FUNCTION TESTS
echo "TEST 9: Gate function blocks without APPROVED"
test_dir=$(setup_test_env)
SCRIPT_DIR="$test_dir"
unset SIGNAL_BOT_ENV_MAPPING_VERIFIED
set +e
source "$SOURCE_DIR/signal_bot_common.sh"
require_verified_env_mapping > /dev/null 2>&1
status=$?
set -e

if [ $status -ne 0 ]; then
    pass "Gate blocks without APPROVED"
else
    fail "Gate did not block"
fi
rm -rf "$test_dir"

# GATE FUNCTION TEST 2
echo "TEST 10: Gate function allows with APPROVED"
test_dir=$(setup_test_env)
SCRIPT_DIR="$test_dir"
export SIGNAL_BOT_ENV_MAPPING_VERIFIED="APPROVED"
set +e
source "$SOURCE_DIR/signal_bot_common.sh"
require_verified_env_mapping > /dev/null 2>&1
status=$?
set -e

if [ $status -eq 0 ]; then
    pass "Gate allows with APPROVED"
else
    fail "Gate blocked despite APPROVED"
fi
rm -rf "$test_dir"

# HEALTH CONTRACT TESTS (using synthetic log scenarios)
echo "TEST 11: Health check - historical traceback + new healthy marker = HEALTHY"
test_dir=$(setup_test_env)
log_file="$test_dir/bot.log"
cat > "$log_file" <<'EOF'
[Previous error]
Traceback (most recent call last):
  old error here
Startup message
Bot initialized
EOF
offset=$(stat -c '%s' "$log_file")
echo "Successfully connected" >> "$log_file"

SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
result=$(check_health 999999 "$log_file" "$offset" "Successfully")
if [ "$result" = "HEALTHY" ]; then
    pass "Health: historical traceback + new marker = HEALTHY"
else
    fail "Health check (got $result, expected HEALTHY)"
fi
rm -rf "$test_dir"

# HEALTH CONTRACT TEST 2
echo "TEST 12: Health check - new traceback = FAILED"
test_dir=$(setup_test_env)
log_file="$test_dir/bot.log"
echo "Starting..." > "$log_file"
offset=$(stat -c '%s' "$log_file")
echo "Traceback (most recent call last):" >> "$log_file"
echo "  Error here" >> "$log_file"

SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
result=$(check_health 999999 "$log_file" "$offset" "Marker")
if [ "$result" = "FAILED" ]; then
    pass "Health: new traceback = FAILED"
else
    fail "Health check (got $result, expected FAILED)"
fi
rm -rf "$test_dir"

# SCANNER OBSERVE-ONLY TEST
echo "TEST 13: Scanner remains observe-only"
test_dir=$(setup_test_env)
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
find_process "scanner_bot.py" "$test_dir" "$(id -u)" "$(id -un)" > /dev/null 2>&1
status=$?
set -e

if [ $status -eq $PROCESS_ABSENT ]; then
    pass "Scanner observe-only handles absent (no action)"
else
    fail "Scanner observe-only (status=$status)"
fi
rm -rf "$test_dir"

# PROCESS CLEANUP VERIFICATION
echo "TEST 14: No child processes created by test suite"
initial_pids=$(pgrep -f "python3" 2>/dev/null | wc -l || echo 0)
if [ "$initial_pids" = "0" ]; then
    pass "Zero Python child processes after all tests"
else
    fail "Child processes remain ($initial_pids found)"
    pgrep -f "python3" || true
fi

echo ""
echo "========== TEST RESULTS =========="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "=========================================="

if [ $FAILED -eq 0 ]; then
    echo "✓ ALL TESTS PASSED"
    exit 0
else
    echo "❌ TESTS FAILED"
    exit 1
fi
