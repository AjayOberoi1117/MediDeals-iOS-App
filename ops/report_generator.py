#!/usr/bin/env python3
"""
Report Generator — Creates intraday, end-of-day, weekly, and monthly reports.
"""

from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List
import json

class ReportGenerator:
    def __init__(self, repo_root: str):
        self.repo_root = Path(repo_root)
        self.report_dir = self.repo_root / "ops" / "reports"
        self.report_dir.mkdir(parents=True, exist_ok=True)

    def generate_intraday_report(self, date: str = None) -> str:
        """
        Generate intraday report for the current or specified date.
        Returns report text.
        """
        if date is None:
            date = datetime.now().strftime("%Y-%m-%d")

        from ops.signal_ledger import SignalLedger
        ledger = SignalLedger()

        signals = ledger.get_signals_by_date(date)
        stats = ledger.get_statistics(start_date=date, end_date=date)

        report = f"""
================================================================================
                      INTRADAY TRADING REPORT
                            {date}
================================================================================

SIGNAL SUMMARY
--------------
Total Signals:      {len(signals)}
HIGH Confidence:    {sum(1 for s in signals if s['confidence'] == 'HIGH')}
MEDIUM Confidence:  {sum(1 for s in signals if s['confidence'] == 'MEDIUM')}
LOW Confidence:     {sum(1 for s in signals if s['confidence'] == 'LOW')}

PERFORMANCE
-----------
Resolved Signals:   {stats['resolved_signals']}
Wins:               {stats['win_count']}
Losses:             {stats['loss_count']}
Win Rate:           {stats['win_rate']*100:.1f}% ({stats['resolved_signals']} samples)

SIGNALS BY STATUS
-----------------
"""
        for conf in ['HIGH', 'MEDIUM', 'LOW']:
            by_conf = [s for s in stats['by_confidence_status'] if s['confidence'] == conf]
            for item in by_conf:
                report += f"  {conf}: {item['count']} signals | "
                report += f"Targets: {item['targets_hit'] or 0} | "
                report += f"Stops: {item['stops_hit'] or 0}\n"

        report += f"""
SIGNAL DETAILS
--------------
"""
        for sig in signals[:20]:  # Show first 20
            report += f"\n{sig['timestamp']} | {sig['symbol']:<10} | "
            report += f"{sig['direction']:<4} | {sig['confidence']:<6} | "
            report += f"Entry: ₹{sig['entry_price']:.2f} | "
            report += f"SL: ₹{sig['stop_loss']:.2f} | "
            report += f"T1: ₹{sig['target_1']:.2f}\n"

        report += f"""
================================================================================
Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S IST')}
================================================================================
"""
        return report

    def generate_eod_report(self, date: str = None) -> str:
        """Generate end-of-day report."""
        if date is None:
            date = datetime.now().strftime("%Y-%m-%d")

        from ops.signal_ledger import SignalLedger
        ledger = SignalLedger()

        signals = ledger.get_signals_by_date(date)
        stats = ledger.get_statistics(start_date=date, end_date=date)

        report = f"""
================================================================================
                      END OF DAY REPORT
                            {date}
================================================================================

MARKET SUMMARY
--------------
Trading Date:       {date}
Total Signals:      {len(signals)}
Resolved:           {stats['resolved_signals']} ({stats['resolved_signals']/len(signals)*100:.0f}%)
Unresolved:         {len(signals) - stats['resolved_signals']}

TRADING PERFORMANCE
-------------------
Win Rate:           {stats['win_rate']*100:.1f}% ({stats['win_count']}/{stats['resolved_signals']})
Avg MFE:            TBD (need price data)
Avg MAE:            TBD (need price data)

TOP PERFORMERS BY CONFIDENCE
-----------------------------
"""
        for conf in ['HIGH', 'MEDIUM', 'LOW']:
            by_conf = [s for s in stats['by_confidence_status'] if s['confidence'] == conf]
            if by_conf:
                for item in by_conf:
                    if item['count'] > 0:
                        report += f"\n{conf} Confidence ({item['count']} signals):\n"
                        report += f"  Win Rate:  {item['targets_hit'] or 0}/{item['count']} "
                        report += f"({(item['targets_hit'] or 0)/item['count']*100:.0f}%)\n"

        report += f"""
NEXT ACTIONS
------------
• Review unresolved signals with price updates
• Backtest against updated prices if available
• Prepare for next trading session

================================================================================
Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S IST')}
================================================================================
"""
        return report

    def generate_weekly_report(self, week_ending: str = None) -> str:
        """Generate weekly report."""
        if week_ending is None:
            today = datetime.now()
            week_ending = today.strftime("%Y-%m-%d")

        week_start = (datetime.strptime(week_ending, "%Y-%m-%d") - timedelta(days=6)).strftime("%Y-%m-%d")

        from ops.signal_ledger import SignalLedger
        ledger = SignalLedger()

        stats = ledger.get_statistics(start_date=week_start, end_date=week_ending)

        report = f"""
================================================================================
                      WEEKLY PERFORMANCE REPORT
                      Week Ending {week_ending}
================================================================================

WEEK SUMMARY ({week_start} to {week_ending})
--------
Total Signals:      {stats['total_signals']}
Resolved:           {stats['resolved_signals']}
Unresolved:         {stats['total_signals'] - stats['resolved_signals']}

PERFORMANCE METRICS
-------------------
Win Rate:           {stats['win_rate']*100:.1f}% ({stats['win_count']}/{stats['resolved_signals']})
Total Wins:         {stats['win_count']}
Total Losses:       {stats['loss_count']}

By Confidence Level:
"""
        for conf in ['HIGH', 'MEDIUM', 'LOW']:
            by_conf = [s for s in stats['by_confidence_status']
                      if s['confidence'] == conf]
            for item in by_conf:
                if item['count'] > 0:
                    wr = (item['targets_hit'] or 0) / item['count'] * 100
                    report += f"  {conf:<8}: {item['count']:>3} signals, "
                    report += f"Win Rate: {wr:>5.1f}%\n"

        report += f"""
OBSERVATIONS
------------
• Sample size of {stats['resolved_signals']} is {'sufficient' if stats['resolved_signals'] >= 10 else 'too small'} for statistical reliability
• Patterns should be validated with additional weeks of data
• No strategy changes recommended without longer track record

================================================================================
Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S IST')}
================================================================================
"""
        return report

    def generate_monthly_report(self, month: str = None) -> str:
        """Generate monthly report."""
        if month is None:
            today = datetime.now()
            month = today.strftime("%Y-%m")

        # Calculate first and last day of month
        start = datetime.strptime(f"{month}-01", "%Y-%m-%d")
        if start.month == 12:
            end = start.replace(year=start.year + 1, month=1) - timedelta(days=1)
        else:
            end = start.replace(month=start.month + 1) - timedelta(days=1)

        start_date = start.strftime("%Y-%m-%d")
        end_date = end.strftime("%Y-%m-%d")

        from ops.signal_ledger import SignalLedger
        ledger = SignalLedger()

        stats = ledger.get_statistics(start_date=start_date, end_date=end_date)

        report = f"""
================================================================================
                      MONTHLY PERFORMANCE REPORT
                            {month}
================================================================================

MONTH SUMMARY ({start_date} to {end_date})
-----------
Total Signals:      {stats['total_signals']}
Resolved:           {stats['resolved_signals']}
Unresolved:         {stats['total_signals'] - stats['resolved_signals']}
Trading Days:       ~{(end - start).days // 7 * 5} (est. Mon-Fri only)

OVERALL PERFORMANCE
-------------------
Win Rate:           {stats['win_rate']*100:.1f}% ({stats['win_count']}/{stats['resolved_signals']})
Total Wins:         {stats['win_count']}
Total Losses:       {stats['loss_count']}
Avg Win/Loss Ratio: {stats['win_count']/max(stats['loss_count'], 1):.2f}

By Confidence Level:
"""
        for conf in ['HIGH', 'MEDIUM', 'LOW']:
            by_conf = [s for s in stats['by_confidence_status']
                      if s['confidence'] == conf]
            for item in by_conf:
                if item['count'] > 0:
                    wr = (item['targets_hit'] or 0) / item['count'] * 100
                    report += f"  {conf:<8}: {item['count']:>3} signals, "
                    report += f"Win Rate: {wr:>5.1f}%\n"

        report += f"""
KEY INSIGHTS
------------
• Current sample provides {'meaningful' if stats['resolved_signals'] >= 50 else 'limited'} data
• Strategy should be validated over multiple months
• No material strategy changes recommended at this stage

NEXT REVIEW
-----------
Schedule next monthly review on or around the 1st of next month.

================================================================================
Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S IST')}
================================================================================
"""
        return report

    def save_report(self, report_text: str, report_type: str, date: str = None) -> Path:
        """Save report to file."""
        if date is None:
            date = datetime.now().strftime("%Y-%m-%d")

        filename = f"{date}_{report_type}_report.txt"
        filepath = self.report_dir / filename

        filepath.write_text(report_text)
        return filepath


if __name__ == '__main__':
    gen = ReportGenerator(repo_root="/Users/ajayoberoi/MediDeals-iOS-App")

    # Test reports
    today = datetime.now().strftime("%Y-%m-%d")
    print(gen.generate_intraday_report(today))
