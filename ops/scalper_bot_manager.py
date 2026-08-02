#!/usr/bin/env python3
"""
SCALPER BOT PROCESS MANAGER

Manages lifecycle of NIFTY50 and BANKNIFTY scalper bots:
- PID locking (prevent duplicate processes)
- Graceful startup/shutdown (SIGTERM handling)
- Exponential backoff on network failures
- Market hours enforcement
- Stale data detection and pause
- EOD shutdown
- Crash recovery
- Persistent logging

Usage:
    python3 ops/scalper_bot_manager.py validate NIFTY50_SCALPER_V1
    python3 ops/scalper_bot_manager.py start-paper NIFTY50_SCALPER_V1
    python3 ops/scalper_bot_manager.py status NIFTY50_SCALPER_V1
    python3 ops/scalper_bot_manager.py stop NIFTY50_SCALPER_V1
"""

import sys
import os
import signal
import time
import logging
import json
import fcntl
from datetime import datetime, timedelta, time as dt_time
from pathlib import Path
import pytz
from enum import Enum

# ============================================================================
# CONFIGURATION
# ============================================================================

BOT_CONFIGS = {
    "NIFTY50_SCALPER_V1": {
        "module": "nifty50_scalper_v1",
        "class": "Nifty50ScalperV1",
        "symbol": "^NSEI",
        "db": "paper_trading.db",
    },
    "BANKNIFTY_SCALPER_V1": {
        "module": "banknifty_scalper_v1",
        "class": "BankNiftyScalperV1",
        "symbol": "^NSEBANK",
        "db": "paper_trading.db",
    },
}

OPS_DIR = Path(__file__).parent
STATE_DIR = OPS_DIR / "state"
LOGS_DIR = OPS_DIR / "logs"
PIDS_DIR = OPS_DIR / "pids"

IST_TZ = pytz.timezone('Asia/Kolkata')

# ============================================================================
# LOGGING
# ============================================================================

def setup_logging(bot_name):
    """Set up logging for bot."""
    LOGS_DIR.mkdir(exist_ok=True)
    log_file = LOGS_DIR / f"{bot_name}.log"

    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s [%(levelname)s] %(message)s',
        handlers=[
            logging.FileHandler(log_file),
            logging.StreamHandler(sys.stdout),
        ]
    )

    return logging.getLogger(bot_name)

log = logging.getLogger(__name__)

# ============================================================================
# PID MANAGEMENT
# ============================================================================

class ProcessLock:
    """File-based process lock."""

    def __init__(self, bot_name):
        self.bot_name = bot_name
        self.pid_file = PIDS_DIR / f"{bot_name}.pid"
        self.lock_file = None

    def acquire(self):
        """Acquire lock. Raises if already locked."""
        PIDS_DIR.mkdir(exist_ok=True)

        try:
            self.lock_file = open(self.pid_file, 'w')
            fcntl.flock(self.lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.lock_file.write(str(os.getpid()))
            self.lock_file.flush()
            return True
        except IOError:
            # Lock held by another process
            if self.pid_file.exists():
                with open(self.pid_file) as f:
                    other_pid = f.read().strip()
                raise RuntimeError(
                    f"Process lock held by PID {other_pid}. "
                    f"Kill with: kill {other_pid}"
                )
            raise RuntimeError("Could not acquire lock")

    def release(self):
        """Release lock."""
        if self.lock_file:
            fcntl.flock(self.lock_file.fileno(), fcntl.LOCK_UN)
            self.lock_file.close()
            if self.pid_file.exists():
                self.pid_file.unlink()

# ============================================================================
# BOT STATE
# ============================================================================

class BotState(Enum):
    """Bot operational state."""
    IDLE = "idle"
    RUNNING = "running"
    PAUSED = "paused"
    STOPPED = "stopped"
    ERROR = "error"

class BotStatus:
    """Track bot status and statistics."""

    def __init__(self, bot_name):
        self.bot_name = bot_name
        self.state = BotState.IDLE
        self.start_time = None
        self.last_scan_time = None
        self.scan_count = 0
        self.signal_count = 0
        self.error_count = 0
        self.last_error = None
        self.network_failures = 0
        self.backoff_level = 0  # For exponential backoff

    def to_dict(self):
        """Convert to dict for JSON serialization."""
        return {
            "bot_name": self.bot_name,
            "state": self.state.value,
            "start_time": self.start_time.isoformat() if self.start_time else None,
            "last_scan_time": self.last_scan_time.isoformat() if self.last_scan_time else None,
            "scan_count": self.scan_count,
            "signal_count": self.signal_count,
            "error_count": self.error_count,
            "last_error": self.last_error,
            "network_failures": self.network_failures,
            "backoff_level": self.backoff_level,
        }

    @staticmethod
    def load(bot_name):
        """Load status from file."""
        STATE_DIR.mkdir(exist_ok=True)
        status_file = STATE_DIR / f"{bot_name}.json"

        status = BotStatus(bot_name)
        if status_file.exists():
            try:
                with open(status_file) as f:
                    data = json.load(f)
                    status.state = BotState(data.get("state", "idle"))
                    status.scan_count = data.get("scan_count", 0)
                    status.signal_count = data.get("signal_count", 0)
                    status.error_count = data.get("error_count", 0)
                    status.network_failures = data.get("network_failures", 0)
                    status.backoff_level = data.get("backoff_level", 0)
            except Exception as e:
                log.warning(f"Could not load status: {e}")

        return status

    def save(self):
        """Save status to file."""
        STATE_DIR.mkdir(exist_ok=True)
        status_file = STATE_DIR / f"{self.bot_name}.json"

        with open(status_file, 'w') as f:
            json.dump(self.to_dict(), f, indent=2)

# ============================================================================
# MARKET HOURS AND STATE CHECKS
# ============================================================================

def is_nse_trading_hours():
    """Check if within NSE trading hours."""
    now_ist = datetime.now(IST_TZ)
    market_open = now_ist.replace(hour=9, minute=15, second=0, microsecond=0)
    market_close = now_ist.replace(hour=15, minute=30, second=0, microsecond=0)

    if now_ist.weekday() >= 5:  # Weekend
        return False

    return market_open <= now_ist <= market_close

def should_shutdown_for_eod():
    """Check if EOD shutdown is needed."""
    now_ist = datetime.now(IST_TZ)
    eod_time = now_ist.replace(hour=15, minute=35, second=0, microsecond=0)
    return now_ist >= eod_time

# ============================================================================
# EXPONENTIAL BACKOFF
# ============================================================================

def get_backoff_delay(backoff_level):
    """Get delay in seconds for given backoff level."""
    # Exponential backoff: 1s, 3s, 10s, 30s, 60s
    delays = [1, 3, 10, 30, 60]
    return delays[min(backoff_level, len(delays) - 1)]

# ============================================================================
# BOT RUNNER
# ============================================================================

class ScalperBotRunner:
    """Runs a scalper bot with lifecycle management."""

    def __init__(self, bot_name):
        self.bot_name = bot_name
        self.config = BOT_CONFIGS.get(bot_name)
        if not self.config:
            raise ValueError(f"Unknown bot: {bot_name}")

        self.status = BotStatus.load(bot_name)
        self.lock = ProcessLock(bot_name)
        self.should_stop = False
        self.bot_instance = None
        self.data_fetcher = None

        # Set up signal handlers
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)

    def _signal_handler(self, signum, frame):
        """Handle SIGTERM/SIGINT gracefully."""
        log.info(f"Received signal {signum}, shutting down gracefully...")
        self.should_stop = True

    def validate(self):
        """Validate bot configuration and dependencies."""
        log.info(f"Validating {self.bot_name}...")

        # Check module import
        try:
            module = __import__(self.config["module"])
            log.info(f"  ✓ Module {self.config['module']} importable")
        except ImportError as e:
            log.error(f"  ✗ Module {self.config['module']} not found: {e}")
            return False

        # Check class exists
        try:
            bot_class = getattr(module, self.config["class"])
            log.info(f"  ✓ Class {self.config['class']} found")
        except AttributeError as e:
            log.error(f"  ✗ Class {self.config['class']} not found: {e}")
            return False

        # Check database path
        db_path = self.config["db"]
        if not os.access(os.path.dirname(db_path) or ".", os.W_OK):
            log.error(f"  ✗ Cannot write to database directory: {db_path}")
            return False
        log.info(f"  ✓ Database directory writable: {db_path}")

        # Check data fetcher
        try:
            from scalper_strategy_harness import DataFetcher
            fetcher = DataFetcher(self.config["symbol"])
            log.info(f"  ✓ Data fetcher available for {self.config['symbol']}")
        except Exception as e:
            log.error(f"  ✗ Data fetcher error: {e}")
            return False

        log.info(f"✓ Validation passed for {self.bot_name}")
        return True

    def start(self):
        """Start the bot process."""
        log.info(f"Starting {self.bot_name}...")

        # Acquire lock
        try:
            self.lock.acquire()
        except RuntimeError as e:
            log.error(f"Cannot start: {e}")
            return False

        log.info(f"✓ Process lock acquired (PID {os.getpid()})")

        # Import bot
        try:
            module = __import__(self.config["module"])
            bot_class = getattr(module, self.config["class"])
            from scalper_strategy_harness import DataFetcher

            self.bot_instance = bot_class(self.config["db"])
            self.data_fetcher = DataFetcher(self.config["symbol"])
            log.info(f"✓ Bot instance created")
        except Exception as e:
            log.error(f"Failed to create bot instance: {e}", exc_info=True)
            self.lock.release()
            return False

        # Update status
        self.status.state = BotState.RUNNING
        self.status.start_time = datetime.now(IST_TZ)
        self.status.save()

        # Main loop
        try:
            self._main_loop()
        except Exception as e:
            log.error(f"Fatal error in main loop: {e}", exc_info=True)
            self.status.state = BotState.ERROR
            self.status.last_error = str(e)
            self.status.save()
        finally:
            self.lock.release()
            log.info(f"✓ Process lock released")

        return True

    def _main_loop(self):
        """Main run loop with market hours checks."""
        log.info(f"Entering main loop...")

        while not self.should_stop:
            # Check for EOD shutdown
            if should_shutdown_for_eod():
                log.info("EOD reached, shutting down")
                break

            # Check market hours
            if not is_nse_trading_hours():
                log.info("Outside market hours, sleeping...")
                time.sleep(60)
                continue

            # Check stale data
            if self.status.backoff_level > 0:
                delay = get_backoff_delay(self.status.backoff_level)
                log.info(f"Backoff level {self.status.backoff_level}, waiting {delay}s...")
                time.sleep(delay)

            # Run scan
            try:
                self.bot_instance.run_once(self.data_fetcher)
                self.status.last_scan_time = datetime.now(IST_TZ)
                self.status.scan_count += 1
                self.status.network_failures = 0
                self.status.backoff_level = 0
                self.status.state = BotState.RUNNING
            except ConnectionError as e:
                self.status.network_failures += 1
                self.status.backoff_level = min(self.status.backoff_level + 1, 4)
                self.status.error_count += 1
                self.status.last_error = str(e)
                log.error(f"Network error (backoff level {self.status.backoff_level}): {e}")
            except Exception as e:
                self.status.error_count += 1
                self.status.last_error = str(e)
                log.error(f"Scan error: {e}", exc_info=True)

            # Save status
            self.status.save()

            # Scan interval
            time.sleep(60)

        log.info(f"Main loop ended")

    def stop(self):
        """Stop the bot process."""
        log.info(f"Stopping {self.bot_name}...")

        pid_file = PIDS_DIR / f"{self.bot_name}.pid"
        if not pid_file.exists():
            log.warning(f"No PID file found; bot may not be running")
            return False

        try:
            with open(pid_file) as f:
                pid = int(f.read().strip())

            if pid == os.getpid():
                log.error("Cannot kill self; run from different process")
                return False

            os.kill(pid, signal.SIGTERM)
            log.info(f"✓ Sent SIGTERM to PID {pid}")

            # Wait for shutdown
            for _ in range(10):
                if not pid_file.exists():
                    log.info(f"✓ Process {pid} terminated")
                    return True
                time.sleep(0.5)

            log.warning(f"Process {pid} did not terminate after 5s; forcing...")
            os.kill(pid, signal.SIGKILL)
            return True

        except Exception as e:
            log.error(f"Error stopping bot: {e}")
            return False

    def status_report(self):
        """Get current status."""
        status = self.status.to_dict()
        log.info(json.dumps(status, indent=2))
        return status

# ============================================================================
# CLI
# ============================================================================

def main():
    """CLI interface."""
    if len(sys.argv) < 3:
        print("Usage:")
        print("  python3 ops/scalper_bot_manager.py validate BOT_NAME")
        print("  python3 ops/scalper_bot_manager.py start-paper BOT_NAME")
        print("  python3 ops/scalper_bot_manager.py status BOT_NAME")
        print("  python3 ops/scalper_bot_manager.py stop BOT_NAME")
        print()
        print("Available bots:")
        for bot_name in BOT_CONFIGS.keys():
            print(f"  - {bot_name}")
        sys.exit(1)

    command = sys.argv[1]
    bot_name = sys.argv[2]

    # Set up logging
    setup_logging(bot_name)

    # Create runner
    runner = ScalperBotRunner(bot_name)

    # Execute command
    if command == "validate":
        success = runner.validate()
        sys.exit(0 if success else 1)

    elif command == "start-paper":
        log.info(f"Starting {bot_name} in PAPER mode...")
        success = runner.start()
        sys.exit(0 if success else 1)

    elif command == "status":
        runner.status_report()
        sys.exit(0)

    elif command == "stop":
        success = runner.stop()
        sys.exit(0 if success else 1)

    else:
        log.error(f"Unknown command: {command}")
        sys.exit(1)

if __name__ == "__main__":
    main()
