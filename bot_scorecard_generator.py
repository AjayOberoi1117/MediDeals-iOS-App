"""
BOT SCORECARD GENERATOR
======================

Daily scorecard for all active bots with composite ranking.
Feeds performance leaderboard and Telegram summary.

Ranking is NOT by profit alone. Uses documented composite scoring method.
"""

import json
import csv
import sqlite3
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Tuple, Optional
from pathlib import Path
from enum import Enum

from paper_trading_ledger import PaperTradingLedger, TradeStatus

log = logging.getLogger(__name__)


class ShortlistStatus(Enum):
    """Bot shortlist status for evaluation."""
    INSUFFICIENT_DATA = "INSUFFICIENT_DATA"
    OBSERVE = "OBSERVE"
    PROMISING = "PROMISING"
    NEEDS_REPAIR = "NEEDS_REPAIR"
    UNSTABLE = "UNSTABLE"
    REJECT = "REJECT"
    CANDIDATE_FOR_CONTROLLED_PILOT = "CANDIDATE_FOR_CONTROLLED_PILOT"


class BotScorecard:
    """Individual bot scorecard entry."""

    def __init__(self, bot_id: str, bot_name: str):
        self.bot_id = bot_id
        self.bot_name = bot_name
        self.strategy_version = "unknown"
        self.runtime_status = "UNKNOWN"
        self.eligible_signals = 0
        self.trades_opened = 0
        self.trades_closed = 0
        self.open_positions = 0
        self.gross_pnl = 0.0
        self.estimated_charges = 0.0
        self.net_pnl = 0.0
        self.win_rate = 0.0
        self.avg_win = 0.0
        self.avg_loss = 0.0
        self.profit_factor = 0.0
        self.expectancy = 0.0
        self.max_drawdown = 0.0
        self.max_losing_streak = 0
        self.avg_holding_period_min = 0
        self.duplicate_alerts = 0
        self.missed_alerts = 0
        self.telegram_delivery_rate = 0.0
        self.data_quality_incidents = 0
        self.crashes_or_restarts = 0
        self.operational_reliability_score = 0.0  # 0-100
        self.strategy_stability_score = 0.0  # 0-100
        self.sample_size_warning = False
        self.shortlist_status = ShortlistStatus.INSUFFICIENT_DATA
        self.rank = 0
        self.composite_score = 0.0

    def to_dict(self) -> Dict:
        """Convert to dictionary for JSON/CSV export."""
        return {
            "rank": self.rank,
            "bot_name": self.bot_name,
            "bot_id": self.bot_id,
            "strategy_version": self.strategy_version,
            "runtime_status": self.runtime_status,
            "eligible_signals": self.eligible_signals,
            "trades_opened": self.trades_opened,
            "trades_closed": self.trades_closed,
            "open_positions": self.open_positions,
            "gross_pnl": round(self.gross_pnl, 2),
            "estimated_charges": round(self.estimated_charges, 2),
            "net_pnl": round(self.net_pnl, 2),
            "win_rate": round(self.win_rate * 100, 1),
            "avg_win": round(self.avg_win, 2),
            "avg_loss": round(self.avg_loss, 2),
            "profit_factor": round(self.profit_factor, 2),
            "expectancy": round(self.expectancy, 2),
            "max_drawdown": round(self.max_drawdown, 2),
            "max_losing_streak": self.max_losing_streak,
            "avg_holding_period_min": self.avg_holding_period_min,
            "duplicate_alerts": self.duplicate_alerts,
            "missed_alerts": self.missed_alerts,
            "telegram_delivery_rate": round(self.telegram_delivery_rate * 100, 1),
            "data_quality_incidents": self.data_quality_incidents,
            "crashes_or_restarts": self.crashes_or_restarts,
            "operational_reliability_score": round(self.operational_reliability_score, 1),
            "strategy_stability_score": round(self.strategy_stability_score, 1),
            "sample_size_warning": self.sample_size_warning,
            "shortlist_status": self.shortlist_status.value,
            "composite_score": round(self.composite_score, 1),
        }


class ScorecardGenerator:
    """Generates bot scorecards from paper trading ledger."""

    # Scoring weights (must sum to 100)
    SCORING_WEIGHTS = {
        "net_pnl_normalized": 20,  # 0-100 scale, best returns
        "win_rate": 15,  # 0-100
        "profit_factor": 15,  # Rewards consistency
        "max_drawdown": 15,  # Lower is better (0-100 inverted)
        "operational_reliability": 15,  # 0-100
        "strategy_stability": 10,  # 0-100 (consistency across sessions)
    }

    # Sample size thresholds
    MIN_TRADES_FOR_EVALUATION = 5
    MIN_DAYS_FOR_EVALUATION = 2
    PREFERRED_TRADES = 20
    PREFERRED_DAYS = 5

    def __init__(self, ledger_db_path: Optional[str] = None):
        """Initialize scorecard generator."""
        self.ledger = PaperTradingLedger(ledger_db_path)
        self.log = logging.getLogger(__name__)

    def generate_daily_scorecard(self, date_str: str) -> Tuple[List[BotScorecard], Dict]:
        """
        Generate scorecard for a specific date.

        Args:
            date_str: Date string (YYYY-MM-DD)

        Returns:
            (ranked_scorecards, metadata)
        """
        try:
            with sqlite3.connect(self.ledger.db_path) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()

                # Get all bots active on this date
                cursor.execute("""
                    SELECT DISTINCT bot_id FROM trades
                    WHERE DATE(entry_time) = ?
                    ORDER BY bot_id
                """, (date_str,))

                bot_ids = [row["bot_id"] for row in cursor.fetchall()]

                if not bot_ids:
                    return [], {"total_bots": 0, "active_bots": 0, "date": date_str}

                # Generate scorecard for each bot
                scorecards = []
                for bot_id in bot_ids:
                    scorecard = self._generate_bot_scorecard(bot_id, date_str)
                    scorecards.append(scorecard)

                # Rank and sort
                self._rank_scorecards(scorecards)
                scorecards.sort(key=lambda s: s.rank)

                metadata = {
                    "date": date_str,
                    "total_bots": len(scorecards),
                    "active_bots": len([s for s in scorecards if s.runtime_status == "RUNNING"]),
                    "bots_healthy": len([s for s in scorecards if s.shortlist_status not in [
                        ShortlistStatus.NEEDS_REPAIR,
                        ShortlistStatus.REJECT,
                    ]]),
                    "bots_requiring_attention": len([s for s in scorecards if s.shortlist_status in [
                        ShortlistStatus.NEEDS_REPAIR,
                        ShortlistStatus.REJECT,
                    ]]),
                    "total_signals": sum(s.eligible_signals for s in scorecards),
                    "total_trades_opened": sum(s.trades_opened for s in scorecards),
                    "total_trades_closed": sum(s.trades_closed for s in scorecards),
                    "total_open_positions": sum(s.open_positions for s in scorecards),
                    "total_net_pnl": sum(s.net_pnl for s in scorecards),
                }

                return scorecards, metadata

        except Exception as e:
            self.log.error(f"Failed to generate daily scorecard: {e}")
            return [], {"error": str(e)}

    def _generate_bot_scorecard(self, bot_id: str, date_str: str) -> BotScorecard:
        """Generate scorecard for a specific bot on a specific date."""
        scorecard = BotScorecard(bot_id, bot_id)

        try:
            with sqlite3.connect(self.ledger.db_path) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()

                # Get all trades for this bot on this date
                cursor.execute("""
                    SELECT * FROM trades
                    WHERE bot_id = ? AND DATE(entry_time) = ?
                    ORDER BY entry_time
                """, (bot_id, date_str))

                trades = cursor.fetchall()

                if not trades:
                    return scorecard

                # Parse trades
                trade_list = [dict(row) for row in trades]

                # Calculate metrics
                scorecard.eligible_signals = len(trade_list)
                scorecard.trades_opened = len([t for t in trade_list if t["entry_time"]])
                scorecard.trades_closed = len([t for t in trade_list if t["status"] == TradeStatus.EXITED.value])
                scorecard.open_positions = scorecard.trades_opened - scorecard.trades_closed

                # P&L metrics
                exited_trades = [t for t in trade_list if t["status"] == TradeStatus.EXITED.value]
                if exited_trades:
                    scorecard.gross_pnl = sum(t["gross_pnl"] or 0 for t in exited_trades)
                    scorecard.estimated_charges = sum(
                        (t["brokerage"] or 0) + (t["stt_charges"] or 0) +
                        (t["exchange_charges"] or 0) + (t["taxes"] or 0)
                        for t in exited_trades
                    )
                    scorecard.net_pnl = sum(t["net_pnl"] or 0 for t in exited_trades)

                    # Win/loss metrics
                    wins = [t for t in exited_trades if t["net_pnl"] and t["net_pnl"] > 0]
                    losses = [t for t in exited_trades if t["net_pnl"] and t["net_pnl"] < 0]

                    if exited_trades:
                        scorecard.win_rate = len(wins) / len(exited_trades)

                    if wins:
                        scorecard.avg_win = sum(t["net_pnl"] for t in wins) / len(wins)

                    if losses:
                        scorecard.avg_loss = abs(sum(t["net_pnl"] for t in losses) / len(losses))

                    if scorecard.avg_loss > 0 and scorecard.avg_win > 0:
                        scorecard.profit_factor = sum(t["net_pnl"] for t in wins) / abs(sum(t["net_pnl"] for t in losses))

                    if exited_trades:
                        scorecard.expectancy = scorecard.net_pnl / len(exited_trades)

                    # Drawdown (simplified)
                    running_pnl = 0
                    peak = 0
                    max_dd = 0
                    for trade in exited_trades:
                        running_pnl += trade["net_pnl"] or 0
                        if running_pnl > peak:
                            peak = running_pnl
                        dd = peak - running_pnl
                        if dd > max_dd:
                            max_dd = dd
                    scorecard.max_drawdown = max_dd

                # Average holding period
                if scorecard.trades_closed > 0:
                    holding_periods = []
                    for trade in exited_trades:
                        if trade["entry_time"] and trade["exit_time"]:
                            try:
                                entry = datetime.fromisoformat(trade["entry_time"])
                                exit_time = datetime.fromisoformat(trade["exit_time"])
                                holding_periods.append((exit_time - entry).total_seconds() / 60)
                            except:
                                pass
                    if holding_periods:
                        scorecard.avg_holding_period_min = int(sum(holding_periods) / len(holding_periods))

                # Sample size warning
                scorecard.sample_size_warning = (
                    scorecard.trades_closed < self.MIN_TRADES_FOR_EVALUATION
                )

                # Determine shortlist status
                scorecard.shortlist_status = self._determine_shortlist_status(scorecard)

                # Strategy stability (placeholder - would need multi-day data)
                if scorecard.net_pnl > 0:
                    scorecard.strategy_stability_score = min(75 + (scorecard.win_rate * 25), 100)
                else:
                    scorecard.strategy_stability_score = max(25 - (abs(scorecard.net_pnl) / max(scorecard.gross_pnl, 1) * 50), 0)

                # Operational reliability (placeholder - would need crash/restart data)
                scorecard.operational_reliability_score = 95  # Default high until proven otherwise

                return scorecard

        except Exception as e:
            self.log.error(f"Failed to generate scorecard for {bot_id}: {e}")
            return scorecard

    def _determine_shortlist_status(self, scorecard: BotScorecard) -> ShortlistStatus:
        """Determine shortlist status based on scorecard metrics."""
        # Insufficient data
        if scorecard.trades_closed < self.MIN_TRADES_FOR_EVALUATION:
            return ShortlistStatus.INSUFFICIENT_DATA

        # Reject: Consistently unprofitable
        if scorecard.win_rate < 0.25 and scorecard.net_pnl < -1000:
            return ShortlistStatus.REJECT

        # Needs repair: Has issues but not rejected
        if scorecard.data_quality_incidents > 0 or scorecard.crashes_or_restarts > 0:
            return ShortlistStatus.NEEDS_REPAIR

        # Unstable: High variance
        if scorecard.max_drawdown > abs(scorecard.net_pnl) * 2 and scorecard.trades_closed < 15:
            return ShortlistStatus.UNSTABLE

        # Promising: Good metrics, sufficient data
        if (scorecard.win_rate >= 0.5 and scorecard.profit_factor >= 1.5 and
            scorecard.trades_closed >= self.PREFERRED_TRADES and
            scorecard.max_drawdown < abs(scorecard.net_pnl)):
            return ShortlistStatus.PROMISING

        # Default: Observe
        return ShortlistStatus.OBSERVE

    def _rank_scorecards(self, scorecards: List[BotScorecard]):
        """Rank scorecards using composite scoring method."""
        if not scorecards:
            return

        # Calculate component scores
        for scorecard in scorecards:
            components = self._calculate_component_scores(scorecard)
            scorecard.composite_score = sum(
                components.get(key, 0) * weight / 100
                for key, weight in self.SCORING_WEIGHTS.items()
            )

        # Sort by composite score (descending)
        scorecards.sort(key=lambda s: s.composite_score, reverse=True)

        # Assign ranks
        for rank, scorecard in enumerate(scorecards, 1):
            scorecard.rank = rank

    def _calculate_component_scores(self, scorecard: BotScorecard) -> Dict[str, float]:
        """Calculate individual component scores (0-100 scale)."""
        components = {}

        # Net P&L normalized (0-100, relative to best performer)
        # Placeholder: 50 base + 50 for positive
        if scorecard.net_pnl > 0:
            components["net_pnl_normalized"] = 50 + min(50, (scorecard.net_pnl / 5000) * 50)
        else:
            components["net_pnl_normalized"] = max(0, 50 + (scorecard.net_pnl / -5000) * 50)

        # Win rate (0-100)
        components["win_rate"] = scorecard.win_rate * 100

        # Profit factor (0-100, capped at 100)
        components["profit_factor"] = min(100, scorecard.profit_factor * 50)

        # Max drawdown (0-100, inverted - lower drawdown is better)
        components["max_drawdown"] = max(0, 100 - (scorecard.max_drawdown / 5000) * 100)

        # Operational reliability (0-100)
        components["operational_reliability"] = scorecard.operational_reliability_score

        # Strategy stability (0-100)
        components["strategy_stability"] = scorecard.strategy_stability_score

        # Apply sample-size penalty
        if scorecard.sample_size_warning:
            for key in components:
                components[key] *= 0.75  # 25% penalty for insufficient data

        return components

    def export_to_markdown(self, scorecards: List[BotScorecard], metadata: Dict) -> str:
        """Export scorecard to markdown format."""
        lines = []
        lines.append("# BOT SCORECARD\n")
        lines.append(f"**Date**: {metadata.get('date', 'N/A')}\n")
        lines.append(f"**Generated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S IST')}\n")
        lines.append(f"**Mode**: PAPER / DEMO — NO BROKER ORDERS\n")
        lines.append("")

        lines.append("## Summary\n")
        lines.append(f"- Total bots configured: {metadata.get('total_bots', 0)}")
        lines.append(f"- Bots active: {metadata.get('active_bots', 0)}")
        lines.append(f"- Bots healthy: {metadata.get('bots_healthy', 0)}")
        lines.append(f"- Signals generated: {metadata.get('total_signals', 0)}")
        lines.append(f"- Trades opened: {metadata.get('total_trades_opened', 0)}")
        lines.append(f"- Trades closed: {metadata.get('total_trades_closed', 0)}")
        lines.append(f"- **Total net P&L**: ₹{metadata.get('total_net_pnl', 0):,.2f}")
        lines.append("")

        lines.append("## Leaderboard\n")
        lines.append("| Rank | Bot | Trades | P&L | Win% | PF | MDD | Reliability | Shortlist |")
        lines.append("|------|-----|--------|-----|------|----|----|-------------|-----------|")

        for scorecard in scorecards:
            lines.append(
                f"| {scorecard.rank} | {scorecard.bot_name} | "
                f"{scorecard.trades_closed} | "
                f"₹{scorecard.net_pnl:,.0f} | "
                f"{scorecard.win_rate*100:.1f}% | "
                f"{scorecard.profit_factor:.2f} | "
                f"₹{scorecard.max_drawdown:,.0f} | "
                f"{scorecard.operational_reliability_score:.0f}% | "
                f"{scorecard.shortlist_status.value} |"
            )

        lines.append("")
        lines.append("⚠️ **PAPER / DEMO MODE — NO REAL BROKER ORDERS**\n")

        return "\n".join(lines)

    def export_to_csv(self, scorecards: List[BotScorecard]) -> str:
        """Export scorecard to CSV format."""
        if not scorecards:
            return "No data"

        output = []
        fieldnames = list(scorecards[0].to_dict().keys())

        # CSV header
        output.append(",".join(fieldnames))

        # CSV rows
        for scorecard in scorecards:
            row_dict = scorecard.to_dict()
            output.append(",".join(str(row_dict.get(field, "")) for field in fieldnames))

        return "\n".join(output)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)

    # Test scorecard generation
    generator = ScorecardGenerator()

    print("\n[TEST] Generating daily scorecard for 2026-07-31...")
    scorecards, metadata = generator.generate_daily_scorecard("2026-07-31")

    print(f"Scorecards generated: {len(scorecards)}")
    print(f"Metadata: {metadata}")

    if scorecards:
        print("\n[MARKDOWN OUTPUT]")
        print(generator.export_to_markdown(scorecards, metadata))

        print("\n[CSV OUTPUT (first 3 rows)]")
        csv_output = generator.export_to_csv(scorecards)
        for line in csv_output.split("\n")[:3]:
            print(line)
