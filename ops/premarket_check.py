#!/usr/bin/env python3
"""
Pre-Market Check — Runs at 8:45 AM IST before market opens.
Verifies bot is ready and reports status.
"""

import sys
from datetime import datetime
from pathlib import Path

def main():
    repo_root = Path("/Users/ajayoberoi/MediDeals-iOS-App")
    sys.path.insert(0, str(repo_root))

    from ops.health_monitor import HealthMonitor
    from ops.process_manager import BotProcessManager

    print(f"\n{'='*70}")
    print(f"PRE-MARKET READINESS CHECK - {datetime.now().strftime('%Y-%m-%d %H:%M:%S IST')}")
    print(f"{'='*70}\n")

    # Run health check
    monitor = HealthMonitor(str(repo_root))
    result = monitor.run_full_health_check()

    # Print summary
    print(f"Market Hours: {result['market_hours']} | Trading Day: {result['trading_day']}")
    print(f"Health: {result['healthy_checks']}/{result['total_checks']} checks passed\n")

    for check in result['checks']:
        status = "✓" if check['healthy'] else "✗"
        print(f"{status} {check['component']:<20} {check['message']}")

    # Handle issues
    if result['issues']:
        print(f"\n{'='*70}")
        print("ISSUES DETECTED - CORRECTIVE ACTIONS:")
        print(f"{'='*70}\n")

        for issue in result['issues']:
            print(f"Issue: {issue['component']}")
            print(f"  Message: {issue['message']}")
            if issue.get('action'):
                print(f"  Action: {issue['action']}\n")

        # Auto-restart if needed
        if 'RESTART_BOT' in result.get('recommended_actions', []):
            print("Attempting to restart bot...\n")
            manager = BotProcessManager(str(repo_root))
            success, msg = manager.restart()
            print(f"Restart: {msg}\n")

            if success:
                print("✓ Bot restarted successfully. Ready for trading.")
            else:
                print(f"✗ Failed to restart bot: {msg}")
                print("Manual intervention required.")
                sys.exit(1)
    else:
        print(f"\n{'='*70}")
        print("✓ ALL SYSTEMS READY FOR TRADING")
        print(f"{'='*70}\n")

    print(f"Check completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S IST')}\n")

if __name__ == '__main__':
    main()
