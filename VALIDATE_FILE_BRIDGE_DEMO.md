# File-Bridge Demo Validation Steps

## Prerequisites

- Enhanced TradeFromFile.mq5 committed (with SL/TP validation)
- MT5 running under Wine on droplet 168.144.30.182
- trader.py ready to write signals
- Demo account connected (Vantage DEMO only)

## Step 1: Recompile Enhanced EA

```bash
# Connect to VNC
vncviewer 168.144.30.182:5999
```

In MT5 terminal:
1. Tools → MetaEditor
2. File → Open → MQL5/Experts/TradeFromFile.mq5
3. Press F7 (Compile)
4. Verify Build tab: "compiled successfully"
5. Close MetaEditor

## Step 2: Re-attach EA to Chart

In MT5 terminal:
1. Navigate to EURUSD chart (or any available)
2. Detach existing TradeFromFile EA: Right-click → Expert Advisors → Remove
3. Reattach updated EA: Right-click → Expert Advisors → TradeFromFile
4. Settings dialog appears:
   - LotSize: **0.01** (demo only)
   - Deviation: **20**
   - CheckSecs: **5**
   - SignalsFile: **mt5_signals.csv**
5. Click OK
6. Check Journal tab for:
   ```
   TradeFromFile EA v2 started | watching: mt5_signals.csv | 
   approved: EURUSD,GBPUSD,XAUUSD
   ```

Keep MT5 Journal window **visible** during all tests.

## Step 3: Test 1 - Valid EURUSD BUY Signal

Close VNC. On droplet terminal:

```bash
cd /root/MediDeals-iOS-App/telegram_bot

# Generate valid EURUSD BUY signal
# Current prices: EURUSD ~1.0850
python3 << 'EOF'
import json, time

signal = {
    "symbol": "EURUSD",
    "direction": "BUY",
    "sl": 1.08200,      # Below entry
    "tp": 1.09200,      # Above entry
    "source": "test_eurusd_buy",
    "ts": time.time()
}

with open(".trade_queue.jsonl", "a") as f:
    f.write(json.dumps(signal) + "\n")

print(f"✓ Test signal queued: {signal}")
EOF
```

Expected behavior:
1. trader.py reads signal from .trade_queue.jsonl
2. trader.py writes to mt5_signals.csv
3. EA polls CSV (every 5 seconds)
4. EA validates SL/TP (should PASS for 1.0820 < 1.0850 < 1.0920)
5. EA executes BUY 0.01 EURUSD
6. Check MT5 Journal for:
   ```
   TRADE OK: BUY EURUSD lot=0.01 sl=1.08200 tp=1.09200 magic=10102
   ```

**Verify:**
- ✓ CSV detected and consumed
- ✓ Order accepted
- ✓ Direction: BUY
- ✓ Lot: 0.01
- ✓ SL: ~1.08200
- ✓ TP: ~1.09200
- ✓ Ticket generated (in MT5 positions)

**If FAILS with error 4756:** Check Journal for validation error (e.g., "SL must be below Bid"). Adjust signal and retry.

## Step 4: Close Test 1 Position

In MT5 terminal:
1. Ctrl+T to open Trades window
2. Find position from Step 3 (EURUSD BUY, magic=10102)
3. Right-click → Close
4. Verify position closed with profit/loss

## Step 5: Test 2 - Valid GBPUSD SELL Signal

Back to droplet terminal:

```bash
# Current prices: GBPUSD ~1.2700
python3 << 'EOF'
import json, time

signal = {
    "symbol": "GBPUSD",
    "direction": "SELL",
    "sl": 1.27500,      # Above entry
    "tp": 1.26500,      # Below entry
    "source": "test_gbpusd_sell",
    "ts": time.time()
}

with open(".trade_queue.jsonl", "a") as f:
    f.write(json.dumps(signal) + "\n")

print(f"✓ Test signal queued: {signal}")
EOF
```

**Verify (in MT5 Journal):**
- ✓ TRADE OK: SELL GBPUSD 0.01
- ✓ SL: ~1.27500
- ✓ TP: ~1.26500
- ✓ Ticket generated

## Step 6: Close Test 2 Position

In MT5, close GBPUSD SELL position (magic=10202).

## Step 7: Test 3 - Valid XAUUSD BUY Signal

```bash
# Current prices: XAUUSD ~2000
python3 << 'EOF'
import json, time

signal = {
    "symbol": "XAUUSD",
    "direction": "BUY",
    "sl": 1990,         # Below entry
    "tp": 2010,         # Above entry
    "source": "test_xauusd_buy",
    "ts": time.time()
}

with open(".trade_queue.jsonl", "a") as f:
    f.write(json.dumps(signal) + "\n")

print(f"✓ Test signal queued: {signal}")
EOF
```

**Verify (in MT5 Journal):**
- ✓ TRADE OK: BUY XAUUSD 0.01
- ✓ SL: ~1990
- ✓ TP: ~2010
- ✓ Ticket generated

## Step 8: Test 4 - INVALID Signal (USDJPY) - Should REJECT

```bash
python3 << 'EOF'
import json, time

# USDJPY is in the BLOCKED list
signal = {
    "symbol": "USDJPY",
    "direction": "BUY",
    "sl": 147.00,
    "tp": 148.00,
    "source": "test_usdjpy_invalid",
    "ts": time.time()
}

with open(".trade_queue.jsonl", "a") as f:
    f.write(json.dumps(signal) + "\n")

print(f"✓ Test signal queued: {signal}")
EOF
```

**Verify (in MT5 Journal):**
```
REJECT USDJPY: not in approved list (EURUSD,GBPUSD,XAUUSD)
```

No order should be created.

## Step 9: Test 5 - INVALID SL/TP - Should REJECT or EXPAND

```bash
python3 << 'EOF'
import json, time

# Invalid SL/TP for BUY: SL above TP
signal = {
    "symbol": "EURUSD",
    "direction": "BUY",
    "sl": 1.09000,      # Above TP (invalid for BUY)
    "tp": 1.08500,      # Below SL (invalid)
    "source": "test_invalid_sl_tp",
    "ts": time.time()
}

with open(".trade_queue.jsonl", "a") as f:
    f.write(json.dumps(signal) + "\n")

print(f"✓ Test signal queued: {signal}")
EOF
```

**Verify (in MT5 Journal):**
```
REJECT BUY EURUSD: TP=1.08500 must be above Bid=1.08450
```

No order should be created.

## Step 10: Summary

After all tests, verify:

- ✓ Valid EURUSD BUY order executed
- ✓ Valid GBPUSD SELL order executed  
- ✓ Valid XAUUSD BUY order executed
- ✓ USDJPY REJECTED (not approved)
- ✓ Invalid SL/TP REJECTED (fail-closed)
- ✓ All executed orders: 0.01 lots, SL/TP attached
- ✓ Tickets generated, positions visible in MT5
- ✓ No duplicate orders on retry
- ✓ Journal shows clear accept/reject reasons

## If All Tests PASS

Return to this session:

```
FILE BRIDGE DEMO EXECUTION VERIFIED
```

Then proceed to:
1. Start trader.py on droplet
2. Run recover_trading_system_file_bridge.sh
3. Enable live signal bots

## If Any Test FAILS

Identify the failure:
- Journal shows error code (e.g., 4756)
- Validation message explains why (e.g., "SL must be below Bid")
- Check current bid/ask prices
- Adjust signal SL/TP accordingly
- Retry

Return:
```
BLOCKED — <exact error from Journal>
```
