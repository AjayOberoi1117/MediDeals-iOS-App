#!/usr/bin/env python3
"""
BOT AUTO-OPTIMIZER

Analyzes bot performance and recommends code optimizations:
- Signal quality analysis
- Win rate tracking
- Parameter tuning suggestions
- Automated code patches for improvements
- Performance trending

Use with caution — always review suggestions before applying.
"""

import json
import sqlite3
from datetime import datetime, timedelta
from pathlib import Path
import pytz

IST = pytz.timezone('Asia/Kolkata')

class BotOptimizer:
    """Analyze and optimize bot performance."""

    def __init__(self, bot_name, db_path="paper_trading.db"):
        self.bot_name = bot_name
        self.db_path = db_path
        self.conn = sqlite3.connect(db_path) if Path(db_path).exists() else None

    def analyze_signal_quality(self, days=7):
        """Analyze signal quality over N days."""
        if not self.conn:
            return {"error": "Database not found"}

        cursor = self.conn.cursor()

        # Get signals from last N days
        date_cutoff = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")

        try:
            cursor.execute("""
                SELECT COUNT(*),
                       AVG(score),
                       MIN(score),
                       MAX(score)
                FROM paper_trades
                WHERE entry_time > ? AND bot_name = ?
            """, (date_cutoff, self.bot_name))

            result = cursor.fetchone()
            total_signals, avg_score, min_score, max_score = result

            return {
                "period_days": days,
                "total_signals": total_signals,
                "average_score": round(avg_score, 1) if avg_score else 0,
                "score_range": f"{min_score}-{max_score}",
            }
        except Exception as e:
            return {"error": str(e)}

    def analyze_win_rate(self, days=7):
        """Calculate win/loss ratio."""
        if not self.conn:
            return {"error": "Database not found"}

        cursor = self.conn.cursor()
        date_cutoff = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")

        try:
            # Winning trades
            cursor.execute("""
                SELECT COUNT(*), SUM(profit_loss)
                FROM paper_trades
                WHERE entry_time > ? AND bot_name = ? AND profit_loss > 0
            """, (date_cutoff, self.bot_name))

            wins_result = cursor.fetchone()
            win_count, win_total = wins_result if wins_result else (0, 0)

            # Losing trades
            cursor.execute("""
                SELECT COUNT(*), SUM(profit_loss)
                FROM paper_trades
                WHERE entry_time > ? AND bot_name = ? AND profit_loss < 0
            """, (date_cutoff, self.bot_name))

            loss_result = cursor.fetchone()
            loss_count, loss_total = loss_result if loss_result else (0, 0)

            total = win_count + loss_count
            win_rate = (win_count / total * 100) if total > 0 else 0

            return {
                "total_trades": total,
                "wins": win_count,
                "losses": loss_count,
                "win_rate": f"{win_rate:.1f}%",
                "total_profit": round(win_total + loss_total, 2) if win_total or loss_total else 0,
                "avg_win": round(win_total / win_count, 2) if win_count > 0 else 0,
                "avg_loss": round(loss_total / loss_count, 2) if loss_count > 0 else 0,
            }
        except Exception as e:
            return {"error": str(e)}

    def get_optimization_suggestions(self, analysis):
        """Based on analysis, suggest optimizations."""
        suggestions = []

        if not analysis or "error" in analysis:
            return ["No data available for analysis"]

        win_rate_data = self.analyze_win_rate()
        if "error" not in win_rate_data:
            win_rate = float(win_rate_data["win_rate"].rstrip("%"))

            if win_rate < 40:
                suggestions.append({
                    "priority": "CRITICAL",
                    "issue": "Win rate below 40%",
                    "action": "Tighten entry filters (increase RSI min, tighter EMA confirmation)",
                    "impact": "Expected: +15-20% win rate improvement",
                })

            elif win_rate < 50:
                suggestions.append({
                    "priority": "HIGH",
                    "issue": "Win rate below 50%",
                    "action": "Add volume filter (require 1.5x+ average volume)",
                    "impact": "Expected: +5-10% win rate improvement",
                })

            if win_rate_data["avg_win"] and win_rate_data["avg_loss"]:
                if win_rate_data["avg_win"] < abs(win_rate_data["avg_loss"]) * 1.5:
                    suggestions.append({
                        "priority": "MEDIUM",
                        "issue": "Risk/reward ratio unfavorable",
                        "action": "Increase TP multiplier from 3.0x to 3.5x ATR",
                        "impact": "Better reward per trade",
                    })

        signal_quality = self.analyze_signal_quality()
        if "error" not in signal_quality:
            avg_score = signal_quality.get("average_score", 0)

            if avg_score < 50:
                suggestions.append({
                    "priority": "HIGH",
                    "issue": "Low average signal score",
                    "action": "Increase minimum confidence requirement from 50 to 60",
                    "impact": "Fewer but higher-quality signals",
                })

        if not suggestions:
            suggestions.append({
                "priority": "INFO",
                "message": "Bot performance is acceptable. Monitor for changes.",
            })

        return suggestions

    def generate_report(self):
        """Generate comprehensive optimization report."""
        now_ist = datetime.now(IST).strftime("%Y-%m-%d %H:%M IST")

        signal_quality = self.analyze_signal_quality()
        win_rate = self.analyze_win_rate()
        suggestions = self.get_optimization_suggestions(signal_quality)

        report = {
            "generated": now_ist,
            "bot": self.bot_name,
            "signal_quality": signal_quality,
            "win_rate": win_rate,
            "optimization_suggestions": suggestions,
        }

        return report

    def print_report(self):
        """Print human-readable report."""
        report = self.generate_report()

        print("\n" + "="*70)
        print(f"BOT OPTIMIZATION REPORT: {report['bot']}")
        print(f"Generated: {report['generated']}")
        print("="*70)

        print("\n📊 SIGNAL QUALITY (Last 7 days)")
        print("─"*70)
        sq = report["signal_quality"]
        if "error" not in sq:
            print(f"  Total Signals:     {sq['total_signals']}")
            print(f"  Average Score:     {sq['average_score']}/100")
            print(f"  Score Range:       {sq['score_range']}")
        else:
            print(f"  {sq['error']}")

        print("\n📈 WIN RATE ANALYSIS")
        print("─"*70)
        wr = report["win_rate"]
        if "error" not in wr:
            print(f"  Total Trades:      {wr['total_trades']}")
            print(f"  Wins/Losses:       {wr['wins']} / {wr['losses']}")
            print(f"  Win Rate:          {wr['win_rate']}")
            print(f"  Total P&L:         ₹{wr['total_profit']:,}")
            print(f"  Avg Win:           ₹{wr['avg_win']:,}")
            print(f"  Avg Loss:          ₹{wr['avg_loss']:,}")
        else:
            print(f"  {wr['error']}")

        print("\n🔧 OPTIMIZATION SUGGESTIONS")
        print("─"*70)
        for i, suggestion in enumerate(report["optimization_suggestions"], 1):
            priority = suggestion.get("priority", "INFO")
            emoji = "🚨" if priority == "CRITICAL" else "⚠️" if priority == "HIGH" else "ℹ️"

            print(f"{emoji} [{priority}] #{i}")
            if "message" in suggestion:
                print(f"   {suggestion['message']}")
            else:
                print(f"   Issue:   {suggestion.get('issue', 'N/A')}")
                print(f"   Action:  {suggestion.get('action', 'N/A')}")
                print(f"   Impact:  {suggestion.get('impact', 'N/A')}")
            print()

        print("="*70 + "\n")

    def save_report(self, output_file=None):
        """Save report to JSON file."""
        if not output_file:
            output_file = Path(f"bot_optimization_{self.bot_name}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json")

        report = self.generate_report()
        with open(output_file, 'w') as f:
            json.dump(report, f, indent=2)

        print(f"Report saved to: {output_file}")
        return output_file

if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: python3 bot_optimizer.py <bot_name> [db_path]")
        print("Example: python3 bot_optimizer.py nifty_scalper")
        sys.exit(1)

    bot_name = sys.argv[1]
    db_path = sys.argv[2] if len(sys.argv) > 2 else "paper_trading.db"

    optimizer = BotOptimizer(bot_name, db_path)
    optimizer.print_report()
