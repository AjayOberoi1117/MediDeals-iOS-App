# BOT PERFORMANCE MONITORING & AUTO-OPTIMIZATION

**Real-time surveillance system for all trading bots with continuous performance tracking and automated optimization suggestions.**

---

## 📊 Overview

Two complementary tools keep all bots under strict vigilance:

### 1. **BOT MONITOR** (`bot_monitor.py`)
Continuous health surveillance of all running bots.

**What it watches:**
- ✅ Is each bot process running?
- ✅ Is each bot logging activity (within last 5 mins)?
- ✅ Is each bot state file fresh (within last 10 mins)?
- ✅ How many errors in recent logs?
- ✅ Overall health score (0-100)

**Alerts you when:**
- 🔴 Health score drops below 50
- 🔴 Bot process dies unexpectedly
- 🔴 Bot goes silent (no logs in 5 mins)
- 🔴 Error rate spikes

---

### 2. **BOT OPTIMIZER** (`bot_optimizer.py`)
Analyzes trading performance and suggests improvements.

**What it analyzes:**
- 📈 Signal quality over last 7 days
- 📊 Win/loss ratio and P&L
- 🎯 Average entry score confidence
- ⚠️ Risk/reward ratios

**Suggests when:**
- Win rate drops below 40% → Tighten entry filters
- Win rate below 50% → Add volume confirmation
- Risk/reward unfavorable → Increase profit targets
- Signal quality low → Raise confidence threshold

---

## 🚀 Quick Start

### Start Monitoring (Runs continuously)
```bash
# Monitor all bots every 60 seconds (runs forever)
python3 bot_monitor.py

# Output:
# [13:45:23 IST] ─────────────────────
# 🟢 NSE Intraday Scanner    | Health:  95/100 | Running: True | PID: 12345
# 🟢 NIFTY50 Scalper         | Health:  88/100 | Running: True | PID: 12346
# 🟡 Forex Scalper           | Health:  62/100 | Running: True | PID: 12347
# 🔴 Gold/XAUUSD Bot         | Health:  25/100 | Running: False| PID: None
```

### Get Instant Status Summary
```bash
# Print summary of all bots (one-time report)
python3 bot_monitor.py summary

# Output:
# ══════════════════════════════════════════════════════════════════════════
# BOT HEALTH SUMMARY
# ══════════════════════════════════════════════════════════════════════════
#
# NSE Intraday Scanner (PID: 12345)
#   Health Score:  95/100
#   Running:       True
#   Log Fresh:     True (12s ago)
#   State Fresh:   True (35s ago)
#   Errors:        0 errors in last 100 log lines
#
# NIFTY50 Scalper (PID: 12346)
#   Health Score:  88/100
#   ...
```

### Analyze Bot Performance
```bash
# Get optimization suggestions for a specific bot
python3 bot_optimizer.py nifty_scalper

# Output:
# ══════════════════════════════════════════════════════════════════════════
# BOT OPTIMIZATION REPORT: nifty_scalper
# Generated: 2026-08-02 13:45 IST
# ══════════════════════════════════════════════════════════════════════════
#
# 📊 SIGNAL QUALITY (Last 7 days)
# ─────────────────────────────────────────────────────────────────────────
#   Total Signals:     42
#   Average Score:     68.5/100
#   Score Range:       45-95
#
# 📈 WIN RATE ANALYSIS
# ─────────────────────────────────────────────────────────────────────────
#   Total Trades:      42
#   Wins/Losses:       28 / 14
#   Win Rate:          66.7%
#   Total P&L:         ₹18,450
#   Avg Win:           ₹658.93
#   Avg Loss:          -₹317.50
#
# 🔧 OPTIMIZATION SUGGESTIONS
# ─────────────────────────────────────────────────────────────────────────
# ℹ️ [INFO] #1
#   Bot performance is acceptable. Monitor for changes.
```

---

## 📋 Health Score Breakdown

Health scores range from 0-100:

```
100 ──── Perfect
 80 ──── Good (🟢 green)      ← Acceptable
 50 ──── Fair (🟡 yellow)     ← Needs attention
  0 ──── Dead (🔴 red)        ← Critical
```

**Score Penalties:**
- Process not running: -50 points
- Logs older than 5 mins: -20 points
- State file older than 10 mins: -15 points
- High error rate (>5 errors): -20 points

---

## 🔔 Alert Types

### Critical Alerts (🚨 sent to Telegram)
Sent when health score < 50 or process dies.

```
Example:
🚨 BOT ALERT
Bot: NSE Intraday Scanner
Type: CRITICAL
━━━━━━━━━━━━━━━━━━━━
Health score: 35/100
Running: False
Log fresh: False
Error rate: 12 errors in last 100 log lines
━━━━━━━━━━━━━━━━━━━━
Time: 13:45 IST
```

### Optimization Alerts (ℹ️ in reports)
Printed when analysis suggests changes.

```
Optimization Suggestion:
[HIGH] Win rate below 50%
Action: Add volume filter (require 1.5x+ average volume)
Impact:  Expected: +5-10% win rate improvement
```

---

## 📁 Data Storage

All monitoring data saved in `telegram_bot/bot_monitor_data/`:

```
bot_monitor_data/
├── all_bots_status.json      ← Current status of all bots
├── scanner_bot_status.json   ← Scanner bot details
├── nifty_scalper_status.json ← NIFTY scalper details
├── signal_performance.json   ← Overall signal metrics
└── [other bot status files]
```

Each status file is updated every 60 seconds.

---

## 🛠️ Configuration

### Change Monitor Interval
Edit `bot_monitor.py`, line ~190:
```python
monitor_interval = 60  # Change from 60 to 30 for more frequent checks
```

### Add New Bot to Watch
Edit `bot_monitor.py`, line ~20:
```python
BOTS = {
    "scanner_bot": {...},
    "nifty_scalper": {...},
    "your_new_bot": {                    # Add this
        "name": "Your Bot Name",
        "script": "your_bot.py",
        "log": "logs/your_bot.log",
        "db": "paper_trading.db",        # If applicable
    },
}
```

### Change Alert Thresholds
Edit `bot_monitor.py`, line ~145:
```python
if status["health_score"] < 50:  # Change from 50 to 70 for more alerts
    send_alert("CRITICAL", ...)
```

---

## 📊 Typical Workflow

**Every Hour:**
1. Monitor runs continuously, checks health every 60 seconds
2. Any critical issue triggers Telegram alert immediately
3. Summary saved to JSON for quick reference

**Daily (Morning):**
```bash
python3 bot_monitor.py summary
# Review overnight performance
```

**Weekly (Monday Morning):**
```bash
python3 bot_optimizer.py scanner_bot
python3 bot_optimizer.py nifty_scalper
python3 bot_optimizer.py forex_scalper
# Review performance trends and suggestions
```

**On Performance Decline:**
```bash
# Check what's happening
python3 bot_monitor.py summary

# Analyze why win rate dropped
python3 bot_optimizer.py <bot_name>

# Apply suggested improvements to bot code
# Re-deploy bot
```

---

## 🎯 Actions Based on Alerts

### If Health Score = 🔴 Red (< 50)
1. **Run `bot_monitor.py summary`** to diagnose
2. **Check logs** for errors: `tail -50 logs/scanner.log`
3. **Restart bot** if needed: `bash stop_bots.sh && bash start_bots.sh`
4. **Monitor closely** for 5 mins to ensure stability

### If Win Rate = ⚠️ Below 50%
1. **Run optimizer report** to see suggestions
2. **Review suggested code changes** carefully
3. **Test on small sample** if uncertain
4. **Apply highest-impact suggestions first** (CRITICAL, then HIGH)
5. **Backtest changes** if possible before deploying

### If Bot Goes Silent (No Logs)
1. Check if it's outside market hours
2. If during market hours, restart the bot
3. Check logs for errors before restart
4. Verify network connectivity

---

## 📈 Performance Metrics Explained

**Signal Quality:**
- **Average Score**: Higher = more confident signals. Target: >60
- **Score Range**: Shows variation. Wide range = inconsistent quality

**Win Rate:**
- **Target: >55%** (sustainable edge)
- **Below 40%**: Critical, needs filter improvements
- **40-50%**: Needs work, add volume/confirmation filters
- **>55%**: Acceptable, monitor for degradation

**P&L:**
- **Avg Win vs Avg Loss**: Should be >1.5x (risk/reward)
- **Profit Factor**: Total Wins / Total Losses. Target: >1.5

---

## 🔐 Security & Safeguards

**Monitor does NOT:**
- ❌ Modify any bot code automatically
- ❌ Restart bots without your approval
- ❌ Execute trades or place orders
- ❌ Change any parameters

**Monitor ONLY:**
- ✅ Reports on status and performance
- ✅ Suggests improvements (you approve)
- ✅ Alerts on critical issues
- ✅ Logs all data for audit trail

---

## 📞 Troubleshooting

**Monitor shows "Log file not found"**
- Bot hasn't written logs yet
- Ensure bot is actually running
- Check log directory exists: `mkdir -p logs`

**Telegram alerts not arriving**
- Check ELITE_BOT_TOKEN is correct
- Check SIGNAL_CHAT_ID is correct
- Test: `curl https://api.telegram.org/bot{token}/getMe`

**Optimizer shows "Database not found"**
- Ensure `paper_trading.db` exists
- Run at least one trade before analyzing
- Check file path matches

---

## 📝 Example: Complete Daily Routine

```bash
# 9:00 AM IST - Start of market day
# (Monitor should already be running)
python3 bot_monitor.py summary  # Quick health check

# 10:00 AM IST - First signals expected
# (Continue monitoring, alerts come automatically)

# 3:30 PM IST - Market close
# (Bots auto-shutdown at 3:35 PM)

# 4:00 PM IST - End of day review
python3 bot_optimizer.py scanner_bot       # Analyze scanner
python3 bot_optimizer.py nifty_scalper     # Analyze scalper
python3 bot_optimizer.py forex_scalper     # Analyze forex
# Review suggestions, note any patterns

# If changes needed:
# 1. Note which bot and what change
# 2. Edit bot code carefully
# 3. Test changes
# 4. Restart bot
# 5. Monitor closely for 1 hour
# 6. Review next day performance
```

---

## 🚀 Advanced: Custom Analysis

Create custom optimization analysis:

```python
from bot_optimizer import BotOptimizer

optimizer = BotOptimizer("nifty_scalper")
report = optimizer.generate_report()

print(f"Win Rate: {report['win_rate']['win_rate']}")
print(f"Avg Profit: ₹{report['win_rate']['avg_win']:,.2f}")

# Make decisions based on data
if float(report['win_rate']['win_rate'].rstrip('%')) < 50:
    print("⚠️ Win rate below 50% - need adjustments")
```

---

**Status**: ✅ **ACTIVE AND MONITORING**

All bots under continuous surveillance. You have full visibility into performance and automated suggestions for improvement. No changes are applied automatically — all suggestions require your approval.
