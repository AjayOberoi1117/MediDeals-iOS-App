# Trading Bot Operations Engineer V2

Professional monitoring, health checking, and reporting system for the Indian Equity Trading Bot.

## Architecture

```
ops/
├── signal_ledger.py          # SQLite database for all signals
├── process_manager.py        # Start/stop/restart/status for bot
├── health_monitor.py         # Pre-market, intraday, EOD checks
├── report_generator.py       # Intraday, weekly, monthly reports
├── market_calendar.py        # NSE trading day detection
├── premarket_check.py        # Runs at 8:45 AM IST (Mon-Fri)
├── eod_report.py            # Runs at 3:45 PM IST (Mon-Fri)
├── mac_install.sh           # Installation script (run on Mac)
├── mac_status.sh            # Check system status (run on Mac)
├── mac_uninstall.sh         # Disable and remove monitoring
├── test_operations.py       # Unit tests
└── reports/                 # Generated reports directory
```

## Key Directories (Mac)

| Component | Location |
|-----------|----------|
| Signal Database | `~/Library/Application Support/AjayTradingBot/signals.db` |
| Logs | `~/Library/Logs/ajay-trading-bot/` |
| LaunchAgents | `~/Library/LaunchAgents/com.ajay.tradingbot*.plist` |
| Repository | `/Users/ajayoberoi/MediDeals-iOS-App` |

## Installation (Mac)

### Prerequisites

- macOS 10.13 or later (launchd support)
- Python 3.11+
- Bash shell
- `sqlite3` command-line tool

### Step 1: Copy this ops/ directory to the repository

The ops/ directory should be in `/Users/ajayoberoi/MediDeals-iOS-App/ops/`

### Step 2: Run the installation script

```bash
bash /Users/ajayoberoi/MediDeals-iOS-App/ops/mac_install.sh
```

This will:
1. Validate plist files
2. Create required directories
3. Install LaunchAgents
4. Enable automatic scheduling

### Step 3: Verify installation

```bash
bash /Users/ajayoberoi/MediDeals-iOS-App/ops/mac_status.sh
```

You should see all LaunchAgents loaded and running.

## Monitoring Schedule

All times in **Asia/Kolkata (IST)**

| Time | Check | Frequency | Action |
|------|-------|-----------|--------|
| 08:45 | Pre-Market | Daily (Mon-Fri) | Verify bot is ready, auto-restart if needed |
| During Market | Intraday | Every 30 min | (Built into bot) |
| 15:45 | End-of-Day | Daily (Mon-Fri) | Generate reports, send Telegram summary |
| 17:00 | Weekly | Fridays | Generate weekly performance report |
| EOD | Monthly | Last trading day | Generate monthly performance report |

## Usage

### Check Bot Status

```bash
python3 /Users/ajayoberoi/MediDeals-iOS-App/ops/process_manager.py status
```

### Manually Start Bot

```bash
python3 /Users/ajayoberoi/MediDeals-iOS-App/ops/process_manager.py start
```

### Manually Stop Bot

```bash
python3 /Users/ajayoberoi/MediDeals-iOS-App/ops/process_manager.py stop
```

### Manually Restart Bot

```bash
python3 /Users/ajayoberoi/MediDeals-iOS-App/ops/process_manager.py restart
```

### Run Health Check

```bash
python3 /Users/ajayoberoi/MediDeals-iOS-App/ops/health_monitor.py
```

### Generate Today's Report

```bash
python3 /Users/ajayoberoi/MediDeals-iOS-App/ops/eod_report.py
```

### Check Monitoring System Status

```bash
bash /Users/ajayoberoi/MediDeals-iOS-App/ops/mac_status.sh
```

## Signal Ledger (Database)

All signals are recorded in SQLite at:
`~/Library/Application Support/AjayTradingBot/signals.db`

### Query Signal Statistics

```bash
sqlite3 ~/Library/Application\ Support/AjayTradingBot/signals.db
sqlite> SELECT confidence, COUNT(*) FROM signals GROUP BY confidence;
sqlite> SELECT * FROM signals WHERE DATE(timestamp) = '2026-07-31';
sqlite> .quit
```

### Tracked Fields Per Signal

- Signal ID, Timestamp, Symbol, Direction (BUY/SELL)
- Confidence Tier (HIGH/MEDIUM/LOW), Score
- Entry Price, Stop Loss, Target Prices
- Quantity, Strategy Code, Timeframe
- RSI, EMA values, Volume Ratio
- Telegram Delivery Status
- Price snapshots at 15/30/60/120 min & EOD
- Max Favorable/Adverse Excursion
- Final Status (Win/Loss/Unresolved)

## Reports

Generated reports are saved to: `/Users/ajayoberoi/MediDeals-iOS-App/ops/reports/`

Each report includes:
- Date-stamped filename
- Performance statistics by confidence level
- Signal count and resolution status
- Win/loss analysis
- Recommendations for next period

## Health Checks

The system automatically detects and reports:

- **Process Health**: Is bot running? PID valid? Uptime?
- **Log Freshness**: Has bot written logs recently?
- **Log Content**: Any errors or exceptions?
- **Market Data**: Is Upstox API working? Data fresh?
- **Telegram**: Are signals being delivered?

### Auto-Remediation

The system will **automatically**:
- Restart a dead bot during pre-market check
- Rotate oversized logs
- Clear stale PID files
- Record all issues in logs

The system will **NOT autonomously**:
- Change strategy settings
- Execute trades
- Modify signal thresholds
- Push to Git
- Deploy code

## Telegram Notifications

The system sends Telegram messages **only** for important events:

✓ Bot stopped unexpectedly
✓ Restart succeeded or failed
✓ Stale market data detected
✓ Telegram delivery failure
✓ Repeated exceptions
✓ Qualified signals being dropped
✓ End-of-day summary
✓ Strategy proposal awaiting approval

✗ Routine healthy checkpoint messages (go to logs only)
✗ Test messages (see mac_status.sh instead)

## Mac Sleep / Power Off Limitation

**Important**: This monitoring system cannot run while your Mac is:
- Powered off
- Asleep (unless "Wake for network access" is enabled in System Preferences)

**Solution**: Keep your Mac powered on and awake during market hours (9:15 AM - 3:30 PM IST).

## Troubleshooting

### LaunchAgent not running

Check if it's loaded:
```bash
launchctl list | grep com.ajay.tradingbot
```

Reload it:
```bash
launchctl bootout "gui/$(id -u)" ~/Library/LaunchAgents/com.ajay.tradingbot.premarket.plist
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.ajay.tradingbot.premarket.plist
```

### Check LaunchAgent logs

```bash
log stream --predicate 'process == "python3"' --level debug
```

### Bot not starting

Check logs:
```bash
tail -50 ~/Library/Logs/ajay-trading-bot/*.log
```

Verify Python path:
```bash
which python3
/usr/bin/env python3 --version
```

### Database locked errors

Wait a moment for locks to clear. If persistent:
```bash
sqlite3 ~/Library/Application\ Support/AjayTradingBot/signals.db ".timeout 10000"
```

## Disabling Monitoring

To stop the automated monitoring **without removing it**:

```bash
bash /Users/ajayoberoi/MediDeals-iOS-App/ops/mac_uninstall.sh
```

Your data is **completely preserved**:
- Signal database remains at `~/Library/Application Support/AjayTradingBot/`
- All logs remain at `~/Library/Logs/ajay-trading-bot/`

To re-enable:
```bash
bash /Users/ajayoberoi/MediDeals-iOS-App/ops/mac_install.sh
```

## Running Tests

```bash
cd /Users/ajayoberoi/MediDeals-iOS-App/ops
python3 -m pytest test_operations.py -v
```

Or with unittest:
```bash
python3 test_operations.py
```

## Version History

- **V2.0** (2026-07-31): Full operations monitoring, health checks, signal ledger, reporting

## Support

For issues or questions:
1. Check logs in `~/Library/Logs/ajay-trading-bot/`
2. Run health check: `python3 /Users/ajayoberoi/MediDeals-iOS-App/ops/health_monitor.py`
3. Review recent reports in `ops/reports/`

---

**Important**: This system monitors and reports on bot health. It does NOT:
- Execute trades
- Modify strategy settings without approval
- Push code to Git
- Deploy changes
- Expose secrets in logs

All monitoring is local to your Mac.
