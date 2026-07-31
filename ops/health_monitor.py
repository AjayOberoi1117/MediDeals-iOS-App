#!/usr/bin/env python3
"""
Health Monitor — Checks bot process, market data freshness, and API connectivity.
Reports issues and suggests corrective actions.
"""

import json
import os
import sys
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Dict, List, Tuple

class HealthMonitor:
    def __init__(self, repo_root: str, log_path: str = "/tmp/scanner-bot.log"):
        self.repo_root = Path(repo_root)
        self.log_path = Path(log_path)
        self.timezone = "Asia/Kolkata"
        self.market_open = (9, 15)  # IST
        self.market_close = (15, 30)  # IST

    def _get_ist_time(self) -> datetime:
        """Get current time in IST."""
        # Use system timezone (this should be IST on the Mac)
        return datetime.now()

    def _is_market_hours(self) -> bool:
        """Check if current time is within market hours."""
        now = self._get_ist_time()
        t = (now.hour, now.minute)
        return self.market_open <= t <= self.market_close

    def _is_trading_day(self) -> bool:
        """Check if today is a trading day (Monday-Friday)."""
        now = self._get_ist_time()
        return now.weekday() < 5  # 0-4 = Mon-Fri

    def check_process(self) -> Dict[str, any]:
        """Check if bot process is running."""
        from ops.process_manager import BotProcessManager
        manager = BotProcessManager(str(self.repo_root))
        running, status_msg = manager.status()

        return {
            'component': 'process',
            'healthy': running,
            'message': status_msg,
            'action': None if running else 'RESTART_BOT'
        }

    def check_log_freshness(self) -> Dict[str, any]:
        """Check if bot is actively writing logs (sign of life)."""
        if not self.log_path.exists():
            return {
                'component': 'log_freshness',
                'healthy': False,
                'message': f"Log file not found: {self.log_path}",
                'action': 'CHECK_BOT_START'
            }

        try:
            stat = self.log_path.stat()
            mod_time = datetime.fromtimestamp(stat.st_mtime)
            age_minutes = (datetime.now() - mod_time).total_seconds() / 60

            # If market hours: logs should be < 5 minutes old
            # If outside market hours: logs should be < 60 minutes old
            if self._is_market_hours():
                healthy = age_minutes < 5
                threshold = 5
            else:
                healthy = age_minutes < 60
                threshold = 60

            message = f"Log last modified {age_minutes:.1f} minutes ago"
            if not healthy:
                message += f" (older than {threshold}min threshold)"

            return {
                'component': 'log_freshness',
                'healthy': healthy,
                'message': message,
                'age_minutes': age_minutes,
                'action': 'CHECK_LOG_CONTENT' if not healthy else None
            }
        except Exception as e:
            return {
                'component': 'log_freshness',
                'healthy': False,
                'message': f"Error reading log: {e}",
                'action': 'CHECK_BOT_START'
            }

    def check_log_content(self) -> Dict[str, any]:
        """Check for errors or staleness in recent log entries."""
        if not self.log_path.exists():
            return {'component': 'log_content', 'healthy': True, 'message': 'N/A'}

        try:
            with open(self.log_path, 'r') as f:
                lines = f.readlines()

            if not lines:
                return {
                    'component': 'log_content',
                    'healthy': False,
                    'message': 'Log file is empty',
                    'action': 'CHECK_BOT_START'
                }

            # Get last 50 lines
            recent_lines = ''.join(lines[-50:])

            # Check for error patterns
            error_patterns = [
                'Exception',
                'Error',
                'Failed',
                'Stale data',
                'API error',
                'Telegram error'
            ]

            issues = []
            for pattern in error_patterns:
                if pattern in recent_lines:
                    issues.append(pattern)

            if issues:
                return {
                    'component': 'log_content',
                    'healthy': False,
                    'message': f"Found errors in recent logs: {', '.join(set(issues))}",
                    'action': 'REVIEW_LOGS'
                }

            # Check if scanning is happening
            if 'Scan:' not in recent_lines and self._is_market_hours():
                return {
                    'component': 'log_content',
                    'healthy': False,
                    'message': 'No recent scan activity detected during market hours',
                    'action': 'RESTART_BOT'
                }

            return {
                'component': 'log_content',
                'healthy': True,
                'message': 'Recent log entries look normal'
            }

        except Exception as e:
            return {
                'component': 'log_content',
                'healthy': False,
                'message': f"Error reading log: {e}",
                'action': 'CHECK_BOT_START'
            }

    def check_market_data(self) -> Dict[str, any]:
        """Check if market data is being fetched and is recent."""
        if not self.log_path.exists():
            return {'component': 'market_data', 'healthy': True, 'message': 'N/A'}

        try:
            with open(self.log_path, 'r') as f:
                lines = f.readlines()

            # Look for successful candle fetches in last 50 lines
            recent = ''.join(lines[-50:])

            if '[1m]' in recent or '[30m]' in recent:
                return {
                    'component': 'market_data',
                    'healthy': True,
                    'message': 'Market data being fetched successfully'
                }

            if self._is_market_hours():
                return {
                    'component': 'market_data',
                    'healthy': False,
                    'message': 'No recent market data fetch during market hours',
                    'action': 'CHECK_API_CONNECTIVITY'
                }

            return {
                'component': 'market_data',
                'healthy': True,
                'message': 'N/A (outside market hours)'
            }

        except Exception as e:
            return {
                'component': 'market_data',
                'healthy': False,
                'message': f"Error checking: {e}",
                'action': 'CHECK_BOT_LOGS'
            }

    def check_telegram_delivery(self) -> Dict[str, any]:
        """Check if signals are being delivered to Telegram."""
        if not self.log_path.exists():
            return {'component': 'telegram', 'healthy': True, 'message': 'N/A'}

        try:
            with open(self.log_path, 'r') as f:
                lines = f.readlines()

            # Look for signal and telegram messages
            recent = ''.join(lines[-100:])

            if 'Telegram error' in recent:
                return {
                    'component': 'telegram',
                    'healthy': False,
                    'message': 'Telegram delivery errors detected',
                    'action': 'CHECK_TELEGRAM_CONFIG'
                }

            if '→ BUY' in recent and 'Telegram' not in recent:
                return {
                    'component': 'telegram',
                    'healthy': False,
                    'message': 'Signals detected but no Telegram delivery',
                    'action': 'CHECK_TELEGRAM_TOKEN'
                }

            return {
                'component': 'telegram',
                'healthy': True,
                'message': 'Telegram status OK'
            }

        except Exception as e:
            return {
                'component': 'telegram',
                'healthy': False,
                'message': f"Error checking: {e}",
                'action': 'REVIEW_LOGS'
            }

    def run_full_health_check(self) -> Dict:
        """Run all health checks."""
        checks = [
            self.check_process(),
            self.check_log_freshness(),
            self.check_log_content(),
            self.check_market_data(),
            self.check_telegram_delivery()
        ]

        issues = [c for c in checks if not c.get('healthy')]
        actions = [c.get('action') for c in checks if c.get('action')]

        return {
            'timestamp': datetime.now().isoformat(),
            'market_hours': self._is_market_hours(),
            'trading_day': self._is_trading_day(),
            'checks': checks,
            'total_checks': len(checks),
            'healthy_checks': len(checks) - len(issues),
            'issues': issues,
            'recommended_actions': list(set(actions))  # Deduplicate
        }


if __name__ == '__main__':
    monitor = HealthMonitor(repo_root="/Users/ajayoberoi/MediDeals-iOS-App")
    result = monitor.run_full_health_check()

    print("\n" + "="*60)
    print("BOT HEALTH MONITORING REPORT")
    print("="*60)
    print(f"Timestamp: {result['timestamp']}")
    print(f"Market Hours: {result['market_hours']} | Trading Day: {result['trading_day']}")
    print(f"Overall: {result['healthy_checks']}/{result['total_checks']} checks passed\n")

    for check in result['checks']:
        status = "✓ PASS" if check['healthy'] else "✗ FAIL"
        print(f"{status} | {check['component']:<20} | {check['message']}")

    if result['issues']:
        print("\n" + "-"*60)
        print("ISSUES DETECTED:")
        for issue in result['issues']:
            print(f"  • {issue['component']}: {issue['message']}")

    if result['recommended_actions']:
        print("\n" + "-"*60)
        print("RECOMMENDED ACTIONS:")
        for action in result['recommended_actions']:
            print(f"  → {action}")

    print("="*60 + "\n")
