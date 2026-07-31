#!/usr/bin/env python3
"""
End-of-Day Report — Runs at 3:45 PM IST after market closes.
Generates reports and sends summary to Telegram.
"""

import sys
import json
from datetime import datetime
from pathlib import Path

def send_telegram_report(message: str, chat_id: str, bot_token: str):
    """Send report summary to Telegram (non-secret content only)."""
    try:
        import requests
        url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
        requests.post(url, data={
            "chat_id": chat_id,
            "text": message,
            "parse_mode": "HTML"
        }, timeout=10)
    except Exception as e:
        print(f"Warning: Failed to send Telegram report: {e}")

def main():
    repo_root = Path("/Users/ajayoberoi/MediDeals-iOS-App")
    sys.path.insert(0, str(repo_root))

    from ops.report_generator import ReportGenerator
    from ops.signal_ledger import SignalLedger

    today = datetime.now().strftime("%Y-%m-%d")

    print(f"\n{'='*70}")
    print(f"END-OF-DAY REPORT GENERATION - {today}")
    print(f"{'='*70}\n")

    # Generate reports
    gen = ReportGenerator(str(repo_root))
    eod_report = gen.generate_eod_report(today)
    filepath = gen.save_report(eod_report, "eod", today)

    print(eod_report)
    print(f"\nReport saved: {filepath}\n")

    # Get stats for Telegram
    ledger = SignalLedger()
    signals = ledger.get_signals_by_date(today)
    stats = ledger.get_statistics(start_date=today, end_date=today)

    if len(signals) > 0:
        telegram_msg = f"""
<b>📊 End-of-Day Summary - {today}</b>

<b>Signals:</b> {len(signals)} generated
<b>Resolved:</b> {stats['resolved_signals']} ({len(signals) and stats['resolved_signals']/len(signals)*100:.0f}%)
<b>Wins:</b> {stats['win_count']} | <b>Losses:</b> {stats['loss_count']}
<b>Win Rate:</b> {stats['win_rate']*100:.1f}%

<i>Full report saved to: {filepath.name}</i>
"""
        # Load env to get Telegram credentials
        try:
            env_file = repo_root / "telegram_bot" / ".env"
            if env_file.exists():
                env_vars = {}
                for line in env_file.read_text().split('\n'):
                    if '=' in line and not line.startswith('#'):
                        k, v = line.split('=', 1)
                        env_vars[k.strip()] = v.strip().strip('"\'')

                bot_token = env_vars.get('TELEGRAM_BOT_TOKEN', '')
                chat_id = env_vars.get('TELEGRAM_CHAT_ID', '')

                if bot_token and chat_id:
                    send_telegram_report(telegram_msg, chat_id, bot_token)
                    print("✓ Telegram summary sent\n")
        except Exception as e:
            print(f"Warning: Could not send Telegram summary: {e}\n")

    print(f"EOD report completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S IST')}\n")

if __name__ == '__main__':
    main()
