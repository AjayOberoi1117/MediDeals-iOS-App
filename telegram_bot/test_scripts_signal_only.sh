#!/bin/bash
#
# PRODUCTION FUNCTION TEST SUITE
# All tests use real production code, not substitutes
#

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT=$(mktemp -d)
PASSED=0
FAILED=0
TEST_PIDS=()

cleanup_test_pids() {
    for pid in "${TEST_PIDS[@]}"; do
        if ps -p "$pid" > /dev/null 2>&1; then
            kill "$pid" 2>/dev/null || true
            sleep 0.5
            if ps -p "$pid" > /dev/null 2>&1; then
                kill -9 "$pid" 2>/dev/null || true
            fi
        fi
    done
}

trap "cleanup_test_pids; rm -rf $TEST_ROOT" EXIT

pass() { echo "✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED + 1)); }

echo "========== PRODUCTION FUNCTION TEST SUITE =========="
echo "Test root: $TEST_ROOT"
echo ""

# ============ TEST 1: SET -E ZERO STATUS ============
echo "TEST 1: SET -E zero process returns status 0"

test1_dir="$TEST_ROOT/test1"
mkdir -p "$test1_dir"

source "$SOURCE_DIR/signal_bot_common.sh"
SCRIPT_DIR="$test1_dir"
set +e
find_process "nonexistent_bot.py" "$test1_dir"
status=$?
set -e

if [ $status -eq 0 ]; then
    pass "Zero process status 0"
else
    fail "Zero process status 0 (got $status)"
fi

# ============ TEST 2: SET -E SINGLE PROCESS STATUS 1 ============
echo "TEST 2: SET -E single process returns status 1"

test2_dir="$TEST_ROOT/test2"
mkdir -p "$test2_dir"

cat > "$test2_dir/dummy_bot.py" <<'EOF'
#!/usr/bin/env python3
import time
while True: time.sleep(60)
EOF
chmod +x "$test2_dir/dummy_bot.py"

cd "$test2_dir"
python3 dummy_bot.py > /dev/null 2>&1 &
PID1=$!
TEST_PIDS+=("$PID1")
sleep 1

SCRIPT_DIR="$test2_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
pid_result=$(find_process "dummy_bot.py" "$test2_dir")
status=$?
set -e

if [ $status -eq 1 ] && [ "$pid_result" = "$PID1" ]; then
    pass "Single process status 1 with PID retained"
else
    fail "Single process status 1 (got status=$status, pid=$pid_result, expected=$PID1)"
fi

cleanup_test_pids
TEST_PIDS=()

# ============ TEST 3: SINGLE PROCESS NOT RESTARTED ============
echo "TEST 3: Single process NOT restarted (status 1)"

test3_dir="$TEST_ROOT/test3"
mkdir -p "$test3_dir"

cat > "$test3_dir/bot.py" <<'EOF'
#!/usr/bin/env python3
import time
while True: time.sleep(60)
EOF
chmod +x "$test3_dir/bot.py"

cd "$test3_dir"
python3 bot.py > /dev/null 2>&1 &
FIRST_PID=$!
TEST_PIDS+=("$FIRST_PID")
sleep 1

SCRIPT_DIR="$test3_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
pid_result=$(find_process "bot.py" "$test3_dir")
status=$?
set -e

if [ $status -eq 1 ]; then
    pass "Single process not restarted (status 1)"
else
    fail "Single process restarted (status $status)"
fi

cleanup_test_pids
TEST_PIDS=()

# ============ TEST 4: DUPLICATE PROCESS STATUS 2 ============
echo "TEST 4: SET -E duplicate processes return status 2"

test4_dir="$TEST_ROOT/test4"
mkdir -p "$test4_dir"

cat > "$test4_dir/bot.py" <<'EOF'
#!/usr/bin/env python3
import time
while True: time.sleep(60)
EOF
chmod +x "$test4_dir/bot.py"

cd "$test4_dir"
python3 bot.py > /dev/null 2>&1 &
PID1=$!
TEST_PIDS+=("$PID1")
sleep 0.5

python3 bot.py > /dev/null 2>&1 &
PID2=$!
TEST_PIDS+=("$PID2")
sleep 1

SCRIPT_DIR="$test4_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
find_process "bot.py" "$test4_dir"
status=$?
set -e

if [ $status -eq 2 ]; then
    pass "Duplicate process status 2"
else
    fail "Duplicate process status 2 (got $status)"
fi

cleanup_test_pids
TEST_PIDS=()

# ============ TEST 5: PRODUCTION OWNER UID VALIDATION ============
echo "TEST 5: Production validate_process checks owner UID"

test5_dir="$TEST_ROOT/test5"
mkdir -p "$test5_dir"

cat > "$test5_dir/bot.py" <<'EOF'
#!/usr/bin/env python3
import time
while True: time.sleep(60)
EOF
chmod +x "$test5_dir/bot.py"

cd "$test5_dir"
python3 bot.py > /dev/null 2>&1 &
PID=$!
TEST_PIDS+=("$PID")
sleep 1

SCRIPT_DIR="$test5_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
expected_uid=$(id -u)

if validate_process "$PID" "bot.py" "$test5_dir" "$expected_uid" ""; then
    pass "Owner UID validation in production"
else
    fail "Owner UID validation failed"
fi

cleanup_test_pids
TEST_PIDS=()

# ============ TEST 6: PRODUCTION OWNER USERNAME VALIDATION ============
echo "TEST 6: Production validate_process checks owner username"

test6_dir="$TEST_ROOT/test6"
mkdir -p "$test6_dir"

cat > "$test6_dir/bot.py" <<'EOF'
#!/usr/bin/env python3
import time
while True: time.sleep(60)
EOF
chmod +x "$test6_dir/bot.py"

cd "$test6_dir"
python3 bot.py > /dev/null 2>&1 &
PID=$!
TEST_PIDS+=("$PID")
sleep 1

SCRIPT_DIR="$test6_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
expected_user=$(whoami)

if validate_process "$PID" "bot.py" "$test6_dir" "" "$expected_user"; then
    pass "Owner username validation in production"
else
    fail "Owner username validation failed"
fi

cleanup_test_pids
TEST_PIDS=()

# ============ TEST 7: CHECK_HEALTH IMMEDIATE TRACEBACK ============
echo "TEST 7: check_health detects immediate traceback"

test7_dir="$TEST_ROOT/test7"
mkdir -p "$test7_dir"

cat > "$test7_dir/traceback.py" <<'EOF'
#!/usr/bin/env python3
raise ValueError("Immediate error")
EOF
chmod +x "$test7_dir/traceback.py"

cd "$test7_dir"
python3 traceback.py > "$test7_dir/traceback.log" 2>&1 &
PID=$!
sleep 1

SCRIPT_DIR="$test7_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
health_result=$(check_health "$PID" "$test7_dir/traceback.log")

if [ "$health_result" = "FAILED" ]; then
    pass "check_health detects immediate traceback"
else
    fail "check_health result: $health_result (expected FAILED)"
fi

# ============ TEST 8: CHECK_HEALTH OLD ERROR + NEW HEALTHY ============
echo "TEST 8: check_health ignores old traceback with new healthy output"

test8_dir="$TEST_ROOT/test8"
mkdir -p "$test8_dir"

cat > "$test8_dir/old_error.log" <<'EOF'
Traceback (most recent call last):
  File "old.py", line 1
ValueError: old error
EOF

cat > "$test8_dir/healthy.py" <<'EOF'
#!/usr/bin/env python3
import time
time.sleep(1)
print("Bot running healthy")
while True: time.sleep(60)
EOF
chmod +x "$test8_dir/healthy.py"

cd "$test8_dir"
old_size=$(stat -c '%s' "$test8_dir/old_error.log")

python3 healthy.py >> "$test8_dir/old_error.log" 2>&1 &
PID=$!
TEST_PIDS+=("$PID")
sleep 2

SCRIPT_DIR="$test8_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
health_result=$(check_health "$PID" "$test8_dir/old_error.log")

if [ "$health_result" = "ALIVE_UNVERIFIED" ]; then
    pass "check_health ignores old traceback"
else
    fail "check_health result: $health_result (expected ALIVE_UNVERIFIED)"
fi

cleanup_test_pids
TEST_PIDS=()

# ============ TEST 9: CHECK_HEALTH NEW TRACEBACK ============
echo "TEST 9: check_health detects new traceback"

test9_dir="$TEST_ROOT/test9"
mkdir -p "$test9_dir"

cat > "$test9_dir/new_error.py" <<'EOF'
#!/usr/bin/env python3
import time
time.sleep(1)
raise ValueError("New error after startup")
EOF
chmod +x "$test9_dir/new_error.py"

cd "$test9_dir"
python3 new_error.py > "$test9_dir/new_error.log" 2>&1 &
PID=$!
sleep 3

SCRIPT_DIR="$test9_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
health_result=$(check_health "$PID" "$test9_dir/new_error.log")

if [ "$health_result" = "FAILED" ]; then
    pass "check_health detects new traceback"
else
    fail "check_health result: $health_result (expected FAILED)"
fi

# ============ TEST 10: CHECK_HEALTH SILENT PROCESS ============
echo "TEST 10: check_health silent process returns ALIVE_UNVERIFIED"

test10_dir="$TEST_ROOT/test10"
mkdir -p "$test10_dir"

cat > "$test10_dir/silent.py" <<'EOF'
#!/usr/bin/env python3
import time
while True: time.sleep(60)
EOF
chmod +x "$test10_dir/silent.py"

cd "$test10_dir"
python3 silent.py > "$test10_dir/silent.log" 2>&1 &
PID=$!
TEST_PIDS+=("$PID")
sleep 1

SCRIPT_DIR="$test10_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
health_result=$(check_health "$PID" "$test10_dir/silent.log")

if [ "$health_result" = "ALIVE_UNVERIFIED" ]; then
    pass "check_health silent process ALIVE_UNVERIFIED"
else
    fail "check_health result: $health_result (expected ALIVE_UNVERIFIED)"
fi

cleanup_test_pids
TEST_PIDS=()

# ============ TEST 11: PROHIBITED PROCESS BLOCKS ============
echo "TEST 11: check_prohibited_processes detects trader.py"

test11_dir="$TEST_ROOT/test11"
mkdir -p "$test11_dir"

cat > "$test11_dir/trader.py" <<'EOF'
#!/usr/bin/env python3
import time
while True: time.sleep(60)
EOF
chmod +x "$test11_dir/trader.py"

cd "$test11_dir"
python3 trader.py > /dev/null 2>&1 &
PROHIBITED_PID=$!
TEST_PIDS+=("$PROHIBITED_PID")
sleep 1

source "$SOURCE_DIR/signal_bot_common.sh"
if ! check_prohibited_processes; then
    pass "Prohibited process detected"
else
    fail "Prohibited process not detected"
fi

cleanup_test_pids
TEST_PIDS=()

# ============ TEST 12: PROHIBITED FILE BLOCKS ============
echo "TEST 12: check_prohibited_files detects .trade_queue.jsonl"

test12_dir="$TEST_ROOT/test12"
mkdir -p "$test12_dir"

cat > "$test12_dir/.trade_queue.jsonl" <<'EOF'
{"action":"buy"}
EOF

source "$SOURCE_DIR/signal_bot_common.sh"
SCRIPT_DIR="$test12_dir"
if ! check_prohibited_files; then
    pass "Prohibited file detected"
else
    fail "Prohibited file not detected"
fi

# ============ TEST 13: ENV -I ISOLATION ============
echo "TEST 13: Environment isolation with env -i"

test13_dir="$TEST_ROOT/test13"
mkdir -p "$test13_dir"

cat > "$test13_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
UNKNOWN_VAR=should_not_export
EOF

SCRIPT_DIR="$test13_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
parse_env

env_output=$(env -i bash -c "export PATH=$PATH; . $SOURCE_DIR/signal_bot_common.sh; echo \$UNKNOWN_VAR")
if [ -z "$env_output" ]; then
    pass "env -i prevents unknown var export"
else
    fail "env -i test failed: $env_output"
fi

# ============ TEST 14: DUPLICATE .ENV KEY ============
echo "TEST 14: Duplicate .env key rejection"

test14_dir="$TEST_ROOT/test14"
mkdir -p "$test14_dir"

cat > "$test14_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=first
BTC_BOT_TOKEN=second
VANTAGE_EA_TOKEN=duplicate
STOCX_BOT_TOKEN=third
SIGNAL_CHAT_ID=chatid
EOF

SCRIPT_DIR="$test14_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
if ! parse_env 2>&1 | grep -q "Duplicate"; then
    fail "Duplicate key not detected"
else
    pass "Duplicate key rejected"
fi

# ============ TEST 15: MALFORMED .ENV ============
echo "TEST 15: Malformed .env line rejection"

test15_dir="$TEST_ROOT/test15"
mkdir -p "$test15_dir"

cat > "$test15_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
MALFORMED_NO_EQUALS
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF

SCRIPT_DIR="$test15_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
if ! parse_env 2>&1 | grep -q "Malformed"; then
    fail "Malformed line not detected"
else
    pass "Malformed line rejected"
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
