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
import subprocess
import requests
from datetime import datetime, timedelta
from pathlib import Path
import pytz

try:
    import psutil
    HAS_PSUTIL = True
except ImportError:
    HAS_PSUTIL = False

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
# BOT DISCOVERY
# ════════════════════════════════════════════════════════════════════════════

def discover_trading_bots():
    """Auto-discover trading bots by looking for log files."""
    log_dir = Path("logs")
    if not log_dir.exists():
        return {}

    discovered = {}
    for log_file in log_dir.glob("*.log"):
        bot_name = log_file.stem
        # Exclude utility scripts
        if bot_name not in ["backtest_forex", "backtest_nifty", "backtest_options", "signal_sync_mac", "signal_server"]:
            discovered[bot_name] = {
                "name": bot_name.replace("_", " ").title(),
                "script": f"{bot_name}.py",
                "log": str(log_file),
            }

    return discovered

# ════════════════════════════════════════════════════════════════════════════
# ALERT DEDUPLICATION
# ════════════════════════════════════════════════════════════════════════════

class AlertManager:
    """Manage alert deduplication and cooldown."""

    def __init__(self):
        self.alert_state_file = MONITOR_DIR / "alert_state.json"
        self.load_state()
        self.cooldown_minutes = 60  # Only alert once per hour for same issue

    def load_state(self):
        """Load alert state from file."""
        if self.alert_state_file.exists():
            with open(self.alert_state_file) as f:
                self.state = json.load(f)
        else:
            self.state = {}

    def save_state(self):
        """Save alert state to file."""
        with open(self.alert_state_file, 'w') as f:
            json.dump(self.state, f, indent=2)

    def should_alert(self, bot_key, alert_type):
        """Check if alert should be sent based on cooldown."""
        now = time.time()
        alert_key = f"{bot_key}_{alert_type}"

        if alert_key not in self.state:
            self.state[alert_key] = {"last_alert": now, "count": 1}
            self.save_state()
            return True

        last_alert_time = self.state[alert_key]["last_alert"]
        time_since_alert = (now - last_alert_time) / 60  # Convert to minutes

        if time_since_alert > self.cooldown_minutes:
            self.state[alert_key] = {"last_alert": now, "count": self.state[alert_key].get("count", 0) + 1}
            self.save_state()
            return True

        return False

    def reset_alert(self, bot_key, alert_type):
        """Reset alert state when issue is resolved."""
        alert_key = f"{bot_key}_{alert_type}"
        if alert_key in self.state:
            del self.state[alert_key]
            self.save_state()

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
        if HAS_PSUTIL:
            try:
                for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
                    try:
                        if self.config["script"] in ' '.join(proc.info['cmdline'] or []):
                            return True, proc.info['pid']
                    except (psutil.NoSuchProcess, psutil.AccessDenied):
                        pass
            except Exception:
                pass
        else:
            # Fallback: use pgrep
            try:
                result = subprocess.run(
                    ['pgrep', '-f', self.config["script"]],
                    capture_output=True, text=True, timeout=5
                )
                if result.returncode == 0:
                    pids = result.stdout.strip().split('\n')
                    return True, int(pids[0])
            except Exception:
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
    print("Auto-discovering bots...\n")

    monitor_interval = 60  # Check every 60 seconds
    alert_manager = AlertManager()
    previous_statuses = {}

    while True:
        try:
            now_ist = datetime.now(IST)
            print(f"\n[{now_ist.strftime('%H:%M:%S IST')}] ─────────────────────")

            # Auto-discover bots
            discovered_bots = discover_trading_bots()
            if not discovered_bots:
                print("⚠️  No bots discovered. Checking in 60s...")
                time.sleep(monitor_interval)
                continue

            print(f"Monitoring {len(discovered_bots)} bots")

            all_statuses = {}

            for bot_key, bot_config in discovered_bots.items():
                checker = BotHealthCheck(bot_key, bot_config)
                status = checker.get_full_status()
                all_statuses[bot_key] = status

                # Display status
                health = status["health_score"]
                emoji = "🟢" if health >= 80 else "🟡" if health >= 50 else "🔴"
                print(f"{emoji} {status['bot']:20} | Health: {health:3}/100 | Running: {status['running']} | PID: {status['pid']}")

                # Alert on critical issues (with deduplication)
                prev_health = previous_statuses.get(bot_key, {}).get("health_score", 100)

                if status["health_score"] < 50 and alert_manager.should_alert(bot_key, "CRITICAL"):
                    send_alert("CRITICAL", status["bot"],
                              f"Health score: {status['health_score']}/100\n"
                              f"Running: {status['running']}\n"
                              f"Log fresh: {status['log_fresh']}\n"
                              f"Error rate: {status['error_rate']}")
                elif status["health_score"] >= 50 and prev_health < 50:
                    # Recovery notification
                    send_alert("RECOVERY", status["bot"],
                              f"✅ Bot recovered. Health: {status['health_score']}/100")
                    alert_manager.reset_alert(bot_key, "CRITICAL")

                if not status["running"] and alert_manager.should_alert(bot_key, "PROCESS_DOWN"):
                    send_alert("ERROR", status["bot"], f"Process not running! Last log: {status['log_age']}")
                elif status["running"] and not previous_statuses.get(bot_key, {}).get("running", True):
                    # Process restarted
                    alert_manager.reset_alert(bot_key, "PROCESS_DOWN")

            # Save historical snapshot (append, don't overwrite)
            timestamp = datetime.now(IST).isoformat()
            history_file = MONITOR_DIR / f"history_{datetime.now().strftime('%Y%m%d')}.jsonl"
            with open(history_file, 'a') as f:
                f.write(json.dumps({"timestamp": timestamp, "statuses": all_statuses}) + "\n")

            # Save latest snapshot
            latest_file = MONITOR_DIR / "all_bots_status.json"
            with open(latest_file, 'w') as f:
                json.dump({"timestamp": timestamp, "statuses": all_statuses}, f, indent=2)

            previous_statuses = all_statuses

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
