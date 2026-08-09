# Google Cloud Windows Trading Stack — Deployment Guide

**Target**: Windows Server 2025 Datacenter  
**Deployment Root**: `C:\TradingBots`  
**Account Type**: Vantage DEMO only  
**Automated Deployment**: `deploy_trading_stack.ps1`

---

## Quick Start

On the Windows VM, run in PowerShell (as Administrator):

```powershell
cd C:\
git clone --branch claude/bots-trade-signals-debug-wjevgt `
  https://github.com/AjayOberoi1117/MediDeals-iOS-App.git

cd MediDeals-iOS-App\google-cloud-windows-consolidation

.\deploy_trading_stack.ps1
```

**Expected time**: 15-30 minutes depending on download speeds and MT5 setup

---

## Deployment Stages

### Stage 1: Windows Baseline
- Verifies Administrator privileges
- Reports system specs (hostname, OS, CPU, RAM, disk)
- Checks internet connectivity
- **Required**: Administrator mode

### Stage 2: Python 3.12
- Installs Python 3.12 x64 (if not present)
- Adds Python and PIP to PATH
- Verifies `python --version` and `python -m pip --version`

**Skip with**: `-SkipPython` (if already installed)

### Stage 3: Git for Windows
- Installs Git 2.43.0 (if not present)
- Adds git.exe to PATH
- Verifies `git --version`

**Skip with**: `-SkipGit` (if already installed)

### Stage 4: MetaTrader 5
- Checks if MT5 is installed at `C:\Program Files\MetaTrader 5\terminal64.exe`
- **If not found**: Script will guide you to manual installation
  - Download from: https://www.metatrader5.com/download
  - Choose **Vantage** as broker (not default)
  - Log in to **Vantage DEMO account** (NOT REAL MONEY)
  - Verify terminal opens successfully
  - Return and rerun script with `-SkipMT5` flag

**Skip with**: `-SkipMT5` (if already installed and running)

### Stage 5: Deploy Source Code
- Clones from GitHub branch: `claude/bots-trade-signals-debug-wjevgt`
- Extracts `google-cloud-windows-consolidation` package
- Copies to `C:\TradingBots`
- Preserves any existing `.env` or state files
- Reports git commit SHA

### Stage 6: Python Virtual Environment
- Creates `.venv` in `C:\TradingBots`
- Installs all dependencies from `requirements-windows.txt`:
  - MetaTrader5>=5.0.35
  - python-dotenv>=1.0.0
  - requests>=2.31.0
  - pandas>=1.5.0
  - pytz>=2023.3
- Verifies imports: MetaTrader5, requests, dotenv, pandas, pytz

### Stage 7: Configuration
- Creates `.env` from `.env.example` (if not already present)
- Lists required variables:
  - `TWELVE_DATA_KEY` (market data API)
  - `TELEGRAM_BOT_TOKEN` (notifications)
  - `TELEGRAM_CHAT_ID` (notifications)
  - `MT5_LOGIN` (Vantage account)
  - `MT5_PASSWORD` (Vantage password)
  - `MT5_SERVER` (Vantage server)
  - `BOT_EXECUTION_MODE` (signal_only or production)
  - `LIVE_TRADING_CONFIRMED` (YES only for production)

**⚠️ CRITICAL**: Edit `.env` with your actual credentials after deployment

### Stage 8: Directories & Queue
- Creates `C:\TradingBots\logs`
- Creates `C:\TradingBots\state`
- Verifies canonical queue path: `C:\TradingBots\state\.trade_queue.jsonl`

### Stage 9: MT5 Verification
- Runs verification scripts:
  - `verify_mt5_connection.py` (connection and account)
  - `verify_symbol_specs.py` (symbol availability)
  - `verify_order_check.py` (order preflight validation)
- Reports: MT5 connection, account type (DEMO/REAL), server, symbols available

### Stage 10: Signal Bots
- Starts BTC Bot (1-hour EURUSD/BTCUSD strategy)
- Starts GOLD Bot (1-hour XAUUSD strategy)
- Starts Forex Scalper (15-minute EUR/GBP scalping)
- Each runs in background Python process
- Prevents duplicates if already running

### Stage 11: MT5 Executor
- Starts Windows MT5 Executor
- Reads trade queue: `C:\TradingBots\state\.trade_queue.jsonl`
- Verifies DEMO account before order placement
- **DEMO safety gate**: Refuses to execute on REAL accounts

### Stage 12: DEMO Order Test
- **Optional**: Use `-DemoTest` flag to test live DEMO order execution
- Requires `BOT_EXECUTION_MODE=production` and `LIVE_TRADING_CONFIRMED=YES` in `.env`
- Places minimum-size order, validates SL/TP
- Default: skipped (signal_only mode)

**Use with**: `.\deploy_trading_stack.ps1 -DemoTest`

### Stage 13: Windows Startup Automation
- Installs Windows Task Scheduler task
- Configures automatic startup at system boot
- Boot sequence: MT5 → bots → executor
- Runs without RDP session required
- Restart policy: 10 retries every 5 minutes

### Stage 14: Health Report
- Runs `health_check.ps1`
- Reports MT5, all bots, executor, queue, Telegram, system resources
- No credential exposure

### Stage 15: DigitalOcean Note
- DigitalOcean deployment preserved as fallback
- Remains running until GCP passes full acceptance test
- No changes made to DO infrastructure

---

## Typical Execution

### First Run (Fresh Installation)

```powershell
# As Administrator in PowerShell
cd C:\MediDeals-iOS-App\google-cloud-windows-consolidation
.\deploy_trading_stack.ps1
```

**Flow**:
1. Stage 1-7: Automated (Python, Git, MT5, source, venv, config)
2. Pauses at Stage 4 if MT5 not installed (manual install required)
3. Resumes after MT5 install: `.\deploy_trading_stack.ps1 -SkipPython -SkipGit -SkipMT5`
4. Stages 8-15: Verification, bots, executor, automation

### Subsequent Runs (Configuration Changes)

If you update `.env` or restart, just run:

```powershell
.\deploy_trading_stack.ps1 -SkipPython -SkipGit -SkipMT5
```

This skips installations and goes straight to deployment.

### Health Check Only

To check current status without restarting:

```powershell
.\deploy_trading_stack.ps1 -HealthOnly
```

Or directly:

```powershell
.\scripts\health_check.ps1
```

---

## Configuration: .env

After deployment, **you must edit** `C:\TradingBots\.env` with your credentials.

**Template** (do not commit this file):

```bash
# MetaTrader5 Credentials (Vantage DEMO account)
MT5_LOGIN=your_vantage_demo_login
MT5_PASSWORD=your_vantage_password
MT5_SERVER=your_vantage_server

# Telegram (for trade confirmations)
TELEGRAM_BOT_TOKEN=your_telegram_bot_token
TELEGRAM_CHAT_ID=your_telegram_chat_id

# Market Data
TWELVE_DATA_KEY=your_twelve_data_api_key

# Execution Mode (SAFETY DEFAULT: signal_only)
BOT_EXECUTION_MODE=signal_only

# Live Trading Confirmation (ONLY required if BOT_EXECUTION_MODE=production)
LIVE_TRADING_CONFIRMED=
```

**DO NOT**:
- Commit `.env` to Git
- Print secrets in logs
- Provide credentials in public channels
- Use REAL Vantage account credentials

---

## Verification Checklist

After deployment, verify each component:

### MT5
```powershell
python .\executor\verify_mt5_connection.py
python .\executor\verify_symbol_specs.py
python .\executor\verify_order_check.py
```

Expected: Connection OK, DEMO account verified, symbols available

### Bots
```powershell
Get-Process python | Where-Object {$_.CommandLine -like "*bot*"}
```

Expected: 3 processes running (btc, gold, forex)

### Executor
```powershell
Get-Process python | Where-Object {$_.CommandLine -like "*executor*"}
```

Expected: 1 process running

### Queue
```powershell
Get-Content .\state\.trade_queue.jsonl | Measure-Object -Line
```

Expected: 0 or more signals in queue

### Logs
```powershell
Get-Content .\logs\*.log -Wait
```

Expected: Real-time log output from all components

### Health
```powershell
.\scripts\health_check.ps1
```

Expected: Green checkmarks for MT5, bots, executor, queue

---

## Troubleshooting

### Python Not Installing

```powershell
# Manual install with PATH update
.\deploy_trading_stack.ps1 -SkipGit -SkipMT5
```

### Git Not Installing

```powershell
# Skip Git installation, use manual installation or WSL git
.\deploy_trading_stack.ps1 -SkipPython -SkipMT5
```

### MT5 Not Found

```powershell
# Pause for manual MT5 install
.\deploy_trading_stack.ps1 -SkipPython -SkipGit -SkipMT5
```

Or install manually:
1. Download: https://www.metatrader5.com/download
2. Run installer
3. Choose Vantage broker
4. Log in to DEMO account
5. Rerun script

### Dependencies Not Installing

Check pip log:
```powershell
Get-Content .\logs\pip-install.log
```

Try manual install:
```powershell
.\\.venv\Scripts\pip install -r requirements-windows.txt --upgrade
```

### Bots Not Starting

Check logs:
```powershell
Get-Content .\logs\btc_bot.log -Tail 20
Get-Content .\logs\gold_bot.log -Tail 20
Get-Content .\logs\forex_scalper.log -Tail 20
```

Common issues:
- Missing `.env` variables
- Twelve Data API key invalid
- MT5 not running or initialized
- Market data provider offline

### Executor Not Starting

Check log:
```powershell
Get-Content .\logs\mt5_executor.log -Tail 50
```

Common issues:
- REAL account detected (DEMO gate rejected)
- MT5 not initialized
- Queue file permission denied
- Signal format invalid

### Task Scheduler Not Working

Verify installation:
```powershell
Get-ScheduledTask -TaskName "TradingStack-AutoStart" -TaskPath "\TradingBots\"
```

Reinstall:
```powershell
.\scripts\install_scheduled_tasks.ps1 -Uninstall
.\scripts\install_scheduled_tasks.ps1
```

---

## File Structure

After deployment, expect:

```
C:\TradingBots\
├── .env                                    (user provides - NOT in repo)
├── .env.example                            (template)
├── requirements-windows.txt                (dependencies)
├── README.md                               (full documentation)
├── DEPLOYMENT_CHECKLIST.md                 (detailed checklist)
├── deploy_trading_stack.ps1                (deployment automation)
│
├── bots/
│   ├── btc_bot_windows.py
│   ├── gold_bot_windows.py
│   ├── forex_scalper_windows.py
│   └── __init__.py
│
├── config/
│   ├── telegram_config_windows.py
│   ├── trade_executor_windows.py
│   └── __init__.py
│
├── market_data/
│   ├── market_data_provider_windows.py
│   └── __init__.py
│
├── executor/
│   ├── windows_mt5_executor.py
│   ├── discover_symbols.py
│   ├── verify_mt5_connection.py
│   ├── verify_symbol_specs.py
│   ├── verify_order_check.py
│   └── __init__.py
│
├── scripts/
│   ├── startup_with_executor.ps1
│   ├── install_scheduled_tasks.ps1
│   ├── health_check.ps1
│   ├── start_all.ps1
│   ├── stop_all.ps1
│   ├── status_all.ps1
│   └── restart_all.ps1
│
├── logs/
│   ├── btc_bot.log
│   ├── gold_bot.log
│   ├── forex_scalper.log
│   ├── mt5_executor.log
│   ├── deployment.log
│   └── pip-install.log
│
└── state/
    ├── .seen_btc
    ├── .seen_gold
    ├── .seen_scalper
    ├── .trade_queue.jsonl
    └── .trade_history.jsonl
```

---

## Command Reference

### Deployment
```powershell
# Full deployment (all stages)
.\deploy_trading_stack.ps1

# Skip Python/Git/MT5 if already installed
.\deploy_trading_stack.ps1 -SkipPython -SkipGit -SkipMT5

# Health check only
.\deploy_trading_stack.ps1 -HealthOnly

# DEMO order test (requires production .env)
.\deploy_trading_stack.ps1 -DemoTest
```

### Operations
```powershell
# Start all bots + executor
.\scripts\startup_with_executor.ps1

# Stop all bots + executor
.\scripts\stop_all.ps1

# Check status
.\scripts\status_all.ps1

# Restart gracefully
.\scripts\restart_all.ps1

# Health report
.\scripts\health_check.ps1

# View live logs
Get-Content .\logs\*.log -Wait
```

### Windows Task Scheduler
```powershell
# Install auto-startup task
.\scripts\install_scheduled_tasks.ps1

# List installed task
.\scripts\install_scheduled_tasks.ps1 -List

# Uninstall task
.\scripts\install_scheduled_tasks.ps1 -Uninstall
```

### Manual Verification
```powershell
# Test MT5 connection
python .\executor\verify_mt5_connection.py

# Test symbol specs
python .\executor\verify_symbol_specs.py

# Test order preflight
python .\executor\verify_order_check.py

# Discover Vantage symbols
python .\executor\discover_symbols.py
```

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│          Vantage MetaTrader 5 (DEMO Account)        │
└────────────────────────┬────────────────────────────┘
                         │
                    (mt5 API)
                         │
        ┌────────────────┴────────────────┐
        │                                 │
   ┌────▼────┐                    ┌──────▼─────┐
   │ BTC Bot │                    │  Executor  │
   │ (1H)    │─┐              ┌───│ (MT5 send) │
   └─────────┘ │              │   └────────────┘
               │              │
   ┌────────┐  │  .trade_queue.jsonl  │
   │GOLD Bot├──┤  (local signal queue)├───┐
   │ (1H)   │  │              │         │
   └────────┘  │              │         │
               │              │         │
   ┌─────────────┐            │   ┌─────▼──────┐
   │Forex Scalper├────────────┘   │ .trade_    │
   │ (15m)       │                │ history.   │
   └─────────────┘                │ jsonl      │
                                  └────────────┘
        ▲                 ▲
        │                 │
   ┌────┴─────┐      ┌────┴──────┐
   │Twelve Data│      │ Telegram  │
   │ API       │      │ Notifications
   └──────────┘      └───────────┘
```

---

## Safety & Security

### DEMO Account Mandatory
- Script enforces DEMO-only via `account.trade_mode == 0` check
- Executor refuses REAL accounts (fail-closed)
- No pathway to production without explicit `.env` configuration

### Double-Gate Production
- `BOT_EXECUTION_MODE=production` + `LIVE_TRADING_CONFIRMED=YES` required
- Default: `signal_only` (no orders placed)
- Prevents accidental live trading

### No Secrets in Logs
- Credentials loaded from `.env` (not in code)
- Health check masks token/chat ID
- Logs never print passwords or account numbers

### Preserved DigitalOcean
- Windows deployment does NOT modify DO
- Both environments can run in parallel
- Fall back to DO if GCP fails

---

## Next Steps After Deployment

1. **Edit `.env`** with your Vantage DEMO, Telegram, and Twelve Data credentials
2. **Verify components** with `.\scripts\health_check.ps1`
3. **Monitor logs** with `Get-Content .\logs\*.log -Wait`
4. **Test DEMO order** (optional) with `.\deploy_trading_stack.ps1 -DemoTest`
5. **Enable auto-startup** with `.\scripts\install_scheduled_tasks.ps1`
6. **Test reboot** to verify Task Scheduler works
7. **Establish parity** between GCP and DigitalOcean
8. **Parallel monitoring** for 24-48 hours before retiring DO

---

## Support

Check logs for errors:
```powershell
Get-Content .\logs\deployment.log        # Deployment stage output
Get-Content .\logs\btc_bot.log           # BTC bot runtime
Get-Content .\logs\gold_bot.log          # GOLD bot runtime
Get-Content .\logs\forex_scalper.log     # Forex bot runtime
Get-Content .\logs\mt5_executor.log      # Executor runtime
Get-Content .\logs\pip-install.log       # Python dependency install
```

---

**Ready to deploy? Run:**
```powershell
.\deploy_trading_stack.ps1
```

---

**Repository**: AjayOberoi1117/MediDeals-iOS-App  
**Branch**: claude/bots-trade-signals-debug-wjevgt  
**Package**: google-cloud-windows-consolidation  
**Deployment Target**: C:\TradingBots (Windows Server 2025)
