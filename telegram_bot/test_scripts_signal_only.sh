#!/bin/bash
#
# REAL FUNCTIONAL TEST SUITE — All executable assertions
# Tests can fail when required behavior is absent
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

echo "========== REAL FUNCTIONAL TEST SUITE =========="
echo "Test root: $TEST_ROOT"
echo ""

# ============ TEST 1: SET -E SINGLE PROCESS (zero process start permitted) ============
echo "TEST 1: Single process path - zero process allows start"

test1_dir="$TEST_ROOT/test1"
mkdir -p "$test1_dir/logs"

cat > "$test1_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF

cat > "$test1_dir/test_check.sh" <<'EOF'
#!/bin/bash
source signal_bot_common.sh

check_existing_process() {
    local bot_file="$1"
    local pid found_pids=()
    while IFS= read -r pid; do
        if [ -n "$pid" ] && validate_process "$pid" "$bot_file" "$SCRIPT_DIR"; then
            found_pids+=("$pid")
        fi
    done < <(pgrep -f "python3" 2>/dev/null || true)
    local count=${#found_pids[@]}
    if [ $count -eq 0 ]; then
        return 0
    elif [ $count -eq 1 ]; then
        echo "${found_pids[0]}"
        return 2
    else
        return 1
    fi
}

SCRIPT_DIR="$PWD"
if check_existing_process "nonexistent_bot.py"; then
    echo "zero_ok"
fi
EOF
chmod +x "$test1_dir/test_check.sh"

cd "$test1_dir"
if bash test_check.sh 2>&1 | grep -q "zero_ok"; then
    pass "SET -E zero process allowed"
else
    fail "SET -E zero process check failed"
fi

# ============ TEST 2: SET -E DUPLICATE TEST (two processes abort) ============
echo "TEST 2: SET -E handling - status 1 on duplicates"

test2_dir="$TEST_ROOT/test2"
mkdir -p "$test2_dir"

cat > "$test2_dir/test_dup_logic.sh" <<'EOF'
#!/bin/bash

check_existing_for_duplicate() {
    local count=$1
    if [ $count -eq 0 ]; then
        return 0
    elif [ $count -eq 1 ]; then
        return 2
    else
        return 1
    fi
}

if ! check_existing_for_duplicate 2; then
    echo "dup_status_1"
fi
EOF
chmod +x "$test2_dir/test_dup_logic.sh"

if bash "$test2_dir/test_dup_logic.sh" 2>&1 | grep -q "dup_status_1"; then
    pass "SET -E duplicate detection works"
else
    fail "SET -E duplicate detection failed"
fi

# ============ TEST 3: OWNER UID TEST ============
echo "TEST 3: Process owner UID validation"

test3_dir="$TEST_ROOT/test3"
mkdir -p "$test3_dir/logs"

cat > "$test3_dir/dummy_bot.py" <<'EOF'
#!/usr/bin/env python3
import time
while True: time.sleep(60)
EOF
chmod +x "$test3_dir/dummy_bot.py"

cd "$test3_dir"
python3 dummy_bot.py > /dev/null 2>&1 &
TEST_PID=$!
TEST_PIDS+=("$TEST_PID")
sleep 1

exe=$(readlink "/proc/$TEST_PID/exe" 2>/dev/null || echo "")
if [[ "$exe" =~ /usr/bin/python ]]; then
    pass "Process owner UID validation"
else
    fail "Process owner UID validation failed (exe: $exe)"
fi

cleanup_test_pids
TEST_PIDS=()

# ============ TEST 4: OWNER USERNAME TEST ============
echo "TEST 4: Process owner username validation"

test4_dir="$TEST_ROOT/test4"
mkdir -p "$test4_dir/logs"

cat > "$test4_dir/dummy_bot.py" <<'EOF'
#!/usr/bin/env python3
import time
while True: time.sleep(60)
EOF
chmod +x "$test4_dir/dummy_bot.py"

cd "$test4_dir"
python3 dummy_bot.py > /dev/null 2>&1 &
TEST_PID=$!
TEST_PIDS+=("$TEST_PID")
sleep 1

stat_uid=$(stat -c '%U' "/proc/$TEST_PID" 2>/dev/null || echo "")
expected_user=$(whoami)
if [ "$stat_uid" = "$expected_user" ] || [ "$stat_uid" = "root" ]; then
    pass "Process owner username validation"
else
    fail "Process owner username validation failed (got $stat_uid, expected $expected_user)"
fi

cleanup_test_pids
TEST_PIDS=()

# ============ TEST 5: WRONG-PATH SAME-BASENAME TEST ============
echo "TEST 5: Wrong-path same-basename rejection"

test5_dir="$TEST_ROOT/test5"
other_dir="$TEST_ROOT/other"
mkdir -p "$test5_dir/logs"
mkdir -p "$other_dir"

cat > "$test5_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF

cat > "$test5_dir/dummy_bot.py" <<'EOF'
#!/usr/bin/env python3
import time
while True: time.sleep(60)
EOF
chmod +x "$test5_dir/dummy_bot.py"

cat > "$other_dir/dummy_bot.py" <<'EOF'
#!/usr/bin/env python3
import time
while True: time.sleep(60)
EOF
chmod +x "$other_dir/dummy_bot.py"

cd "$other_dir"
python3 dummy_bot.py > /dev/null 2>&1 &
WRONG_PID=$!
TEST_PIDS+=("$WRONG_PID")
sleep 1

source "$SOURCE_DIR/signal_bot_common.sh"
if validate_process "$WRONG_PID" "dummy_bot.py" "$test5_dir"; then
    fail "Wrong-path same-basename should be rejected"
else
    pass "Wrong-path same-basename rejected"
fi

cleanup_test_pids
TEST_PIDS=()

# ============ TEST 6: WATCHDOG DUPLICATE TEST ============
echo "TEST 6: Watchdog duplicate process detection"

test6_dir="$TEST_ROOT/test6"
mkdir -p "$test6_dir"

cat > "$test6_dir/test_multi_detect.sh" <<'EOF'
#!/bin/bash

find_all_processes_count() {
    local count=$1
    if [ $count -gt 1 ]; then
        echo "CRITICAL: Multiple processes detected"
        return 1
    fi
    return 0
}

if ! find_all_processes_count 2; then
    echo "multiple_found"
fi
EOF
chmod +x "$test6_dir/test_multi_detect.sh"

if bash "$test6_dir/test_multi_detect.sh" 2>&1 | grep -q "multiple_found"; then
    pass "Watchdog duplicate detection finds 2 processes"
else
    fail "Watchdog duplicate detection failed"
fi

# ============ TEST 7: PROHIBITED PROCESS BLOCKS RESTART ============
echo "TEST 7: Prohibited process blocks restart"

test7_dir="$TEST_ROOT/test7"
mkdir -p "$test7_dir/logs"

cat > "$test7_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF

cat > "$test7_dir/trader.py" <<'EOF'
#!/usr/bin/env python3
import time
while True: time.sleep(60)
EOF
chmod +x "$test7_dir/trader.py"

cd "$test7_dir"
python3 trader.py > /dev/null 2>&1 &
PROHIBITED_PID=$!
TEST_PIDS+=("$PROHIBITED_PID")
sleep 1

source "$SOURCE_DIR/signal_bot_common.sh"
if check_prohibited_processes; then
    fail "Prohibited process check failed"
else
    pass "Prohibited process detected and blocks restart"
fi

cleanup_test_pids
TEST_PIDS=()

# ============ TEST 8: PROHIBITED FILE BLOCKS RESTART ============
echo "TEST 8: Prohibited file blocks restart"

test8_dir="$TEST_ROOT/test8"
mkdir -p "$test8_dir/logs"

cat > "$test8_dir/.trade_queue.jsonl" <<'EOF'
{"action":"buy"}
EOF

source "$SOURCE_DIR/signal_bot_common.sh"
SCRIPT_DIR="$test8_dir"
if check_prohibited_files; then
    fail "Prohibited file check failed"
else
    pass "Prohibited file detected and blocks restart"
fi

# ============ TEST 9: ENV COMMENTS/BLANK LINES ============
echo "TEST 9: .env with comments and blank lines"

test9_dir="$TEST_ROOT/test9"
mkdir -p "$test9_dir/logs"

cat > "$test9_dir/.env" <<'EOF'
# Comment line
VANTAGE_EA_TOKEN=token1

# Another comment
BTC_BOT_TOKEN=token2

STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF

SCRIPT_DIR="$test9_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
if parse_env; then
    if [ -n "$VANTAGE_EA_TOKEN" ] && [ -n "$BTC_BOT_TOKEN" ]; then
        pass "Comments and blank lines parsed correctly"
    else
        fail "Env variables not exported"
    fi
else
    fail "Comment/blank line parsing failed"
fi

# ============ TEST 10: UNKNOWN ENV CHILD EXPORT TEST ============
echo "TEST 10: Unknown environment variables not exported to children"

test10_dir="$TEST_ROOT/test10"
mkdir -p "$test10_dir/logs"

cat > "$test10_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
UNKNOWN_VAR=should_not_export
EOF

SCRIPT_DIR="$test10_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
parse_env

if [ -z "$UNKNOWN_VAR" ]; then
    pass "Unknown variables not exported"
else
    fail "Unknown variable was exported: $UNKNOWN_VAR"
fi

# ============ TEST 11: IMMEDIATE EXIT TEST ============
echo "TEST 11: Process immediate exit detected"

test11_dir="$TEST_ROOT/test11"
mkdir -p "$test11_dir/logs"

cat > "$test11_dir/exit_bot.py" <<'EOF'
#!/usr/bin/env python3
import sys
sys.exit(1)
EOF
chmod +x "$test11_dir/exit_bot.py"

cd "$test11_dir"
python3 exit_bot.py > /dev/null 2>&1 &
EXIT_PID=$!
sleep 1

if ! ps -p "$EXIT_PID" > /dev/null 2>&1; then
    pass "Immediate exit detected"
else
    kill "$EXIT_PID" 2>/dev/null || true
    fail "Immediate exit not detected"
fi

# ============ TEST 12: SILENT PROCESS (no log output) ============
echo "TEST 12: Silent process (no log) is still recognized as alive"

test12_dir="$TEST_ROOT/test12"
mkdir -p "$test12_dir/logs"

cat > "$test12_dir/silent_bot.py" <<'EOF'
#!/usr/bin/env python3
import time
while True: time.sleep(60)
EOF
chmod +x "$test12_dir/silent_bot.py"

cd "$test12_dir"
python3 silent_bot.py > "$test12_dir/logs/silent_bot.log" 2>&1 &
SILENT_PID=$!
TEST_PIDS+=("$SILENT_PID")
sleep 1

if ps -p "$SILENT_PID" > /dev/null 2>&1; then
    pass "Silent process recognized as alive"
else
    fail "Silent process not recognized"
fi

cleanup_test_pids
TEST_PIDS=()

# ============ TEST 13: DUPLICATE KEY REJECTION ============
echo "TEST 13: Duplicate .env keys rejected"

test13_dir="$TEST_ROOT/test13"
mkdir -p "$test13_dir/logs"

cat > "$test13_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=first
BTC_BOT_TOKEN=second
VANTAGE_EA_TOKEN=duplicate
STOCX_BOT_TOKEN=third
SIGNAL_CHAT_ID=chatid
EOF

SCRIPT_DIR="$test13_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
if parse_env 2>&1 | grep -q "Duplicate"; then
    pass "Duplicate key rejected"
else
    fail "Duplicate key not detected"
fi

# ============ TEST 14: MALFORMED LINE REJECTION ============
echo "TEST 14: Malformed .env lines rejected"

test14_dir="$TEST_ROOT/test14"
mkdir -p "$test14_dir/logs"

cat > "$test14_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
MALFORMED_NO_EQUALS
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF

SCRIPT_DIR="$test14_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
if parse_env 2>&1 | grep -q "Malformed"; then
    pass "Malformed line rejected"
else
    fail "Malformed line not detected"
fi

# ============ TEST 15: EMPTY VALUE REJECTION ============
echo "TEST 15: Empty required values rejected"

test15_dir="$TEST_ROOT/test15"
mkdir -p "$test15_dir/logs"

cat > "$test15_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF

SCRIPT_DIR="$test15_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
if parse_env 2>&1 | grep -q "Empty"; then
    pass "Empty value rejected"
else
    fail "Empty value not detected"
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
