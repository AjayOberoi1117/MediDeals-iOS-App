# Signal-Only Watchdog and Startup Infrastructure Review

## Architecture Overview

This document describes the signal-only trading bot infrastructure, which sends trade signals via Telegram but does NOT execute automatic broker orders.

### Core Principle

- **Signal-Only Mode**: Bots detect technical patterns and send alerts to Telegram
- **No Broker Execution**: The `queue_trade()` function has been removed from all signal bots
- **Manual Order Placement**: Traders receive signals and manually place orders on their broker
- **Scanner Protection**: The Nifty 100 equity scanner (`scanner_bot.py`) operates independently in observe-only mode

### Managed Bots (6 Total)

| Symbol | Bot File | Timeframe | Strategy |
|--------|----------|-----------|----------|
| EURUSD | `eurusd_bot.py` | 1 Hour | EMA(9/21) + RSI(14) |
| GBPUSD | `gbpusd_bot.py` | 1 Hour | EMA(9/21) + RSI(14) |
| USDJPY | `usdjpy_bot.py` | 1 Hour | EMA(9/21) + RSI(14) |
| XAUUSD | `gold_bot.py` | 1 Hour | EMA(9/21) + RSI(14) |
| BTCUSD | `btc_bot.py` | 1 Hour | EMA(9/21) + RSI(14) |
| NIFTY | `nifty_scalper.py` | 5 Min | Multi-factor scalper |

### Scanner Bot (Protected Component)

- **Bot File**: `scanner_bot.py`
- **Purpose**: Monitors Nifty 100 equity universe for technical signals
- **Status**: OBSERVE-ONLY (no auto-restart, no signal handling, no state modification)
- **Governance**: Non-negotiable protection — this bot is frozen and may not be restarted by watchdog or startup scripts

## Startup Script (`start_signal_bots.sh`)

### Purpose
Launches the 6 approved signal bots with safety validation.

### Key Features
- **Environment Validation**: Checks `.env` for required variables before starting
- **Existing Process Detection**: Validates running processes and refuses duplicate launches
- **Process Validation**: Checks process ownership, working directory, command line integrity
- **Duplicate Handling**: Reports when processes already exist and skips re-launch
- **Signal-Only Compliance**: Only launches approved bots (no trader.py, MT5Trader, wine, forex_scalper, token_updater)

### Requirements
1. `.env` file must contain:
   - `VANTAGE_EA_TOKEN` (for Forex, Gold bots)
   - `BTC_BOT_TOKEN` (for Crypto bot)
   - `SIGNAL_CHAT_ID` (for all signal receivers)

2. All 6 bot files must exist in the bot directory

3. No existing valid process for each symbol

### Process Validation Checks
- Process ID is running
- Command line contains bot filename
- Executor is python3
- Working directory matches `$SCRIPT_DIR`

### Output
```
========================================
SIGNAL-ONLY BOT STARTUP
========================================
Host: <hostname>
Timestamp: <ISO timestamp>

Validating bot files...
✓ All 6 bot files present

Checking for existing processes...

Starting bots...
✓ EURUSD (eurusd_bot.py) started at PID <pid>
  Log: /path/to/logs/eurusd_bot.log
✓ GBPUSD (gbpusd_bot.py) started at PID <pid>
  Log: /path/to/logs/gbpusd_bot.log
...
```

## Watchdog Script (`watchdog_signal_only.sh`)

### Purpose
Monitors approved bots for crashes and automatically restarts them.

### Key Features
- **Compliance Validation**: Checks no prohibited processes are running
- **Duplicate Detection**: Identifies multiple instances of same bot (alert-only)
- **Process Monitoring**: Detects crashes and triggers auto-restart
- **Environment Validation**: Rejects restart if `.env` is invalid
- **Scanner Observe-Only**: Detects scanner status but never restarts or signals it
- **Finite Cycles**: Runs one cycle per invocation (suitable for cron every N minutes)

### Prohibited Processes
The watchdog validates that these are NOT running:
- `trader.py` (broker execution)
- `MT5Trader` or `MetaTrader` (terminal automation)
- `wine` (Windows emulator for terminal)
- `forex_scalper.py` (deprecated trading engine)
- `token_updater_bot.py` (credential management)
- `mac_trade_writer.py` (OS X order placement)

### Prohibited Files
- `.trade_queue.jsonl` (broker order queue)
- `mt5_signals.csv` (terminal signal file)

### Duplicate Handling
When multiple valid processes exist for a symbol:
- **Action**: Alert to watchdog log only
- **No Termination**: Watchdog never executes `kill`, `pkill`, `killall`, or any process termination command
- **Manual Review Required**: Operator must investigate and manually remove duplicates if needed

### Scanner Monitoring
When scanner_bot.py is detected:
- **Action**: Log observe-only status (no action taken)
- **No Restart**: Watchdog never restarts scanner
- **No Signals**: Watchdog never sends signals to scanner process
- **No File Modification**: Watchdog never modifies scanner logs, state, or configuration

### Restart Procedure
1. Check if bot is running via PID validation
2. If crash detected and `.env` is valid
3. Launch bot via `nohup python3 $bot_file > $log_file 2>&1 &`
4. Wait 1 second
5. Verify process is running
6. Log restart event with new PID

### Output (Watchdog Log)
```
[2026-08-04 12:00:00 UTC] ========== WATCHDOG CYCLE ==========
[2026-08-04 12:00:00 UTC] ALERT: Multiple EURUSD processes detected: 1234 5678
[2026-08-04 12:00:00 UTC] ALERT: GBPUSD is not running
[2026-08-04 12:00:00 UTC] RESTART: GBPUSD (gbpusd_bot.py)
[2026-08-04 12:00:01 UTC] SUCCESS: GBPUSD restarted at PID 9999
[2026-08-04 12:00:01 UTC] OBSERVE: Scanner bot running at PID 5555 (no action)
[2026-08-04 12:00:02 UTC] ========== CYCLE COMPLETE ==========
```

## Test Suite (`test_scripts_signal_only.sh`)

### Purpose
Validates both scripts for correctness and safety before deployment.

### Test Categories

**Static Security Tests**
- No kill/pkill/killall/xargs kill commands
- No trader.py, forex_scalper.py, MT5Trader, wine execution
- No scanner start or restart commands
- No top-level local declarations

**Syntax Tests**
- Both scripts pass `bash -n` syntax validation
- Environment variable handling is correct
- Function definitions are syntactically valid

**Functional Tests**
- Watchdog completes one cycle
- Missing `.env` is rejected safely
- Missing bot files are rejected safely
- All 6 bots are referenced and validated
- Scanner observe-only mode is implemented
- Process validation functions exist
- Duplicate detection without termination works

### Running Tests
```bash
cd /path/to/telegram_bot
bash test_scripts_signal_only.sh
```

### Expected Output
```
TEST RESULTS
Passed: 15
Failed: 0
==========================================
✓ ALL TESTS PASSED
Scripts are safe for deployment.
```

## Log Paths

### Startup Log
- **Location**: Not persisted (stdout/stderr only)
- **Timing**: Generated once per startup

### Watchdog Log
- **Location**: `$SCRIPT_DIR/logs/watchdog.log`
- **Format**: `[ISO timestamp] [LEVEL] message`
- **Retention**: Accumulates indefinitely (suggest daily rotation)

### Bot Logs
- **Location**: `$SCRIPT_DIR/logs/<symbol>_bot.log`
- **Format**: Per-bot logging (see individual bot code)
- **Retention**: Accumulates indefinitely (suggest daily rotation)

## Runtime Paths

All paths are relative to the bot directory:

```
telegram_bot/
├── start_signal_bots.sh         (startup script)
├── watchdog_signal_only.sh      (watchdog script)
├── test_scripts_signal_only.sh  (test suite)
├── .env                         (credentials, not in repo)
├── eurusd_bot.py                (approved bot)
├── gbpusd_bot.py                (approved bot)
├── usdjpy_bot.py                (approved bot)
├── gold_bot.py                  (approved bot)
├── btc_bot.py                   (approved bot)
├── nifty_scalper.py             (approved bot)
├── scanner_bot.py               (protected, observe-only)
├── logs/
│   ├── watchdog.log             (watchdog cycle log)
│   ├── eurusd_bot.log           (bot output)
│   ├── gbpusd_bot.log           (bot output)
│   ├── usdjpy_bot.log           (bot output)
│   ├── gold_bot.log             (bot output)
│   ├── btc_bot.log              (bot output)
│   └── nifty_scalper.log        (bot output)
└── .seen_*                      (bar tracking files)
```

## Deployment Procedures

### Dry-Run (Testing)
```bash
# 1. Create temporary directory with bot files
TEMP_DIR=$(mktemp -d)
cp telegram_bot/*.py "$TEMP_DIR/"
cp telegram_bot/.env "$TEMP_DIR/"
cd "$TEMP_DIR"

# 2. Run startup validation (exit before starting)
bash start_signal_bots.sh --validate

# 3. Run one watchdog cycle
bash watchdog_signal_only.sh --once

# 4. Run test suite
bash test_scripts_signal_only.sh

# 5. Cleanup
rm -rf "$TEMP_DIR"
```

### Production Deployment
```bash
# 1. Copy scripts to production
scp start_signal_bots.sh user@host:/path/to/telegram_bot/
scp watchdog_signal_only.sh user@host:/path/to/telegram_bot/
scp test_scripts_signal_only.sh user@host:/path/to/telegram_bot/

# 2. Make executable
ssh user@host "chmod +x /path/to/telegram_bot/start_signal_bots.sh"
ssh user@host "chmod +x /path/to/telegram_bot/watchdog_signal_only.sh"
ssh user@host "chmod +x /path/to/telegram_bot/test_scripts_signal_only.sh"

# 3. Run test suite on production
ssh user@host "cd /path/to/telegram_bot && bash test_scripts_signal_only.sh"

# 4. Start bots
ssh user@host "cd /path/to/telegram_bot && bash start_signal_bots.sh"

# 5. Configure cron (optional)
ssh user@host "crontab -e"
# Add: */5 * * * * cd /path/to/telegram_bot && bash watchdog_signal_only.sh
```

### Rollback Procedure
```bash
# 1. Stop current bots
ssh user@host "pkill -f 'python3.*_bot.py'"  # User must do this manually

# 2. Restore previous scripts
ssh user@host "cp /path/to/backups/old/start_signal_bots.sh /path/to/telegram_bot/"
ssh user@host "cp /path/to/backups/old/watchdog_signal_only.sh /path/to/telegram_bot/"

# 3. Restart bots with old scripts
ssh user@host "cd /path/to/telegram_bot && bash start_signal_bots.sh"
```

## Known Limitations

1. **No Atomic PID Tracking**: The scripts do not maintain PID files. Process discovery uses `pgrep` with full validation.

2. **No Automatic Process Cleanup**: The watchdog detects duplicates but does NOT terminate them. Manual intervention required if multiple instances exist.

3. **No Graceful Shutdown**: Restarted bots do not signal old instances. They simply start new processes.

4. **Scanner Protection is Hard**: The scanner cannot be restarted or signalled by these scripts, which means if it crashes on production, manual restart is required (no automatic recovery).

5. **Environment is Read Once**: `.env` is read at bot startup. Changes to `.env` require manual bot restart.

6. **Log Rotation Not Implemented**: Watchdog and bot logs accumulate indefinitely. External rotation (via logrotate) is recommended.

7. **No Graceful Signal Delivery**: The watchdog cannot gracefully stop bots. Only hard termination is possible (outside this suite).

## Scanner Protection Proof

The following statements are verified by code inspection:

✓ `start_signal_bots.sh` does NOT start scanner_bot.py
✓ `start_signal_bots.sh` does NOT restart scanner_bot.py
✓ `start_signal_bots.sh` does NOT stop scanner_bot.py
✓ `start_signal_bots.sh` does NOT signal scanner_bot.py
✓ `watchdog_signal_only.sh` contains `monitor_scanner()` that only logs status (no action)
✓ `watchdog_signal_only.sh` does NOT restart scanner_bot.py
✓ `watchdog_signal_only.sh` does NOT kill/pkill/signal scanner_bot.py
✓ `watchdog_signal_only.sh` does NOT modify scanner state files
✓ `watchdog_signal_only.sh` does NOT modify scanner logs
✓ `watchdog_signal_only.sh` OBSERVE_ONLY mode for scanner

## Compliance Checklist

Before deployment, verify:

- [ ] All 6 bot files present and readable
- [ ] `.env` contains all required variables (no values exposed)
- [ ] `start_signal_bots.sh` syntax is valid (`bash -n start_signal_bots.sh`)
- [ ] `watchdog_signal_only.sh` syntax is valid (`bash -n watchdog_signal_bots.sh`)
- [ ] `test_scripts_signal_only.sh` passes all tests
- [ ] No kill/pkill/killall commands in startup or watchdog
- [ ] No broker execution components (trader.py, MT5Trader, wine, etc.)
- [ ] Scanner is protected and never restarted by these scripts
- [ ] Duplicate detection works without terminating processes
- [ ] At least one cycle of watchdog completes successfully

## References

- **Strategy Baseline**: Approved strategy parameters are frozen in each bot file (no dynamic updates)
- **Signal Format**: Telegram messages include Entry, SL, TP, Risk/Reward ratio
- **Manual Order Placement**: Traders are responsible for order entry on their broker
- **Monitoring**: Use `ps aux | grep python3` to check running processes
- **Logs**: Review `logs/watchdog.log` for restart events and alerts

---

**Document Version**: 1.0  
**Last Updated**: 2026-08-04  
**Status**: Signal-Only Infrastructure Approved  
**Scanner Status**: Observe-Only Protected
