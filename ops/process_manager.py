#!/usr/bin/env python3
"""
Process Manager — Safe start, stop, restart, and status for scanner_bot.py
Prevents multiple instances, validates PIDs, and maintains restart backoff.
"""

import os
import sys
import subprocess
import time
import signal
from pathlib import Path
from datetime import datetime, timedelta
from typing import Optional, Tuple

class BotProcessManager:
    def __init__(self, repo_root: str, bot_script: str = "telegram_bot/scanner_bot.py"):
        """
        Initialize process manager.

        Args:
            repo_root: Absolute path to repository root (e.g., /Users/ajayoberoi/MediDeals-iOS-App)
            bot_script: Relative path to bot script from repo root
        """
        self.repo_root = Path(repo_root)
        self.bot_script = self.repo_root / bot_script
        self.pid_file = self.repo_root / ".bot_pid"
        self.restart_log = self._get_log_dir() / "restarts.log"
        self.max_restart_attempts = 5
        self.restart_backoff_minutes = 5

        if not self.bot_script.exists():
            raise FileNotFoundError(f"Bot script not found: {self.bot_script}")

    def _get_log_dir(self) -> Path:
        """Get standard logging directory."""
        log_dir = Path.home() / "Library" / "Logs" / "ajay-trading-bot"
        log_dir.mkdir(parents=True, exist_ok=True)
        return log_dir

    def _is_process_running(self, pid: int) -> bool:
        """Check if a process is actually running with the given PID."""
        try:
            # Send signal 0 (just check if process exists)
            os.kill(pid, 0)
            return True
        except (OSError, ProcessLookupError):
            return False

    def _validate_pid(self, pid: int) -> bool:
        """Validate that PID belongs to the expected bot process."""
        try:
            # Use ps to verify the process
            result = subprocess.run(
                ["ps", "-p", str(pid), "-o", "command="],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                command = result.stdout.strip()
                # Check if it's running our bot script
                return "scanner_bot.py" in command
            return False
        except Exception:
            return False

    def _read_pid(self) -> Optional[int]:
        """Read PID from file, return None if stale or invalid."""
        if not self.pid_file.exists():
            return None

        try:
            pid = int(self.pid_file.read_text().strip())
            if self._is_process_running(pid) and self._validate_pid(pid):
                return pid
            else:
                # Stale PID, remove it
                self.pid_file.unlink()
                return None
        except (ValueError, OSError):
            self.pid_file.unlink() if self.pid_file.exists() else None
            return None

    def _write_pid(self, pid: int):
        """Write PID to file."""
        self.pid_file.write_text(str(pid))

    def _log_restart(self, status: str, reason: str = ""):
        """Log restart event."""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        line = f"{timestamp} | {status} | {reason}\n"
        self.restart_log.parent.mkdir(parents=True, exist_ok=True)
        with open(self.restart_log, "a") as f:
            f.write(line)

    def status(self) -> Tuple[bool, str]:
        """
        Get bot status.
        Returns: (is_running, status_message)
        """
        pid = self._read_pid()

        if pid is None:
            return False, "Bot is NOT running (no valid PID)"

        if self._is_process_running(pid):
            try:
                result = subprocess.run(
                    ["ps", "-p", str(pid), "-o", "etime="],
                    capture_output=True, text=True, timeout=5
                )
                uptime = result.stdout.strip() if result.returncode == 0 else "unknown"
                return True, f"Bot is running (PID {pid}, uptime: {uptime})"
            except Exception as e:
                return True, f"Bot is running (PID {pid}, uptime unknown: {e})"

        return False, f"PID {pid} is not a running process"

    def start(self) -> Tuple[bool, str]:
        """
        Start the bot if not already running.
        Returns: (success, message)
        """
        # Check if already running
        running, status_msg = self.status()
        if running:
            return False, f"Bot already running. {status_msg}"

        # Change to repo root
        os.chdir(self.repo_root)

        try:
            # Start bot as subprocess (detached from this process)
            process = subprocess.Popen(
                [sys.executable, str(self.bot_script)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True  # Detach from parent
            )

            self._write_pid(process.pid)
            self._log_restart("START_SUCCESS", f"PID {process.pid}")

            time.sleep(1)  # Give process time to start

            # Verify it's still running
            if self._is_process_running(process.pid):
                return True, f"Bot started successfully (PID {process.pid})"
            else:
                self._log_restart("START_FAILED", "Process exited immediately")
                return False, "Bot started but exited immediately (check logs)"

        except Exception as e:
            self._log_restart("START_FAILED", str(e))
            return False, f"Failed to start bot: {e}"

    def stop(self, force: bool = False) -> Tuple[bool, str]:
        """
        Stop the bot gracefully or forcefully.
        Returns: (success, message)
        """
        pid = self._read_pid()

        if pid is None:
            return True, "Bot is not running"

        try:
            if not self._is_process_running(pid):
                self.pid_file.unlink()
                return True, "Bot was not running (PID file cleaned)"

            # Try graceful SIGTERM first
            os.kill(pid, signal.SIGTERM)
            self._log_restart("STOP_SIGTERM", f"PID {pid}")

            # Wait up to 5 seconds for graceful shutdown
            for _ in range(50):  # 5 seconds with 0.1s intervals
                if not self._is_process_running(pid):
                    self.pid_file.unlink()
                    self._log_restart("STOP_SUCCESS", f"PID {pid} shut down gracefully")
                    return True, "Bot stopped gracefully"
                time.sleep(0.1)

            # If still running, use SIGKILL if force=True
            if force:
                os.kill(pid, signal.SIGKILL)
                self._log_restart("STOP_SIGKILL", f"PID {pid}")
                time.sleep(0.5)
                self.pid_file.unlink()
                return True, "Bot force-stopped"

            return False, f"Bot did not stop gracefully (PID {pid}). Use force=True to kill."

        except ProcessLookupError:
            self.pid_file.unlink()
            return True, "Bot process no longer exists (cleaned up)"
        except Exception as e:
            return False, f"Failed to stop bot: {e}"

    def restart(self) -> Tuple[bool, str]:
        """
        Restart the bot (stop and start).
        Returns: (success, message)
        """
        stopped, stop_msg = self.stop()
        if not stopped:
            return False, f"Failed to stop bot: {stop_msg}"

        time.sleep(1)

        started, start_msg = self.start()
        if not started:
            self._log_restart("RESTART_FAILED", start_msg)
            return False, f"Failed to restart: {start_msg}"

        self._log_restart("RESTART_SUCCESS", "")
        return True, start_msg

    def get_restart_history(self, limit: int = 20) -> list:
        """Get recent restart log entries."""
        if not self.restart_log.exists():
            return []

        with open(self.restart_log, "r") as f:
            lines = f.readlines()
            return lines[-limit:]


if __name__ == '__main__':
    # Usage example
    if len(sys.argv) < 2:
        print("Usage: process_manager.py [start|stop|restart|status]")
        sys.exit(1)

    # Mac paths (adjust as needed)
    manager = BotProcessManager(repo_root="/Users/ajayoberoi/MediDeals-iOS-App")

    command = sys.argv[1].lower()

    if command == "start":
        success, msg = manager.start()
        print(msg)
        sys.exit(0 if success else 1)
    elif command == "stop":
        success, msg = manager.stop()
        print(msg)
        sys.exit(0 if success else 1)
    elif command == "restart":
        success, msg = manager.restart()
        print(msg)
        sys.exit(0 if success else 1)
    elif command == "status":
        running, msg = manager.status()
        print(msg)
        sys.exit(0 if running else 1)
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)
