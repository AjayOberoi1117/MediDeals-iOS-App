# Windows MT5 Execution Bridge

Canonical execution package for Vantage MetaTrader5 DEMO account on Windows.

## Architecture

```
Signal Bots (Ubuntu GCP)
    ↓
.trade_queue.jsonl
    ↓
Windows MT5 Executor
    ↓
MetaTrader5 (Native Windows)
```

Signal bots on Ubuntu write trades to a JSON queue. The Windows MT5 Executor reads the queue and executes via the native MetaTrader5 Python API.

## Safety Features

- **Fail-Closed Defaults**: Signal-only mode by default (no orders placed)
- **Double-Gate Production**: Production trading requires BOTH:
  - `BOT_EXECUTION_MODE=production` in `.env`
  - `LIVE_TRADING_CONFIRMED=YES` in `.env`
- **Execution Verification Scripts**: Test MT5 connection, symbols, and order preflight WITHOUT placing trades
- **History Logging**: All signals logged to `.trade_history.jsonl` with execution results
- **Graceful Error Handling**: Stale/malformed signals skipped with logging

## Prerequisites

### Windows VM Setup (GCP/Azure/etc)

1. **Install Vantage MetaTrader5**
   - Download from Vantage official site
   - Create/log in with DEMO account
   - Enable `AutoTrading` in MT5 settings
   - Note your login number and server name

2. **Install Python 3.9+ (64-bit)**
   - Required for MetaTrader5 package
   - Download from https://www.python.org/
   - **IMPORTANT**: Select 64-bit version during installation
   - Add to PATH during setup

3. **Verify Installation**
   ```powershell
   python --version
   python -c "import struct; print('64-bit' if struct.calcsize('P') == 8 else '32-bit')"
   ```

## Installation

### Step 1: Initial Setup (Run Once)

```powershell
# Run PowerShell as Administrator

cd C:\path\to\windows-mt5-execution
.\setup_windows.ps1
```

This script will:
- Verify Python installation and architecture
- Create a virtual environment
- Install required packages
- Create `.env` from template
- Provide next steps

### Step 2: Configure Credentials

Edit `.env` with your Vantage MT5 credentials:

```powershell
notepad .env
```

**Required fields**:

```env
# Vantage MT5 DEMO Account
MT5_LOGIN=<your_account_number>
MT5_PASSWORD=<your_password>
MT5_SERVER=<broker_server_name>

# Telegram (optional, for notifications)
TELEGRAM_BOT_TOKEN=<your_bot_token>
TELEGRAM_CHAT_ID=<your_chat_id>

# Execution Mode (default: signal_only — SAFE)
BOT_EXECUTION_MODE=signal_only

# Production Gate (only set if enabling live trading)
LIVE_TRADING_CONFIRMED=
```

**Example MT5 Credentials** (from Vantage):
```
MT5_LOGIN=345600136
MT5_PASSWORD=YourPassword123
MT5_SERVER=Vantage-Demo
```

### Step 3: Verify MT5 Connection

```powershell
# Activate venv if not already active
.\venv\Scripts\Activate.ps1

# Test initialization and account info
python verify_mt5_connection.py
```

**Expected output**:
```
═══════════════════════════════════════════════════════════════════
TERMINAL INFORMATION
═══════════════════════════════════════════════════════════════════
  Connected:      True
  Trade Allowed:  True
  Trade Expert:   True (AutoTrading enabled in MT5)

═══════════════════════════════════════════════════════════════════
ACCOUNT INFORMATION
═══════════════════════════════════════════════════════════════════
  Account Type:   DEMO
  Balance:        10000.00 USD
✅ DEMO account confirmed — safe to test
```

**Troubleshooting**:
- If MT5 not found: MetaTrader5 terminal not running or not installed
- If connection fails: Check login/password/server name in `.env`
- If "Trade Allowed" is False: Enable AutoTrading in MT5 settings

### Step 4: Verify Symbol Availability

```powershell
python verify_symbol_specs.py
```

**Expected output**:
```
Checking REQUIRED symbols...

  ✅ EURUSD | Bid: 1.08765 | Ask: 1.08775
  ✅ GBPUSD | Bid: 1.27050 | Ask: 1.27065
  ✅ XAUUSD | Bid: 2510.50 | Ask: 2510.75
  ✅ BTCUSD | Bid: 67200.00 | Ask: 67250.00

═══════════════════════════════════════════════════════════════════
SUMMARY: 4/4 required symbols available
═══════════════════════════════════════════════════════════════════
```

**Troubleshooting**:
- If symbols not found: Broker may not offer them (rare with Vantage)
- If no tick data: Market may be closed (check session times)

### Step 5: Test Order Preflight

```powershell
python verify_order_check.py
```

**Expected output**:
```
Testing sample orders with order_check() [NO ORDERS SENT]...

  ✅ BUY EURUSD | Volume: 0.01 | Price: 1.08775 | SL: 1.08225 | TP: 1.09425
  ✅ SELL GBPUSD | Volume: 0.01 | Price: 1.27050 | SL: 1.27600 | TP: 1.26400

═══════════════════════════════════════════════════════════════════
SUMMARY: 4/4 test orders passed preflight
═══════════════════════════════════════════════════════════════════
✅ All preflight checks passed
```

**Troubleshooting**:
- If order_check fails: Check SL/TP distances or margin requirements
- "Insufficient margin": Account balance too low for test lot size

## Running the Executor

### Signal-Only Mode (Default — Safe)

```powershell
python windows_mt5_executor.py
```

This mode:
- Reads signals from queue
- **Does NOT place orders**
- Sends Telegram notifications
- Logs all signals to history
- Safe for testing without risk

### Production Mode (Double-Gated)

⚠️  **Only enable after successful testing**

1. Stop the executor (Ctrl+C)
2. Edit `.env`:
   ```env
   BOT_EXECUTION_MODE=production
   LIVE_TRADING_CONFIRMED=YES
   ```
3. **Restart**: `python windows_mt5_executor.py`

**Critical Safety Gates**:
- Both environment variables must be set to exact values
- No typos or variations accepted
- Default (missing values) = signal_only (SAFE)
- Single gate failure = orders blocked

## Signals Queue Format

The executor reads from `.trade_queue.jsonl` (created by Ubuntu signal bots).

**JSON format**:
```json
{
  "symbol": "EURUSD",
  "direction": "BUY",
  "sl": 1.08200,
  "tp": 1.09400,
  "source": "EURUSD_1H",
  "ts": 1691234567.89
}
```

**Valid symbols**: EURUSD, GBPUSD, USDJPY, XAUUSD, BTCUSD

**Valid directions**: BUY, SELL (case-insensitive)

## Output Files

- **`.trade_history.jsonl`** — All signals processed (success/skip/error)
- **`mt5_executor.log`** — Executor logs (debug/info/warning/error)

## Troubleshooting

### "MT5 initialization failed"
- Check MT5 credentials in `.env`
- Verify MetaTrader5 terminal is running
- Confirm login account is active

### "No tick data for EURUSD (market closed)"
- Check market session times for the symbol/broker
- Forex typically trades 24/5 (Sun-Fri)
- Metals/crypto may have different hours

### "Order check failed | retcode=10004"
- Insufficient margin: Balance too low for lot size
- Reduce lot size in `windows_mt5_executor.py` (line: `"volume": 0.01`)

### "LIVE_TRADING_CONFIRMED not satisfied"
- Verify `.env` has: `LIVE_TRADING_CONFIRMED=YES` (exact spelling)
- No extra spaces or quotes
- Case-sensitive

### Queue not being read
- Verify `.trade_queue.jsonl` exists in correct path
- Check `TRADE_QUEUE_PATH` in `.env` if using custom location
- Ubuntu bot must have network access to write the file

## Integration with Ubuntu Signal Bots

### File-Sharing Setup (REQUIRED)

Ubuntu signal bots write `.trade_queue.jsonl` locally. Windows executor must read this queue via **network share** (SMB).

**Architecture**:
```
Ubuntu signal bots → /mnt/windows/.trade_queue.jsonl (SMB mount)
                              ↓
                     Windows share: C:\shared-mt5-queue\
                              ↓
                  Windows MT5 executor (reads + executes)
```

**Setup**:
See **[NETWORK_SHARE_SETUP.md](NETWORK_SHARE_SETUP.md)** for complete instructions:
- Windows SMB share creation (one-time setup)
- Ubuntu mount configuration (one-time setup)
- Signal bot path configuration
- Troubleshooting and alternatives

**Quick Setup**:
1. Windows: Create folder `C:\shared-mt5-queue` and share it
2. Ubuntu: Mount via `sudo mount -t cifs //windows-ip/MT5Queue /mnt/windows`
3. Ubuntu .env: Set `TRADE_QUEUE_PATH=/mnt/windows/.trade_queue.jsonl`
4. Windows .env: Set `TRADE_QUEUE_PATH=C:\shared-mt5-queue\.trade_queue.jsonl`
5. Start both executors

**Alternative Options** (if network share not feasible):
- SSH/SCP sync: Ubuntu writes locally, sync script copies to Windows
- Cloud storage: S3/GCS/Google Drive shared folder

See **NETWORK_SHARE_SETUP.md** for alternatives and detailed troubleshooting.

### Canonical Signal Bot Integration

Ubuntu signal bots call:
```python
from trade_executor import queue_trade

# When signal fires:
queue_trade("EURUSD", "BUY", sl=1.08200, tp=1.09400, source="EURUSD_1H")
```

The Windows executor reads from this queue automatically.

## Monitoring

### Live Logs
```powershell
Get-Content mt5_executor.log -Tail 50 -Wait
```

### Trade History
```powershell
# View last 10 trades
Get-Content .trade_history.jsonl | Select-Object -Last 10
```

## Safety Checklist

Before enabling production:

- [ ] All verification scripts pass
- [ ] DEMO account confirmed
- [ ] All required symbols verified
- [ ] Order preflight successful
- [ ] Signal-only mode working (logs show no trades)
- [ ] `.env` has `BOT_EXECUTION_MODE=production`
- [ ] `.env` has `LIVE_TRADING_CONFIRMED=YES`
- [ ] Ubuntu bot has network access to queue file
- [ ] Telegram notifications working (optional)

## Disaster Recovery

### Immediate Stop
```powershell
# Stop executor (running in terminal)
Ctrl+C

# Clear trade queue to prevent execution of old signals
Remove-Item .trade_queue.jsonl
```

### Revert to Signal-Only
```
Edit .env:
BOT_EXECUTION_MODE=signal_only
LIVE_TRADING_CONFIRMED=
```

Restart executor — orders will not be placed.

## Support/Debugging

### Enable Debug Logging
Edit `windows_mt5_executor.py`:
```python
level=logging.DEBUG  # Change from INFO
```

### Test Signal Injection (Manual)
```powershell
# Create a test signal
@"
{"symbol": "EURUSD", "direction": "BUY", "sl": 1.08200, "tp": 1.09400, "source": "TEST", "ts": $([int][double]::Parse((Get-Date -UFormat %s)))}
"@ | Add-Content .trade_queue.jsonl

# Run executor
python windows_mt5_executor.py
```

## Files Included

- **`windows_mt5_executor.py`** — Main executor (reads queue, executes orders)
- **`verify_mt5_connection.py`** — Test MT5 initialization
- **`verify_symbol_specs.py`** — Test symbol availability
- **`verify_order_check.py`** — Test order preflight (no execution)
- **`requirements-windows.txt`** — Python dependencies
- **`.env.example`** — Configuration template
- **`setup_windows.ps1`** — Automated setup script
- **`README_WINDOWS_MT5.md`** — This file (main deployment guide)
- **`NETWORK_SHARE_SETUP.md`** — Network share configuration (SMB setup between Ubuntu and Windows)

## Next Steps

1. ✅ Run `setup_windows.ps1`
2. ✅ Edit `.env` with credentials
3. ✅ Run `verify_mt5_connection.py`
4. ✅ Run `verify_symbol_specs.py`
5. ✅ Run `verify_order_check.py`
6. ✅ Start executor: `python windows_mt5_executor.py`
7. ⏳ Wait for signals from Ubuntu bots
8. 🚀 (Optional) Enable production after successful testing

---

**Last Updated**: 2026-08-09  
**Canonical Source**: MediDeals-iOS-App/telegram_bot/  
**Execution Mode**: Fail-closed (signal-only by default)
