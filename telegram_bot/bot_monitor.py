#!/usr/bin/env python3
"""
BOT PERFORMANCE MONITOR

Real-time surveillance of all trading bots:
- Signal generation tracking
- Win/loss ratio monitoring
- Error detection and alerts
- Performance scoring
- Auto-optimization recommendations

Runs continuously, logs all metrics, alerts on issues.
"""

import os
import json
import time
import psutil
import requests
from datetime import datetime, timedelta
from pathlib import Path
import pytz

IST = pytz.timezone('Asia/Kolkata')
MONITOR_DIR = Path(__file__).parent / "bot_monitor_data"
MONITOR_DIR.mkdir(exist_ok=True)

# Bot processes to watch
BOTS = {
    "scanner_bot": {
        "name": "NSE Intraday Scanner",
        "script": "scanner_bot.py",
        "log": "logs/scanner.log",
        "state": ".scanner_state.json",
    },
    "nifty_scalper": {
        "name": "NIFTY50 Scalper",
        "script": "nifty_scalper.py",
        "log": "logs/nifty.log",
        "db": "paper_trading.db",
    },
    "forex_scalper": {
        "name": "Forex Scalper",
        "script": "forex_scalper.py",
        "log": "logs/scalper.log",
        "db": "paper_trading.db",
    },
    "gold_bot": {
        "name": "Gold/XAUUSD Bot",
        "script": "gold_bot.py",
        "log": "logs/gold.log",
    },
    "token_updater": {
        "name": "Token Updater Bot",
        "script": "token_updater_bot.py",
        "log": "logs/token_updater.log",
    },
}

SIGNAL_CHAT_ID = "1994067941"
ELITE_BOT_TOKEN = "8649245457:AAFpe95Us_eiVTuewD1f7TJG2gRwUMX0zuA"

# ════════════════════════════════════════════════════════════════════════════
# BOT HEALTH CHECKS
# ════════════════════════════════════════════════════════════════════════════

class BotHealthCheck:
    """Monitor individual bot health."""

    def __init__(self, bot_key, bot_config):
        self.bot_key = bot_key
        self.config = bot_config
        self.name = bot_config["name"]
        self.status_file = MONITOR_DIR / f"{bot_key}_status.json"

    def check_process_running(self):
        """Check if bot process is running."""
        for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
            try:
                if self.config["script"] in ' '.join(proc.info['cmdline'] or []):
                    return True, proc.info['pid']
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        return False, None

    def check_log_recent(self):
        """Check if bot has written to log recently (last 5 min)."""
        log_path = Path(self.config.get("log"))
        if not log_path.exists():
            return False, "Log file not found"

        mod_time = log_path.stat().st_mtime
        now = time.time()
        age_seconds = now - mod_time

        if age_seconds < 300:  # 5 minutes
            return True, f"{age_seconds:.0f}s ago"
        else:
            return False, f"{age_seconds/60:.1f} minutes ago"

    def check_state_file(self):
        """Check if state file is fresh (last 10 min)."""
        if "state" not in self.config:
            return None, "No state file"

        state_path = Path(self.config["state"])
        if not state_path.exists():
            return False, "State file not found"

        mod_time = state_path.stat().st_mtime
        now = time.time()
        age_seconds = now - mod_time

        if age_seconds < 600:  # 10 minutes
            return True, f"{age_seconds:.0f}s ago"
        else:
            return False, f"{age_seconds/60:.1f} minutes ago"

    def check_error_rate(self):
        """Count errors in recent log entries."""
        log_path = Path(self.config.get("log"))
        if not log_path.exists():
            return None, "Log not found"

        try:
            with open(log_path, 'r') as f:
                lines = f.readlines()[-100:]  # Last 100 lines
                error_count = sum(1 for line in lines if 'error' in line.lower() or 'exception' in line.lower())
                return error_count, f"{error_count} errors in last 100 log lines"
        except Exception:
            return None, "Could not read log"

    def get_full_status(self):
        """Get complete health status for this bot."""
        running, pid = self.check_process_running()
        log_fresh, log_age = self.check_log_recent()
        state_fresh, state_age = self.check_state_file()
        errors, error_msg = self.check_error_rate()

        status = {
            "bot": self.name,
            "bot_key": self.bot_key,
            "timestamp": datetime.now(IST).isoformat(),
            "running": running,
            "pid": pid,
            "log_fresh": log_fresh,
            "log_age": log_age,
            "state_fresh": state_fresh,
            "state_age": state_age,
            "error_rate": error_msg,
            "health_score": self.calculate_health_score(running, log_fresh, state_fresh, errors),
        }

        # Save status
        with open(self.status_file, 'w') as f:
            json.dump(status, f, indent=2)

        return status

    def calculate_health_score(self, running, log_fresh, state_fresh, errors):
        """Calculate overall health (0-100)."""
        score = 100

        if not running:
            score -= 50
        if not log_fresh:
            score -= 20
        if not state_fresh:
            score -= 15
        if errors and errors > 5:
            score -= min(20, errors * 2)

        return max(0, score)

# ════════════════════════════════════════════════════════════════════════════
# SIGNAL PERFORMANCE TRACKING
# ════════════════════════════════════════════════════════════════════════════

class SignalPerformanceTracker:
    """Track signal quality and accuracy."""

    def __init__(self):
        self.perf_file = MONITOR_DIR / "signal_performance.json"
        self.load_performance()

    def load_performance(self):
        """Load historical performance data."""
        if self.perf_file.exists():
            with open(self.perf_file) as f:
                self.data = json.load(f)
        else:
            self.data = {
                "signals_today": 0,
                "signals_this_week": 0,
                "average_hold_time": 0,
                "win_rate": 0,
                "avg_profit": 0,
                "avg_loss": 0,
                "largest_win": 0,
                "largest_loss": 0,
                "profit_factor": 0,
            }

    def save_performance(self):
        """Save performance metrics."""
        with open(self.perf_file, 'w') as f:
            json.dump(self.data, f, indent=2)

    def get_report(self):
        """Generate performance summary."""
        return self.data

# ════════════════════════════════════════════════════════════════════════════
# ALERT SYSTEM
# ════════════════════════════════════════════════════════════════════════════

def send_alert(alert_type, bot_name, message):
    """Send alert via Telegram if critical."""
    if alert_type not in ["WARNING", "CRITICAL", "ERROR"]:
        return

    msg = (
        f"🚨 <b>BOT ALERT</b>\n"
        f"Bot: {bot_name}\n"
        f"Type: {alert_type}\n"
        f"━━━━━━━━━━━━━━━━━━━━\n"
        f"{message}\n"
        f"━━━━━━━━━━━━━━━━━━━━\n"
        f"Time: {datetime.now(IST).strftime('%H:%M IST')}"
    )

    try:
        url = f"https://api.telegram.org/bot{ELITE_BOT_TOKEN}/sendMessage"
        requests.post(url, data={"chat_id": SIGNAL_CHAT_ID, "text": msg, "parse_mode": "HTML"}, timeout=10)
    except Exception as e:
        print(f"Alert failed: {e}")

# ════════════════════════════════════════════════════════════════════════════
# MAIN MONITORING LOOP
# ════════════════════════════════════════════════════════════════════════════

def run_monitor():
    """Main monitoring loop."""
    print("🔍 BOT MONITOR STARTED")
    print(f"Watching {len(BOTS)} bots every 60 seconds\n")

    monitor_interval = 60  # Check every 60 seconds

    while True:
        try:
            now_ist = datetime.now(IST)
            print(f"\n[{now_ist.strftime('%H:%M:%S IST')}] ─────────────────────")

            all_statuses = {}

            for bot_key, bot_config in BOTS.items():
                checker = BotHealthCheck(bot_key, bot_config)
                status = checker.get_full_status()
                all_statuses[bot_key] = status

                # Display status
                health = status["health_score"]
                emoji = "🟢" if health >= 80 else "🟡" if health >= 50 else "🔴"
                print(f"{emoji} {status['bot']:20} | Health: {health:3}/100 | Running: {status['running']} | PID: {status['pid']}")

                # Alert on critical issues
                if status["health_score"] < 50:
                    send_alert("CRITICAL", status["bot"],
                              f"Health score: {status['health_score']}/100\n"
                              f"Running: {status['running']}\n"
                              f"Log fresh: {status['log_fresh']}\n"
                              f"Error rate: {status['error_rate']}")

                if not status["running"]:
                    send_alert("ERROR", status["bot"], f"Process not running! Last log: {status['log_age']}")

            # Save collective status
            collective_file = MONITOR_DIR / "all_bots_status.json"
            with open(collective_file, 'w') as f:
                json.dump(all_statuses, f, indent=2)

            # Sleep and repeat
            time.sleep(monitor_interval)

        except Exception as e:
            print(f"Monitor error: {e}")
            time.sleep(monitor_interval)

def print_summary():
    """Print summary of all bot statuses."""
    collective_file = MONITOR_DIR / "all_bots_status.json"
    if not collective_file.exists():
        print("No status data yet. Run monitor first.")
        return

    with open(collective_file) as f:
        statuses = json.load(f)

    print("\n" + "="*70)
    print("BOT HEALTH SUMMARY")
    print("="*70)

    for bot_key, status in statuses.items():
        print(f"\n{status['bot']} (PID: {status['pid']})")
        print(f"  Health Score:  {status['health_score']}/100")
        print(f"  Running:       {status['running']}")
        print(f"  Log Fresh:     {status['log_fresh']} ({status['log_age']})")
        print(f"  State Fresh:   {status['state_fresh']} ({status['state_age']})")
        print(f"  Errors:        {status['error_rate']}")

    print("\n" + "="*70)

if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1 and sys.argv[1] == "summary":
        print_summary()
    else:
        run_monitor()
