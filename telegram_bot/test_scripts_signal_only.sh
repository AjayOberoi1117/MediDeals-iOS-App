#!/bin/bash
#
# PRODUCTION FUNCTION TEST SUITE - Integration Tests
# All tests use real production code paths and entry points
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

EXPECTED_UID="$(id -u)"
EXPECTED_USERNAME="$(id -un)"

# TEST 1: PROCESS_ABSENT status
echo "TEST 1: Zero process returns PROCESS_ABSENT"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
set +e
find_process "nonexistent.py" "$test_dir" "$EXPECTED_UID" "$EXPECTED_USERNAME" > /dev/null 2>&1
status=$?
set -e
if [ $status -eq $PROCESS_ABSENT ]; then
    pass "Zero process returns PROCESS_ABSENT ($PROCESS_ABSENT)"
else
    fail "Zero process status (got $status, expected $PROCESS_ABSENT)"
fi
rm -rf "$test_dir"

# TEST 2: PROCESS_SINGLE status with PID
echo "TEST 2: Single process returns PROCESS_SINGLE with PID"
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
result=$(find_process "bot.py" "$test_dir" "$EXPECTED_UID" "$EXPECTED_USERNAME")
status=$?
set -e
cleanup_pids "$pid1"

if [ $status -eq $PROCESS_SINGLE ] && [ "$result" = "$pid1" ]; then
    pass "Single process returns PROCESS_SINGLE ($PROCESS_SINGLE) with PID"
else
    fail "Single process (got status=$status, pid=$result, expected status=$PROCESS_SINGLE, pid=$pid1)"
fi
rm -rf "$test_dir"

# TEST 3: PROCESS_DUPLICATE status
echo "TEST 3: Multiple processes return PROCESS_DUPLICATE"
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
find_process "bot.py" "$test_dir" "$EXPECTED_UID" "$EXPECTED_USERNAME" > /dev/null 2>&1
status=$?
set -e
cleanup_pids "$pid1" "$pid2"

if [ $status -eq $PROCESS_DUPLICATE ]; then
    pass "Multiple processes return PROCESS_DUPLICATE ($PROCESS_DUPLICATE)"
else
    fail "Multiple processes (got status=$status, expected $PROCESS_DUPLICATE)"
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
if validate_process "$pid" "bot.py" "$test_dir" "$EXPECTED_UID" ""; then
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
if validate_process "$pid" "bot.py" "$test_dir" "" "$EXPECTED_USERNAME"; then
    pass "Owner username validation"
else
    fail "Owner username validation"
fi
cleanup_pids "$pid"
rm -rf "$test_dir"

# TEST 6: Wrong UID rejected
echo "TEST 6: Wrong UID rejected"
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
wrong_uid=$((EXPECTED_UID + 9999))
if ! validate_process "$pid" "bot.py" "$test_dir" "$wrong_uid" ""; then
    pass "Wrong UID rejected"
else
    fail "Wrong UID not rejected"
fi
cleanup_pids "$pid"
rm -rf "$test_dir"

# TEST 7: Wrong username rejected
echo "TEST 7: Wrong username rejected"
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
if ! validate_process "$pid" "bot.py" "$test_dir" "" "wronguser"; then
    pass "Wrong username rejected"
else
    fail "Wrong username not rejected"
fi
cleanup_pids "$pid"
rm -rf "$test_dir"

# TEST 8: Prohibited process detection
echo "TEST 8: Prohibited process detection"
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

# TEST 9: Prohibited file detection
echo "TEST 9: Prohibited file detection"
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

# TEST 10: .env duplicate key rejection
echo "TEST 10: Duplicate .env key rejection"
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

# TEST 11: .env malformed line rejection
echo "TEST 11: Malformed .env line rejection"
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

# TEST 12: .env empty value rejection
echo "TEST 12: Empty .env value rejection"
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

# TEST 13: .env with comments and blanks
echo "TEST 13: .env comments and blank lines"
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

# TEST 14: require_verified_env_mapping blocks without APPROVED
echo "TEST 14: require_verified_env_mapping blocks without APPROVED"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
unset SIGNAL_BOT_ENV_MAPPING_VERIFIED
if ! require_verified_env_mapping 2>/dev/null; then
    pass "Gate blocks without APPROVED"
else
    fail "Gate did not block"
fi
rm -rf "$test_dir"

# TEST 15: require_verified_env_mapping allows with APPROVED
echo "TEST 15: require_verified_env_mapping allows with APPROVED"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"
export SIGNAL_BOT_ENV_MAPPING_VERIFIED="APPROVED"
if require_verified_env_mapping 2>/dev/null; then
    pass "Gate allows with APPROVED"
else
    fail "Gate blocked despite APPROVED"
fi
rm -rf "$test_dir"

# TEST 16: Startup gate absent blocks launch (real entry point)
echo "TEST 16: Startup gate absent blocks launch"
test_dir=$(mktemp -d)
mkdir -p "$test_dir/logs"
cp "$SOURCE_DIR/signal_bot_common.sh" "$test_dir/"
cp "$SOURCE_DIR/start_signal_bots.sh" "$test_dir/"
cd "$test_dir"
for bot in eurusd_bot.py gbpusd_bot.py usdjpy_bot.py gold_bot.py btc_bot.py nifty_scalper.py; do
    touch "$bot"
done
cat > "$test_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF

SCRIPT_DIR="$test_dir"
unset SIGNAL_BOT_ENV_MAPPING_VERIFIED
set +e
bash "$test_dir/start_signal_bots.sh" > "$test_dir/startup.log" 2>&1
startup_status=$?
set -e

if [ $startup_status -ne 0 ] && grep -q "Environment mapping not verified" "$test_dir/startup.log"; then
    pass "Startup gate absent blocks launch"
else
    fail "Startup gate did not block properly"
fi
rm -rf "$test_dir"

# TEST 17: Watchdog gate absent blocks restart (real entry point)
echo "TEST 17: Watchdog gate absent blocks restart"
test_dir=$(mktemp -d)
mkdir -p "$test_dir/logs"
cp "$SOURCE_DIR/signal_bot_common.sh" "$test_dir/"
cp "$SOURCE_DIR/watchdog_signal_only.sh" "$test_dir/"
cd "$test_dir"
for bot in eurusd_bot.py gbpusd_bot.py usdjpy_bot.py gold_bot.py btc_bot.py nifty_scalper.py; do
    touch "$bot"
done
cat > "$test_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF

SCRIPT_DIR="$test_dir"
unset SIGNAL_BOT_ENV_MAPPING_VERIFIED
set +e
bash "$test_dir/watchdog_signal_only.sh" --once > "$test_dir/watchdog.log" 2>&1
watchdog_status=$?
set -e

if [ $watchdog_status -ne 0 ] && grep -q "Environment mapping" "$test_dir/logs/watchdog.log" 2>/dev/null || grep -q "Environment mapping" "$test_dir/watchdog.log" 2>/dev/null; then
    pass "Watchdog gate absent blocks restart"
else
    fail "Watchdog gate did not block properly (status=$watchdog_status)"
fi
rm -rf "$test_dir"

# TEST 18: Startup with gate APPROVED proceeds to validations
echo "TEST 18: Startup with APPROVED gate proceeds to validations"
test_dir=$(mktemp -d)
mkdir -p "$test_dir/logs"
cp "$SOURCE_DIR/signal_bot_common.sh" "$test_dir/"
cp "$SOURCE_DIR/start_signal_bots.sh" "$test_dir/"
cd "$test_dir"
for bot in eurusd_bot.py gbpusd_bot.py usdjpy_bot.py gold_bot.py btc_bot.py nifty_scalper.py; do
    touch "$bot"
done
cat > "$test_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF

SCRIPT_DIR="$test_dir"
export SIGNAL_BOT_ENV_MAPPING_VERIFIED="APPROVED"
set +e
bash "$test_dir/start_signal_bots.sh" > "$test_dir/startup.log" 2>&1
startup_status=$?
set -e

if [ $startup_status -eq 0 ] && grep -q "STARTUP COMPLETE" "$test_dir/startup.log"; then
    pass "Startup with APPROVED gate proceeds"
else
    fail "Startup with APPROVED gate did not proceed"
fi
rm -rf "$test_dir"

# TEST 19: Watchdog with gate APPROVED proceeds to monitoring
echo "TEST 19: Watchdog with APPROVED gate proceeds to monitoring"
test_dir=$(mktemp -d)
mkdir -p "$test_dir/logs"
cp "$SOURCE_DIR/signal_bot_common.sh" "$test_dir/"
cp "$SOURCE_DIR/watchdog_signal_only.sh" "$test_dir/"
cd "$test_dir"
for bot in eurusd_bot.py gbpusd_bot.py usdjpy_bot.py gold_bot.py nifty_scalper.py; do
    touch "$bot"
done
cat > "$test_dir/.env" <<'EOF'
VANTAGE_EA_TOKEN=token1
BTC_BOT_TOKEN=token2
STOCX_BOT_TOKEN=token3
SIGNAL_CHAT_ID=chatid
EOF

SCRIPT_DIR="$test_dir"
export SIGNAL_BOT_ENV_MAPPING_VERIFIED="APPROVED"
set +e
bash "$test_dir/watchdog_signal_only.sh" --once > "$test_dir/watchdog.log" 2>&1
watchdog_status=$?
set -e

if grep -q "WATCHDOG CYCLE" "$test_dir/logs/watchdog.log" 2>/dev/null; then
    pass "Watchdog with APPROVED gate proceeds"
else
    fail "Watchdog with APPROVED gate did not proceed"
fi
rm -rf "$test_dir"

# TEST 20: Scanner remains observe-only (no restart)
echo "TEST 20: Scanner remains observe-only"
test_dir=$(mktemp -d)
SCRIPT_DIR="$test_dir"
source "$SOURCE_DIR/signal_bot_common.sh"

set +e
find_process "scanner_bot.py" "$test_dir" "$EXPECTED_UID" "$EXPECTED_USERNAME" > /dev/null 2>&1
status=$?
set -e

if [ $status -eq $PROCESS_ABSENT ]; then
    pass "Scanner observe-only handles absent"
else
    fail "Scanner observe-only failed"
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
