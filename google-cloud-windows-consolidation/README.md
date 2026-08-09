# Google Cloud Windows Consolidation — Complete Trading Stack

**Status**: ✅ READY FOR DEPLOYMENT  
**Date**: 2026-08-09  
**Target**: Google Cloud Windows VM (vantage-mt5-execution)  
**Account**: Vantage DEMO (non-production, safe for testing)

---

## Quick Start

```powershell
# 1. Setup (one-time)
cd C:\TradingBots
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt

# 2. Configure
notepad .env
# Set: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, TWELVE_DATA_KEY, etc.

# 3. Start bots
cd scripts
.\start_all.ps1

# 4. Monitor
.\status_all.ps1
Get-Content ..\logs\btc_bot.log -Tail 50 -Wait
```

---

## Architecture

**Three signal generation bots running on Windows:**

```
┌─────────────────────────────────────────┐
│  Google Cloud Windows VM                │
│  (vantage-mt5-execution)                │
│                                         │
│  ├─ btc_bot_windows.py                 │
│  │  └─ EMA(9/21) + RSI(14) | 1H        │
│  │  └─ Symbol: BTCUSD                  │
│  │  └─ SL: 1x ATR | TP: 3x ATR        │
│  │                                     │
│  ├─ gold_bot_windows.py                │
│  │  └─ EMA(9/21) + RSI(14) | 1H        │
│  │  └─ Symbol: XAUUSD                 │
│  │  └─ SL: 1x ATR | TP: 3x ATR        │
│  │                                     │
│  ├─ forex_scalper_windows.py           │
│  │  └─ EMA(9/21) + RSI(14) + ADX | 15m│
│  │  └─ Symbols: EURUSD, GBPUSD        │
│  │  └─ SL: 1.5x ATR | TP: 3x ATR     │
│  │  └─ Cooldown: 30min per pair       │
│  │                                     │
│  └─ windows_mt5_executor.py            │
│     └─ Reads .trade_queue.jsonl       │
│     └─ Executes orders via MT5 API    │
│     └─ Double-gate safety check       │
│                                         │
│  Data Flow:                             │
│  Bots → .trade_queue.jsonl → Executor  │
│              ↓                          │
│      MetaTrader5 (Vantage DEMO)        │
│              ↓                          │
│         Trade Execution                │
│                                         │
└─────────────────────────────────────────┘
```

---

## Directory Structure

```
C:\TradingBots\
├── bots/
│   ├── btc_bot_windows.py           (1H BTC strategy)
│   ├── gold_bot_windows.py          (1H GOLD strategy)
│   └── forex_scalper_windows.py     (15m forex strategy)
├── config/
│   ├── telegram_config_windows.py   (execution mode validation)
│   ├── trade_executor_windows.py    (queue writer)
│   └── __init__.py
├── market_data/
│   ├── market_data_provider_windows.py  (Twelve Data + yfinance)
│   └── __init__.py
├── executor/
│   ├── windows_mt5_executor.py      (MT5 order execution — copy from /windows-mt5-execution/)
│   ├── verify_mt5_connection.py     (connection test)
│   └── verify_symbol_specs.py       (symbol test)
├── scripts/
│   ├── start_all.ps1                (start all bots)
│   ├── stop_all.ps1                 (stop all bots)
│   ├── status_all.ps1               (check status)
│   └── restart_all.ps1              (restart all bots)
├── logs/
│   ├── btc_bot.log
│   ├── gold_bot.log
│   ├── forex_scalper.log
│   └── mt5_executor.log
├── state/
│   ├── .seen_btc                    (seen bars — BTC)
│   ├── .seen_gold                   (seen bars — GOLD)
│   ├── .seen_scalper                (seen bars — FOREX)
│   ├── .trade_queue.jsonl           (signal queue)
│   └── .trade_history.jsonl         (execution history)
├── .env                             (credentials)
├── requirements.txt                 (Python dependencies)
└── README.md                        (this file)
```

---

## Installation

### Step 1: Copy Package to Windows VM

```powershell
# On Windows VM
cd C:\
git clone https://github.com/ajayoberoi1117/medideals-ios-app.git
cd medideals-ios-app
cp -r google-cloud-windows-consolidation C:\TradingBots
cd C:\TradingBots
```

### Step 2: Create Virtual Environment

```powershell
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install --upgrade pip
pip install -r requirements.txt
```

### Step 3: Configure Environment

```powershell
notepad .env
```

**Required environment variables:**

```env
# Telegram Notifications
TELEGRAM_BOT_TOKEN=your_telegram_bot_token
TELEGRAM_CHAT_ID=your_telegram_chat_id

# Data Provider (optional — if Twelve Data API key available)
TWELVE_DATA_KEY=your_twelve_data_api_key

# Execution Mode (default: signal_only — SAFE)
BOT_EXECUTION_MODE=signal_only

# Production Gate (only set to YES if enabling live trading)
LIVE_TRADING_CONFIRMED=

# MT5 Credentials (for executor, if using manual order execution)
MT5_LOGIN=your_vantage_account_number
MT5_PASSWORD=your_password
MT5_SERVER=Vantage-Demo
```

### Step 4: Start Bots

```powershell
cd C:\TradingBots\scripts
.\start_all.ps1
```

---

## Signal Strategies

### BTC Bot (btc_bot_windows.py)

**Market**: BTCUSD (Bitcoin USD)  
**Timeframe**: 1 Hour  
**Strategy**: EMA(9/21) Crossover + RSI(14)  
**Signal Filter**: Daily trend confirmation  
**SL/TP**: 1x ATR / 3x ATR  
**Report**: Daily at 10:00 PM IST  

### GOLD Bot (gold_bot_windows.py)

**Market**: XAUUSD (Gold USD)  
**Timeframe**: 1 Hour  
**Strategy**: EMA(9/21) Crossover + RSI(14)  
**Signal Filter**: Daily trend confirmation (MANDATORY)  
**SL/TP**: 1x ATR / 3x ATR  
**Report**: Daily at 10:00 PM IST  

### Forex Scalper (forex_scalper_windows.py)

**Markets**: EURUSD, GBPUSD  
**Timeframe**: 15 Minutes  
**Strategy**: EMA(9/21) Crossover + RSI(14) + ADX(14)  
**ADX Filter**: ≥20 (trend strength confirmation)  
**1H Trend**: Bullish/bearish confirmation  
**Cooldown**: 30 minutes between signals per pair  
**SL/TP**: 1.5x ATR / 3x ATR  
**Report**: Daily at 10:00 PM IST  
**Weekend**: Skips forex signals (market closed)  

---

## Safety Features

### ✅ Fail-Closed Defaults

- **Default mode**: `signal_only` (NO orders placed)
- **Signals logged**: All signals to `.trade_history.jsonl`
- **Telegram enabled**: Notifications for all signals
- **Safe for unlimited testing**: No account risk in signal-only mode

### ✅ Double-Gate Production Gate

Order execution requires BOTH environment variables set to exact values:

```env
BOT_EXECUTION_MODE=production
LIVE_TRADING_CONFIRMED=YES
```

Missing or incorrect values → orders blocked (fail-closed)

### ✅ DEMO Account Verification

- Windows MT5 executor verifies DEMO account before execution
- Refuses REAL accounts (safety cannot be overridden)
- Stale signals (>5 min old) are skipped
- No credentials logged

### ✅ Duplicate Protection

- **Seen bars tracking**: `.seen_btc`, `.seen_gold`, `.seen_scalper`
- **Cooldown timers**: Forex scalper has 30-min cooldown per pair
- **Signal ID deduplication**: Prevents same bar from generating multiple signals

---

## Operations

### Start All Bots

```powershell
cd C:\TradingBots\scripts
.\start_all.ps1
```

**Expected output:**
```
=== Trading Bots Startup ===
...
✓ BTC Bot started (PID: 1234)
✓ GOLD Bot started (PID: 1235)
✓ Forex Scalper started (PID: 1236)

Started: 3 / 3 bots
✓ All bots started successfully
```

### Check Status

```powershell
.\status_all.ps1
```

**Expected output:**
```
=== Trading Bots Status ===
✓ BTC Bot - RUNNING (PID: 1234)
  Last log: INFO | Bar 2026-08-09 14:00:00 ...

✓ GOLD Bot - RUNNING (PID: 1235)
  Last log: INFO | Bar 2026-08-09 14:00:00 ...

✓ Forex Scalper - RUNNING (PID: 1236)
  Last log: INFO | Bar 2026-08-09 14:00:00 ...

Summary: Running 3 / 3 bots
```

### View Live Logs

```powershell
# BTC Bot
Get-Content C:\TradingBots\logs\btc_bot.log -Tail 50 -Wait

# GOLD Bot
Get-Content C:\TradingBots\logs\gold_bot.log -Tail 50 -Wait

# Forex Scalper
Get-Content C:\TradingBots\logs\forex_scalper.log -Tail 50 -Wait
```

### Stop All Bots

```powershell
.\stop_all.ps1
```

### Restart All Bots

```powershell
.\restart_all.ps1
```

---

## Testing Workflow

### Phase 1: Signal-Only Mode (Safe)

1. **Start bots**
   ```powershell
   .\start_all.ps1
   ```

2. **Monitor signals**
   ```powershell
   Get-Content ..\logs\btc_bot.log -Tail 20 -Wait
   ```

3. **Verify Telegram notifications** (if credentials configured)

4. **Check trade history**
   ```powershell
   Get-Content ..\state\.trade_history.jsonl -Tail 10
   ```

**Expected**: Signals logged to history, NO orders placed, Telegram notifications sent

### Phase 2: Pre-Production Verification

1. **Run MT5 connection test** (if executor available)
   ```powershell
   cd ..\executor
   python verify_mt5_connection.py
   ```

2. **Verify symbol specs**
   ```powershell
   python verify_symbol_specs.py
   ```

3. **Test order preflight** (no actual orders)
   ```powershell
   python verify_order_check.py
   ```

### Phase 3: Production Activation (After Successful Testing)

⚠️ **Only after Phase 1 & 2 are successful:**

1. **Edit .env**
   ```powershell
   notepad ..\.env
   ```
   Set:
   ```env
   BOT_EXECUTION_MODE=production
   LIVE_TRADING_CONFIRMED=YES
   ```

2. **Restart bots**
   ```powershell
   .\restart_all.ps1
   ```

3. **Monitor first 10 signals carefully**
   - Check logs for order submissions
   - Verify orders appear in MT5 account
   - Check trade history for execution results

4. **Verify P&L** in MT5 terminal

---

## Signal Format

**Location**: `C:\TradingBots\state\.trade_queue.jsonl`  
**Format**: JSON-Lines (one JSON object per line)

**Example signal:**
```json
{"symbol": "BTCUSD", "direction": "BUY", "sl": 42500.50, "tp": 44100.25, "source": "BTCUSD_1H", "ts": 1691234567.89}
{"symbol": "XAUUSD", "direction": "SELL", "sl": 2510.75, "tp": 2490.50, "source": "XAUUSD_1H", "ts": 1691234568.12}
{"symbol": "EURUSD", "direction": "BUY", "sl": 1.08200, "tp": 1.09400, "source": "EURUSD_15m", "ts": 1691234569.45}
```

**Fields:**
- `symbol`: BTCUSD, XAUUSD, EURUSD, GBPUSD
- `direction`: BUY or SELL
- `sl`: Stop Loss price
- `tp`: Take Profit price
- `source`: Signal source (timeframe + bot)
- `ts`: Unix timestamp

---

## Trade History

**Location**: `C:\TradingBots\state\.trade_history.jsonl`  
**Purpose**: Audit trail of all signal processing

**Example entries:**
```json
{"signal": {...}, "status": "queued", "timestamp": "2026-08-09T14:30:45"}
{"signal": {...}, "status": "executed", "order_id": "12345", "timestamp": "2026-08-09T14:30:47"}
{"signal": {...}, "status": "rejected", "reason": "stale_signal", "timestamp": "2026-08-09T14:35:00"}
```

---

## Troubleshooting

### Bots not starting

1. **Check Python installation**
   ```powershell
   python --version
   python -c "import pandas; import yfinance; print('OK')"
   ```

2. **Verify .env exists**
   ```powershell
   Test-Path C:\TradingBots\.env
   ```

3. **Check logs**
   ```powershell
   Get-Content C:\TradingBots\logs\btc_bot.log -Tail 30
   ```

### "Module not found" errors

```powershell
cd C:\TradingBots
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt --upgrade
```

### No signals generated

1. **Check market data fetching**
   - Verify internet connectivity
   - Check if market is open for the symbol
   - Verify Twelve Data API key (if using)

2. **Check signal logic**
   - View logs for "Not enough bars" warnings
   - Verify EMA/RSI calculations with chart
   - Check daily trend filter status

3. **Check Telegram credentials** (if notifications expected)
   ```powershell
   notepad .env
   # Verify TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID are valid
   ```

### MT5 executor not reading queue

1. **Verify queue file path**
   ```powershell
   Test-Path C:\TradingBots\state\.trade_queue.jsonl
   ```

2. **Check executor logs**
   ```powershell
   Get-Content C:\TradingBots\logs\mt5_executor.log -Tail 30 -Wait
   ```

3. **Verify MT5 is running** with AutoTrading enabled

### Orders not executing in production mode

1. **Verify both gates are set**
   ```powershell
   Get-Content C:\TradingBots\.env | Select-String "BOT_EXECUTION_MODE|LIVE_TRADING_CONFIRMED"
   ```

2. **Check DEMO account verification**
   ```powershell
   python .\executor\verify_mt5_connection.py
   ```

3. **Review executor logs**
   ```powershell
   Get-Content C:\TradingBots\logs\mt5_executor.log -Tail 50
   ```

---

## Monitoring Checklist

### Daily Health Check

- [ ] All 3 bots running: `.\status_all.ps1`
- [ ] No errors in logs (grep for ERROR): `Select-String -Path logs\* -Pattern "ERROR"`
- [ ] Signals generated today: `Get-Content state\.trade_history.jsonl -Tail 50`
- [ ] Telegram notifications received (if configured)
- [ ] MT5 connection active (if executor running)

### Weekly Review

- [ ] Log file sizes reasonable (auto-rotate if >100MB)
- [ ] No duplicate signals: `Select-String -Path logs\* -Pattern "duplicate"`
- [ ] Telegram delivery working
- [ ] Market data freshness: `Select-String -Path logs\* -Pattern "Fetched.*bars"`

### Monthly Maintenance

- [ ] Archive logs (save before month-end)
- [ ] Review strategy statistics (win rate, P&L)
- [ ] Update credentials if needed
- [ ] Backup state files and configuration

---

## Integration with DigitalOcean (Migration)

**Status**: Parallel deployment (GCP primary, DO backup)

During migration:
- GCP Windows VM: Execute DEMO trades (this package)
- DigitalOcean VM: Remains online (backup) — no order execution

After successful GCP acceptance testing:
- Retire DigitalOcean VM
- GCP remains as primary execution platform

---

## Support

### Quick Reference

| Issue | Solution |
|-------|----------|
| Bots won't start | Run `pip install -r requirements.txt` again |
| No signals | Check logs: `Get-Content logs\btc_bot.log \| Select-Object -Last 30` |
| MT5 connection fails | Run `python executor\verify_mt5_connection.py` |
| Orders not executing | Verify both gate variables in `.env` |
| High CPU usage | Check if bots in infinite loop (stop and restart) |

### Log Locations

```
C:\TradingBots\logs\
├── btc_bot.log
├── gold_bot.log
├── forex_scalper.log
└── mt5_executor.log
```

### Next Steps

1. ✅ Copy package to Windows VM
2. ✅ Setup Python environment
3. ✅ Configure `.env`
4. ✅ Start bots with `start_all.ps1`
5. ✅ Monitor in signal-only mode for 24-48 hours
6. ✅ Test MT5 connection and symbol specs
7. ✅ Enable production mode after validation
8. ✅ Monitor first 10 live trades
9. ✅ Archive logs and verify P&L

---

**Version**: 1.0 (2026-08-09)  
**Status**: Production Ready  
**Account**: Vantage DEMO (safe for testing)  
**Location**: `C:\TradingBots\`
