#!/usr/bin/env bash
################################################################################
# Deploy TradeFromFile EA (File-Bridge Architecture)
# ==================================================
#
# Deploys the EA to MT5, enables it, validates execution pipeline.
# No Python IPC (wine_server.py) — all execution via CSV file bridge.
#
# Usage:
#   bash deploy_ea_file_bridge.sh
#
# Prerequisites:
#   - MT5 running under Wine (from stabilize_mt5_bridge.sh)
#   - trader.py ready to write to .trade_queue.jsonl
#   - TradeFromFile.mq5 exists in current directory
#
################################################################################

set -euo pipefail

readonly MT5_PREFIX="/root/.wine_mt5"
readonly MT5_PATH="$MT5_PREFIX/drive_c/Program Files/MetaTrader 5"
readonly EXPERTS_FOLDER="$MT5_PATH/MQL5/Experts"
readonly FILES_FOLDER="$MT5_PATH/MQL5/Files"
readonly BOT_DIR="/root/MediDeals-iOS-App/telegram_bot"

echo "════════════════════════════════════════════════════════════════════"
echo "Deploy TradeFromFile EA (File-Bridge Architecture)"
echo "════════════════════════════════════════════════════════════════════"

echo ""
echo "STEP 1: Verify MT5 folder structure"

if [[ ! -d "$MT5_PATH" ]]; then
    echo "✗ MT5 folder not found: $MT5_PATH"
    echo "  Ensure MT5 is installed and stabilize_mt5_bridge.sh ran successfully"
    exit 1
fi
echo "✓ MT5 folder found"

if [[ ! -d "$EXPERTS_FOLDER" ]]; then
    echo "✗ MQL5/Experts folder not found: $EXPERTS_FOLDER"
    echo "  Creating folder..."
    mkdir -p "$EXPERTS_FOLDER"
    echo "✓ Created"
fi

if [[ ! -d "$FILES_FOLDER" ]]; then
    echo "✗ MQL5/Files folder not found: $FILES_FOLDER"
    echo "  Creating folder..."
    mkdir -p "$FILES_FOLDER"
    echo "✓ Created"
fi

echo ""
echo "STEP 2: Copy TradeFromFile.mq5 to Experts"

if [[ ! -f "TradeFromFile.mq5" ]]; then
    echo "✗ TradeFromFile.mq5 not found in current directory"
    exit 1
fi

cp TradeFromFile.mq5 "$EXPERTS_FOLDER/"
echo "✓ EA copied to: $EXPERTS_FOLDER/TradeFromFile.mq5"

echo ""
echo "STEP 3: Verify environment"

cd "$BOT_DIR"

if [[ ! -f ".env" ]]; then
    echo "✗ .env file not found"
    exit 1
fi

# Check MT5_FILES_PATH
if grep -q "MT5_FILES_PATH" .env; then
    echo "✓ MT5_FILES_PATH already in .env"
else
    echo "⚠ Adding MT5_FILES_PATH to .env"
    echo "MT5_FILES_PATH=$FILES_FOLDER" >> .env
fi

echo "✓ Environment ready"

echo ""
echo "STEP 4: Verify trader.py can write to MT5/Files"

if python3 -c "
import os, sys
sys.path.insert(0, '.')
os.chdir('.')
try:
    from trader import MT5_FILES, SIGNALS_FILE
    os.makedirs(MT5_FILES, exist_ok=True)
    print(f'✓ MT5_FILES: {MT5_FILES}')
    print(f'✓ SIGNALS_FILE: {SIGNALS_FILE}')
    # Test write
    test_line = 'EURUSD,BUY,1.0800,1.0900,10101,test,1234567890\n'
    with open(SIGNALS_FILE, 'a') as f:
        f.write(test_line)
    # Clear for actual use
    open(SIGNALS_FILE, 'w').close()
    print('✓ Write test passed')
    sys.exit(0)
except Exception as e:
    print(f'✗ Error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1; then
    echo "✓ trader.py can write to MT5/Files"
else
    echo "✗ trader.py write test failed"
    exit 1
fi

echo ""
echo "STEP 5: Compile TradeFromFile.mq5 (MT5 MetaEditor required)"
echo ""
echo "  The EA has been copied to: $EXPERTS_FOLDER/TradeFromFile.mq5"
echo ""
echo "  To compile:"
echo "    1. In MT5 terminal: Tools → MetaEditor"
echo "    2. Open: File → Open → MQL5/Experts/TradeFromFile.mq5"
echo "    3. Compile: F7 or Compile button"
echo "    4. Check Build tab for 'compiled successfully'"
echo ""

read -p "  Has TradeFromFile.mq5 been compiled? (yes/no): " compiled

if [[ "$compiled" != "yes" ]]; then
    echo "⚠ Compilation skipped"
    echo "  Required before attaching EA"
fi

echo ""
echo "STEP 6: Attach EA to Chart"
echo ""
echo "  ╔════════════════════════════════════════════════════════════════╗"
echo "  ║ MANUAL ACTION REQUIRED                                        ║"
echo "  ╠════════════════════════════════════════════════════════════════╣"
echo "  ║                                                                ║"
echo "  ║ 1. Connect to VNC: vncviewer 168.144.30.182:5999              ║"
echo "  ║                                                                ║"
echo "  ║ 2. In MT5 terminal:                                           ║"
echo "  ║    • Navigate to any chart (e.g., EURUSD)                     ║"
echo "  ║    • Right-click → Expert Advisors → TradeFromFile            ║"
echo "  ║    • OR: File → Open → MQL5/Experts/TradeFromFile.ex5         ║"
echo "  ║                                                                ║"
echo "  ║ 3. Settings dialog:                                           ║"
echo "  ║    • LotSize: 0.01 (DEMO ONLY)                                ║"
echo "  ║    • Deviation: 20 (slippage)                                 ║"
echo "  ║    • CheckSecs: 5 (poll interval)                             ║"
echo "  ║    • SignalsFile: mt5_signals.csv                             ║"
echo "  ║                                                                ║"
echo "  ║ 4. Permissions:                                               ║"
echo "  ║    • ✓ Allow DLL imports (for CTrade)                         ║"
echo "  ║    • ✓ Allow network requests (optional)                      ║"
echo "  ║    • ✓ Allow file operations                                  ║"
echo "  ║                                                                ║"
echo "  ║ 5. Click 'OK' to attach                                       ║"
echo "  ║                                                                ║"
echo "  ║ 6. Journal tab should show:                                   ║"
echo "  ║    'TradeFromFile EA started | watching: mt5_signals.csv...'  ║"
echo "  ║                                                                ║"
echo "  ║ 7. Close VNC                                                  ║"
echo "  ║                                                                ║"
echo "  ║ 8. Return to terminal and confirm below                       ║"
echo "  ║                                                                ║"
echo "  ╚════════════════════════════════════════════════════════════════╝"
echo ""

read -p "Press ENTER after EA is attached and running: " _

echo ""
echo "STEP 7: Validate file-bridge pipeline"
echo ""

# Create test signal
test_signal=$(cat <<EOF
{"symbol": "EURUSD", "direction": "BUY", "sl": 1.08000, "tp": 1.09000, "source": "EURUSD_15m", "ts": $(date +%s)}
EOF
)

echo "$test_signal" >> .trade_queue.jsonl
echo "✓ Test signal written to .trade_queue.jsonl"

echo "✓ Waiting for trader.py to process (up to 10 seconds)..."
sleep 10

if grep -q "EURUSD" "$FILES_FOLDER/mt5_signals.csv" 2>/dev/null; then
    echo "✓ Signal found in mt5_signals.csv (trader.py processed it)"
else
    echo "⚠ Signal not found in MT5/Files/mt5_signals.csv yet"
    echo "  Verify trader.py is running: ps aux | grep trader.py"
fi

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "✓ File-Bridge Deployment Complete"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Start trader.py: bash start_trader.sh"
echo "  2. Start signal bots"
echo "  3. Monitor EA journal in MT5 for trade executions"
echo "  4. Verify controlled 0.01-lot demo order"
echo ""
