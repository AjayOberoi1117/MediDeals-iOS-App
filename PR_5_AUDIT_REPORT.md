# PR #5 AUDIT REPORT
## NSE Scanner Bot & Monitoring System

**Date:** 2026-08-02  
**Audit Type:** Evidence-Based Verification  
**Standard:** Claims require evidence. No marketing language. No estimates without data.

---

## ⚠️ CRITICAL FINDING

**Previous claim:** "Strict Bot Surveillance System Deployed"

**Actual status:** Code exists in repository. NOT deployed to production server.

❌ No systemd service running  
❌ No process IDs active  
❌ No server uptime to report  
❌ No production monitoring active  

---

# SECTION 1: VERIFIED (Evidence-Based)

## 1.1 Scanner Bot Code Changes — VERIFIED

**Location:** `telegram_bot/scanner_bot.py`

**Verified Changes:**

### Weekend/Holiday Blocking
```python
def verify_weekend_safety():
    if now_ist.weekday() >= 5:  # Saturday=5, Sunday=6
        return False
```
✅ Code exists and is syntactically correct  
✅ Tests run: `python3 -c "from datetime import datetime; import pytz; IST = pytz.timezone('Asia/Kolkata'); now = datetime.now(IST); print(now.weekday() >= 5)"`  
✅ Result on Sunday 2026-08-02: `True` (weekend correctly detected)

### 4-Layer Safety Implementation
```python
Layer 1: verify_weekend_safety() in main()        # Lines 234-246
Layer 2: verify_weekend_safety() in while loop    # Lines 258-262
Layer 3: Internal check in run_scan()             # Lines 422-429
Layer 4: Final check in notify()                  # Lines 220-233
```
✅ All 4 layers present in code  
✅ Each layer independently blocks on weekends

### Earnings Calendar
```python
EARNINGS_CALENDAR = {
    "TCS": [datetime(2026, 4, 15).date(), ...],
    "RELIANCE": [datetime(2026, 4, 20).date(), ...],
    # ... 5 major stocks configured
}
```
✅ Dictionary structure correct  
✅ 5 stocks with quarterly dates populated  
✅ check_earnings_within_days() function present

### Signal Criteria Changes
```python
# Old: if (bullish_cross or ema_bounce_buy) and 45 <= c_rsi <= 68:
# New: if (bullish_cross or ema_bounce_buy) and 50 <= c_rsi <= 65:
```
✅ RSI range tightened from 45-68 to 50-65  
✅ Change verified at line 373

### Scan Start Time
```python
# Old: if now_ist.hour < 10:
# New: if now_ist.hour < 9 or (now_ist.hour == 9 and now_ist.minute < 35):
```
✅ Scan start moved from 10:00 AM to 9:35 AM  
✅ Logic verified at line 420

### 2-Hour Symbol Cooldown
```python
symbols_alerted = {}  # Changed from list to dict
# Old: if symbol in state["symbols_alerted"]: continue
# New: if symbol in state["symbols_alerted"]:
#          if now_timestamp - state["symbols_alerted"][symbol] < cooldown_seconds:
```
✅ Structure changed from list to timestamp dict  
✅ Cooldown logic present at lines 438-440

---

## 1.2 Data Source — VERIFIED

**Claim:** Switched from Yahoo Finance to Upstox API

**Evidence:**
```python
# Line 235 in fetch_candles():
url = f"https://api.upstox.com/v2/historical-candle/{key_enc}/15minute/{to_date}/{from_date}"
```
✅ Upstox 15-minute endpoint present  
✅ Previous daily endpoint removed  
✅ LOOKBACK_DAYS changed 120 → 5 (appropriate for 15-min data)

**Limitation:** This change has NOT been tested against live Upstox API in current environment (network restricted). Code change verified; execution not verified.

---

## 1.3 Monitoring System Code — VERIFIED

**Location:** `telegram_bot/bot_monitor.py` (477 lines)

**Code Structure Verified:**
- ✅ BotHealthCheck class present
- ✅ check_process_running() method present
- ✅ check_log_recent() method present
- ✅ check_error_rate() method present
- ✅ Health score calculation present

**Limitations:**
- ⚠️ Code depends on psutil library (not verified if installed)
- ⚠️ Telegram alerts depend on network (may fail in restricted environment)
- ⚠️ Monitored bots hardcoded in BOTS dict

---

## 1.4 Optimizer System Code — VERIFIED

**Location:** `telegram_bot/bot_optimizer.py` (231 lines)

**Code Structure Verified:**
- ✅ BotOptimizer class present
- ✅ analyze_signal_quality() method present
- ✅ analyze_win_rate() method present
- ✅ get_optimization_suggestions() method present

**Critical Issue Found:**
SQL queries in lines 107-123 reference table `paper_trades`:
```python
cursor.execute("""
    SELECT COUNT(*),
           AVG(score),
    FROM paper_trades
    WHERE entry_time > ? AND bot_name = ?
""", (date_cutoff, self.bot_name))
```

❌ Table `paper_trades` existence NOT verified  
❌ Column names (entry_time, score, bot_name, profit_loss) NOT verified  
❌ If table doesn't exist, optimizer will crash with SQL error

---

## 1.5 Commits — VERIFIED

PR #5 contains 5 commits:
1. `0b0b176` - Switch to Upstox 15-minute data
2. `f569d64` - Fix signal flooding/silence
3. `5e803bd` - Add 4-layer weekend/holiday safety
4. `0458d0a` - Add earnings calendar detection
5. `0b33645` - Add monitoring and optimization system

✅ All commits present in repository  
✅ Commit messages document changes  
✅ Code changes match commit descriptions

---

# SECTION 2: NOT YET VERIFIED (Requires Evidence)

## 2.1 Deployment Status — NOT VERIFIED

**Claimed:** "Strict Bot Surveillance System Deployed"

**Required Evidence (Not Provided):**
- [ ] Server path where monitor runs
- [ ] systemd service file
- [ ] Process ID of running monitor
- [ ] Service status output
- [ ] Uptime duration
- [ ] Log file location on server

**Current Status:** Monitor code exists but is NOT running on any production server.

**Correct Statement:** "Monitoring system implemented in repository. Not yet deployed."

---

## 2.2 Bot Coverage — NOT VERIFIED

**Claimed:** Monitoring "all bots"

**Hardcoded in bot_monitor.py (lines 23-36):**
```python
BOTS = {
    "scanner_bot": {...},
    "nifty_scalper": {...},
    "forex_scalper": {...},
    "gold_bot": {...},
    "token_updater": {...},
}
```

**Question:** Are these ALL bots in the repository?

**Required:** Audit of repository to list all `.py` files in `telegram_bot/` that are actual trading bots.

**Current:** Only 5 bots hardcoded. Unknown if others exist.

---

## 2.3 Database Schema — NOT VERIFIED

**Claimed:** Optimizer calculates "win rate," "average profit," etc.

**Problem:** SQL queries depend on table schema that was NOT verified.

**Required Evidence (Not Provided):**
```sql
-- Does this table exist?
DESCRIBE paper_trades;

-- Expected columns:
-- entry_time      (DATETIME)
-- exit_time       (DATETIME)
-- bot_name        (VARCHAR)
-- symbol          (VARCHAR)
-- profit_loss     (FLOAT)
-- score           (INT)
-- confidence      (VARCHAR)
```

**Current Status:** Unknown. If table doesn't exist or columns differ, optimizer crashes.

---

## 2.4 Health Score Calculation — NOT VERIFIED

**Claimed:** "Overall health score (0-100)"

**Code Present:** `calculate_health_score()` function at line 176-189

**Formula (from code):**
```python
score = 100
if not running: score -= 50
if not log_fresh: score -= 20
if not state_fresh: score -= 15
if errors > 5: score -= min(20, errors * 2)
return max(0, score)
```

**Questions Not Answered:**
- What if process is running but log is old? (40 points)
- What happens for bots without state files? (-15 for no reason?)
- Is this the right weighting? No justification provided.
- Has this been tested against actual bot scenarios?

**Current Status:** Logic exists but weights are arbitrary. Not validated against real bot behavior.

---

## 2.5 Alert Prevention — NOT VERIFIED

**Claimed:** Alerts sent for critical issues

**Code Present:** `send_alert()` function at line 154-166

**Critical Missing Feature:**
```python
# Current code:
if status["health_score"] < 50:
    send_alert("CRITICAL", ...)

# Problem: No duplicate prevention
# If bot stays unhealthy, alert sent EVERY 60 SECONDS
# Result: 60+ identical alerts per hour to Telegram
```

**Current Status:** Alert spam is possible. No cooldown, no deduplication.

**Required Fix:**
```python
# Check if alert was sent recently for this bot
last_alert_time = load_last_alert_time(bot_key)
if now - last_alert_time > 3600:  # Only alert once per hour
    send_alert(...)
    save_last_alert_time(bot_key)
```

---

## 2.6 Historical Data Retention — NOT VERIFIED

**Claimed:** "Full audit trail" of performance metrics

**Current Implementation:**
```python
# bot_monitor.py line ~260
with open(collective_file, 'w') as f:
    json.dump(all_statuses, f, indent=2)
```

**Problem:** Each status file is OVERWRITTEN every 60 seconds.

**What exists:** Only the latest snapshot (current status)  
**What is missing:** Historical data beyond 60 seconds

**Current Status:** Latest snapshot only. NOT an audit trail.

**Required to create audit trail:**
```python
# Append to historical file instead of overwriting
with open(f"history_{timestamp}.json", 'a') as f:
    json.dump(all_statuses, f)  # Append, don't overwrite
```

---

## 2.7 Performance Projections — NOT VERIFIED

**Claimed in code comments:**
- "Expected: +20% win rate improvement"
- "Expected: +5-10% improvement"
- "Higher conviction"

**Evidence Provided:** None

**Issue:** These are marketing projections, not measured results.

**Current Status:** Suggestions generated but never validated against actual performance.

**Required Before Claiming Success:**
1. Run suggestion on test bot for 30 days
2. Compare before/after win rates
3. Measure actual improvement
4. Document with data

---

## 2.8 Production Readiness — NOT VERIFIED

**Claimed:** System is ready for use

**Dependencies Not Checked:**
- ❓ Is psutil installed? (Required by bot_monitor.py)
- ❓ Do numpy/pandas exist? (May be required by scalper bots)
- ❓ Is Telegram API accessible? (Network restricted in this environment)
- ❓ Does Upstox API actually return 15-minute data? (Not tested)

**Current Status:** Code written but dependencies and network access not verified in production environment.

---

## 2.9 Earnings Calendar Accuracy — NOT VERIFIED

**Claim:** Earnings dates for major stocks configured

**Evidence Provided:**
```python
"TCS": [datetime(2026, 4, 15).date(), ...]  # Claimed Q4 FY26 results
```

**Questions:**
- Are these actual TCS earnings dates or estimates?
- Does April 15 actually match TCS's FY26 Q4 results date?
- Who verified these dates?

**Current Status:** Dates appear reasonable but not validated against NSE announcements or company calendars.

---

# SECTION 3: ISSUES FOUND

## 3.1 Alert Spam Risk

**Severity:** HIGH  
**Location:** bot_monitor.py, send_alert() function  
**Issue:** No duplicate prevention — same alert sent every 60 seconds if problem persists

**Impact:** User would receive 1,440 identical Telegram alerts per day if bot stays unhealthy for 24 hours.

---

## 3.2 Database Schema Mismatch Risk

**Severity:** HIGH  
**Location:** bot_optimizer.py, analyze_win_rate() and analyze_signal_quality()  
**Issue:** SQL queries assume `paper_trades` table with specific columns; schema never verified

**Impact:** Optimizer will crash at runtime if table doesn't exist or columns are named differently.

---

## 3.3 No Historical Data Retention

**Severity:** MEDIUM  
**Location:** bot_monitor.py  
**Issue:** Status files overwritten every 60 seconds; no historical trend data

**Impact:** Cannot track performance over time. No way to detect gradual degradation.

---

## 3.4 Arbitrary Health Score Weights

**Severity:** MEDIUM  
**Location:** bot_monitor.py, calculate_health_score()  
**Issue:** Weights assigned without justification:
- Process not running: -50 (vs -20 for stale logs?)
- Stale logs: -20
- Stale state: -15
- High errors: -20

**Impact:** Health scores may not reflect actual severity of issues. Bot could be marked healthy while having real problems.

---

# SECTION 4: RECOMMENDATION

## What Works
✅ Scanner bot code changes are sound (weekend blocking, earnings detection, RSI tightening)  
✅ Monitoring system architecture is reasonable  
✅ All code is syntactically correct and present in repository

## What Doesn't Work Yet
❌ Monitor is not deployed or running  
❌ Optimizer requires database schema verification  
❌ Alert system will spam on repeated failures  
❌ No historical metrics retained  
❌ Earnings dates not validated  
❌ Health score weights unjustified

## Required Before Production Use

### Immediate (Blocking)
1. **Verify database schema** — Check if `paper_trades` table exists with required columns
2. **Add alert deduplication** — Prevent alert spam with cooldown logic
3. **Test Upstox API integration** — Confirm 15-minute data fetch works
4. **Add historical data retention** — Save snapshots instead of overwriting

### Before Deployment
1. **Deploy monitor as systemd service** — Run as background process with auto-restart
2. **Test on actual bots** — Run monitor for 7 days, collect real data
3. **Validate health score formula** — Adjust weights based on real bot scenarios
4. **Verify earnings calendar** — Confirm dates against NSE announcements

### Nice to Have
1. Add database migration script for paper_trades table
2. Create dashboard to visualize health over time
3. Document alert threshold configuration
4. Add metrics export (Prometheus, CloudWatch, etc.)

---

# FINAL STATEMENT

This audit separates implementation quality from deployment reality:

**Quality of code:** ✅ Good (well-structured, multi-layer safety, comprehensive)  
**Status of deployment:** ❌ Not deployed (in repository, not running)  
**Readiness for production:** ⚠️ Requires fixes before use

Do not use the word "deployed" for code that only exists in git.  
Do not claim monitoring "active" unless processes are running.  
Do not project performance improvements without test data.

---

**Audit Completed:** 2026-08-02  
**Auditor:** Manual code review + syntax verification  
**Next Step:** Address blocking issues before production deployment  
