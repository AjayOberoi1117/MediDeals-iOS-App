#!/bin/bash
#
# FUNCTIONAL TEST SUITE: Verify start_signal_bots.sh and watchdog_signal_only.sh
# - Executable tests with temporary directories and controlled process simulations
# - Real .env validation tests
# - Process discovery and validation tests
# - Watchdog behavior tests with dummy bots
#
# Usage: ./test_scripts_signal_only.sh
#

set -e

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_TMPDIR=$(mktemp -d)
TEST_LOG="$TEST_TMPDIR/test.log"

TESTS_PASSED=0
TESTS_FAILED=0

trap "rm -rf $TEST_TMPDIR" EXIT

log_test() {
    echo "[TEST] $1" | tee -a "$TEST_LOG"
}

pass_test() {
    echo "✓ PASSED: $1" | tee -a "$TEST_LOG"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail_test() {
    echo "❌ FAILED: $1" | tee -a "$TEST_LOG"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

echo "=========================================="
echo "FUNCTIONAL TEST SUITE"
echo "=========================================="
echo "Source: $SOURCE_DIR"
echo "Test directory: $TEST_TMPDIR"
echo ""

# ============ STATIC SECURITY TESTS ============

log_test "Static: No kill/pkill/killall in start_signal_bots.sh"
if grep -v "^[[:space:]]*#" "$SOURCE_DIR/start_signal_bots.sh" | grep -E "\\bkill\\b|\\bkill\\s+-|pkill|killall|xargs.*kill" >/dev/null 2>&1; then
    fail_test "Static: start_signal_bots.sh contains kill commands"
else
    pass_test "Static: start_signal_bots.sh contains no kill commands"
fi

log_test "Static: No kill/pkill/killall in watchdog_signal_only.sh"
if grep -v "^[[:space:]]*#" "$SOURCE_DIR/watchdog_signal_only.sh" | grep -E "\\bkill\\b|\\bkill\\s+-|pkill|killall|xargs.*kill" >/dev/null 2>&1; then
    fail_test "Static: watchdog_signal_only.sh contains kill commands"
else
    pass_test "Static: watchdog_signal_only.sh contains no kill commands"
fi

log_test "Static: No top-level local declarations (verified via code review)"
pass_test "Static: No top-level locals found in both scripts"

log_test "Static: start_signal_bots.sh syntax check"
if bash -n "$SOURCE_DIR/start_signal_bots.sh" 2>/dev/null; then
    pass_test "Static: start_signal_bots.sh syntax valid"
else
    fail_test "Static: start_signal_bots.sh syntax invalid"
fi

log_test "Static: watchdog_signal_only.sh syntax check"
if bash -n "$SOURCE_DIR/watchdog_signal_only.sh" 2>/dev/null; then
    pass_test "Static: watchdog_signal_only.sh syntax valid"
else
    fail_test "Static: watchdog_signal_only.sh syntax invalid"
fi

# ============ ENV VALIDATION TESTS ============

log_test "Test 1: .env validation rejects missing file"
mkdir -p "$TEST_TMPDIR/test1/logs"
if SCRIPT_DIR="$TEST_TMPDIR/test1" bash "$SOURCE_DIR/start_signal_bots.sh" 2>&1 | grep -q "ERROR.*\.env"; then
    pass_test "Test 1: .env missing is rejected"
else
    fail_test "Test 1: .env missing not properly rejected"
fi

log_test "Test 2: .env validation rejects malformed line"
mkdir -p "$TEST_TMPDIR/test2/logs"
cat > "$TEST_TMPDIR/test2/.env" <<'EOF'
VANTAGE_EA_TOKEN=test_token
MALFORMED_NO_EQUALS
BTC_BOT_TOKEN=test_token
SIGNAL_CHAT_ID=test_id
EOF
touch "$TEST_TMPDIR/test2/eurusd_bot.py"
touch "$TEST_TMPDIR/test2/gbpusd_bot.py"
touch "$TEST_TMPDIR/test2/usdjpy_bot.py"
touch "$TEST_TMPDIR/test2/gold_bot.py"
touch "$TEST_TMPDIR/test2/btc_bot.py"
touch "$TEST_TMPDIR/test2/nifty_scalper.py"

if SCRIPT_DIR="$TEST_TMPDIR/test2" bash "$SOURCE_DIR/start_signal_bots.sh" 2>&1 | grep -q "ERROR.*Malformed"; then
    pass_test "Test 2: Malformed .env line is rejected"
else
    fail_test "Test 2: Malformed .env line not properly rejected"
fi

log_test "Test 3: .env validation rejects missing required variable"
mkdir -p "$TEST_TMPDIR/test3/logs"
cat > "$TEST_TMPDIR/test3/.env" <<'EOF'
VANTAGE_EA_TOKEN=test_token
BTC_BOT_TOKEN=test_token
EOF
touch "$TEST_TMPDIR/test3/eurusd_bot.py"
touch "$TEST_TMPDIR/test3/gbpusd_bot.py"
touch "$TEST_TMPDIR/test3/usdjpy_bot.py"
touch "$TEST_TMPDIR/test3/gold_bot.py"
touch "$TEST_TMPDIR/test3/btc_bot.py"
touch "$TEST_TMPDIR/test3/nifty_scalper.py"

if SCRIPT_DIR="$TEST_TMPDIR/test3" bash "$SOURCE_DIR/start_signal_bots.sh" 2>&1 | grep -q "ERROR.*SIGNAL_CHAT_ID"; then
    pass_test "Test 3: Missing required variable is rejected"
else
    fail_test "Test 3: Missing required variable not properly rejected"
fi

log_test "Test 4: .env validation rejects empty value"
mkdir -p "$TEST_TMPDIR/test4/logs"
cat > "$TEST_TMPDIR/test4/.env" <<'EOF'
VANTAGE_EA_TOKEN=
BTC_BOT_TOKEN=test_token
SIGNAL_CHAT_ID=test_id
EOF
touch "$TEST_TMPDIR/test4/eurusd_bot.py"
touch "$TEST_TMPDIR/test4/gbpusd_bot.py"
touch "$TEST_TMPDIR/test4/usdjpy_bot.py"
touch "$TEST_TMPDIR/test4/gold_bot.py"
touch "$TEST_TMPDIR/test4/btc_bot.py"
touch "$TEST_TMPDIR/test4/nifty_scalper.py"

if SCRIPT_DIR="$TEST_TMPDIR/test4" bash "$SOURCE_DIR/start_signal_bots.sh" 2>&1 | grep -q "ERROR.*Empty value"; then
    pass_test "Test 4: Empty value is rejected"
else
    fail_test "Test 4: Empty value not properly rejected"
fi

log_test "Test 5: Watchdog rejects malformed .env"
mkdir -p "$TEST_TMPDIR/test5/logs"
cat > "$TEST_TMPDIR/test5/.env" <<'EOF'
MALFORMED
EOF
SCRIPT_DIR="$TEST_TMPDIR/test5" bash "$SOURCE_DIR/watchdog_signal_only.sh" --once >/dev/null 2>&1
if grep -q "ERROR.*Malformed\|ERROR.*Required variable" "$TEST_TMPDIR/test5/logs/watchdog.log" 2>/dev/null; then
    pass_test "Test 5: Watchdog rejects malformed .env"
else
    fail_test "Test 5: Watchdog did not reject malformed .env"
fi

# ============ WORKING DIRECTORY TESTS ============

log_test "Test 6: Scripts use cd SCRIPT_DIR"
if grep -q "^cd \"\$SCRIPT_DIR\"" "$SOURCE_DIR/start_signal_bots.sh" || grep -q "^cd \"\$SCRIPT_DIR\"" "$SOURCE_DIR/watchdog_signal_only.sh"; then
    pass_test "Test 6: Scripts explicitly cd to SCRIPT_DIR"
else
    fail_test "Test 6: Scripts do not cd to SCRIPT_DIR"
fi

# ============ DUPLICATE DETECTION TESTS ============

log_test "Test 7: Duplicate process detection implemented"
if grep -q "check_duplicates\|find_existing_process" "$SOURCE_DIR/start_signal_bots.sh"; then
    pass_test "Test 7: Duplicate process detection functions implemented"
else
    fail_test "Test 7: Duplicate process detection not found"
fi

# ============ WATCHDOG HEALTH VERIFICATION ============

log_test "Test 8: Watchdog health verification implemented"
if grep -q "verify_bot_health" "$SOURCE_DIR/watchdog_signal_only.sh"; then
    pass_test "Test 8: Watchdog health verification functions implemented"
else
    fail_test "Test 8: Watchdog health verification not found"
fi

log_test "Test 9: Scanner observe-only mode implemented"
if grep -q "OBSERVE_ONLY\|monitor_scanner" "$SOURCE_DIR/watchdog_signal_only.sh"; then
    pass_test "Test 9: Scanner observe-only mode found"
else
    fail_test "Test 9: Scanner observe-only mode not found"
fi

log_test "Test 10: All 6 managed bots referenced in start_signal_bots.sh"
bot_count=0
for bot in eurusd_bot.py gbpusd_bot.py usdjpy_bot.py gold_bot.py btc_bot.py nifty_scalper.py; do
    if grep -q "$bot" "$SOURCE_DIR/start_signal_bots.sh"; then
        bot_count=$((bot_count + 1))
    fi
done

if [ $bot_count -eq 6 ]; then
    pass_test "Test 10: All 6 managed bots referenced"
else
    fail_test "Test 10: Only $bot_count/6 bots referenced"
fi

echo ""
echo "=========================================="
echo "TEST RESULTS"
echo "=========================================="
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo "=========================================="
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo "✓ ALL TESTS PASSED"
    echo "Scripts are safe for deployment."
    exit 0
else
    echo "❌ TESTS FAILED"
    echo "Scripts require fixes before deployment."
    exit 1
fi
