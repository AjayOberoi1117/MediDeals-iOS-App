#!/bin/bash
#
# PRODUCTION FUNCTION TEST SUITE - Simplified
# All tests use real production code
#

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASSED=0
FAILED=0

pass() { echo "✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED + 1)); }

cleanup_pids() {
    for pid in "$@"; do
        if ps -p "$pid" > /dev/null 2>&1; then
            kill "$pid" 2>/dev/null
            sleep 0.2
            if ps -p "$pid" > /dev/null 2>&1; then
                kill -9 "$pid" 2>/dev/null
            fi
        fi
    done
}

echo "========== PRODUCTION FUNCTION TEST SUITE =========="
echo ""

# TEST 1: SET -E status 0 - no process
echo "TEST 1: Zero process status 0"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
find_process "nonexistent.py" "$test_dir" > /dev/null 2>&1
status=$?
set -e
if [ $status -eq 0 ]; then
    pass "Zero process returns status 0"
else
    fail "Zero process status (got $status, expected 0)"
fi
rm -rf "$test_dir"

# TEST 2: SET -E status 1 - single process
echo "TEST 2: Single process status 1 with PID"
test_dir=$(mktemp -d)
cat > "$test_dir/bot.py" <<'EOF'
#!/usr/bin/env python3
import time
while True: time.sleep(60)
EOF
chmod +x "$test_dir/bot.py"
cd "$test_dir"
python3 bot.py > /dev/null 2>&1 &
pid1=$!
sleep 0.5

SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
result=$(find_process "bot.py" "$test_dir")
status=$?
set -e
cleanup_pids "$pid1"

if [ $status -eq 1 ] && [ "$result" = "$pid1" ]; then
    pass "Single process returns status 1 with PID"
else
    fail "Single process (got status=$status, pid=$result, expected status=1, pid=$pid1)"
fi
rm -rf "$test_dir"

# TEST 3: SET -E status 2 - multiple processes
echo "TEST 3: Multiple processes status 2"
test_dir=$(mktemp -d)
cat > "$test_dir/bot.py" <<'EOF'
#!/usr/bin/env python3
import time
while True: time.sleep(60)
EOF
chmod +x "$test_dir/bot.py"
cd "$test_dir"
python3 bot.py > /dev/null 2>&1 &
pid1=$!
sleep 0.2
python3 bot.py > /dev/null 2>&1 &
pid2=$!
sleep 0.5

SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
find_process "bot.py" "$test_dir" > /dev/null 2>&1
status=$?
set -e
cleanup_pids "$pid1" "$pid2"

if [ $status -eq 2 ]; then
    pass "Multiple processes returns status 2"
else
    fail "Multiple processes (got status=$status, expected 2)"
fi
rm -rf "$test_dir"

# TEST 4: Owner UID validation
echo "TEST 4: Owner UID validation"
test_dir=$(mktemp -d)
cat > "$test_dir/bot.py" <<'EOF'
#!/usr/bin/env python3
import time
while True: time.sleep(60)
EOF
chmod +x "$test_dir/bot.py"
cd "$test_dir"
python3 bot.py > /dev/null 2>&1 &
pid=$!
sleep 0.5

SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
expected_uid=$(id -u)
if validate_process "$pid" "bot.py" "$test_dir" "$expected_uid" ""; then
    pass "Owner UID validation"
else
    fail "Owner UID validation"
fi
cleanup_pids "$pid"
rm -rf "$test_dir"

# TEST 5: Owner username validation
echo "TEST 5: Owner username validation"
test_dir=$(mktemp -d)
cat > "$test_dir/bot.py" <<'EOF'
#!/usr/bin/env python3
import time
while True: time.sleep(60)
EOF
chmod +x "$test_dir/bot.py"
cd "$test_dir"
python3 bot.py > /dev/null 2>&1 &
pid=$!
sleep 0.5

SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
expected_user=$(whoami)
if validate_process "$pid" "bot.py" "$test_dir" "" "$expected_user"; then
    pass "Owner username validation"
else
    fail "Owner username validation"
fi
cleanup_pids "$pid"
rm -rf "$test_dir"

# TEST 6: Prohibited process detection
echo "TEST 6: Prohibited process detection"
test_dir=$(mktemp -d)
cat > "$test_dir/trader.py" <<'EOF'
#!/usr/bin/env python3
import time
while True: time.sleep(60)
EOF
chmod +x "$test_dir/trader.py"
cd "$test_dir"
python3 trader.py > /dev/null 2>&1 &
pid=$!
sleep 0.5

source "$SOURCE_DIR/signal_bot_common.sh"
if ! check_prohibited_processes; then
    pass "Prohibited process detected"
else
    fail "Prohibited process not detected"
fi
cleanup_pids "$pid"
rm -rf "$test_dir"

# TEST 7: Prohibited file detection
echo "TEST 7: Prohibited file detection"
test_dir=$(mktemp -d)
touch "$test_dir/.trade_queue.jsonl"

SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
if ! check_prohibited_files; then
    pass "Prohibited file detected"
else
    fail "Prohibited file not detected"
fi
rm -rf "$test_dir"

# TEST 8: .env duplicate key rejection
echo "TEST 8: Duplicate .env key rejection"
test_dir=$(mktemp -d)
cat > "$test_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=first
BTC_BOT_TOKEN=second
VANTAGE_EA_TOKEN=duplicate
STOCX_BOT_TOKEN=third
SIGNAL_CHAT_ID=chatid
EOF
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
if ! parse_env 2>&1 | grep -q "Duplicate"; then
    fail "Duplicate key not detected"
else
    pass "Duplicate key rejected"
fi
rm -rf "$test_dir"

# TEST 9: .env malformed line rejection
echo "TEST 9: Malformed .env line rejection"
test_dir=$(mktemp -d)
cat > "$test_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
MALFORMED_NO_EQUALS
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
if ! parse_env 2>&1 | grep -q "Malformed"; then
    fail "Malformed line not detected"
else
    pass "Malformed line rejected"
fi
rm -rf "$test_dir"

# TEST 10: .env empty value rejection
echo "TEST 10: Empty .env value rejection"
test_dir=$(mktemp -d)
cat > "$test_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
if ! parse_env 2>&1 | grep -q "Empty"; then
    fail "Empty value not detected"
else
    pass "Empty value rejected"
fi
rm -rf "$test_dir"

# TEST 11: .env with comments and blanks
echo "TEST 11: .env comments and blank lines"
test_dir=$(mktemp -d)
cat > "$test_dir/.env" <<'EOF'
# Comment
VANTAGE_EA_TOKEN=token1

# Another comment
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
if parse_env > /dev/null 2>&1 && [ -n "$VANTAGE_EA_TOKEN" ]; then
    pass "Comments and blanks parsed"
else
    fail "Comments/blanks parsing"
fi
rm -rf "$test_dir"

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
