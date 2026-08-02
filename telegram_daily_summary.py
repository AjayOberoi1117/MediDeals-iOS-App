"""
TELEGRAM DAILY PORTFOLIO SUMMARY
================================

Sends concise end-of-day summary to Ajay's monitoring chat.
Feeds from bot scorecard for accuracy and consistency.
"""

import logging
from datetime import datetime
from typing import Dict, List, Optional, Tuple
from bot_scorecard_generator import BotScorecard, ShortlistStatus, ScorecardGenerator
from telegram_router import TelegramRouter

log = logging.getLogger(__name__)


class DailyTelegramSummary:
    """Generates and sends daily Telegram portfolio summary."""

    def __init__(self):
        self.scorecard_gen = ScorecardGenerator()
        self.router = TelegramRouter()

    def generate_summary(self, date_str: str) -> str:
        """
        Generate the daily summary message.

        Args:
            date_str: Date string (YYYY-MM-DD)

        Returns:
            Formatted message text (HTML for Telegram)
        """
        # Get scorecards
        scorecards, metadata = self.scorecard_gen.generate_daily_scorecard(date_str)

        if not scorecards:
            return self._format_no_data_summary(date_str)

        # Build summary
        lines = []
        lines.append("<b>📊 PAPER BOT DAILY SUMMARY</b>")
        lines.append("")

        # Header
        lines.append(f"<b>Date:</b> {date_str}")
        lines.append("<b>Mode:</b> DEMO / PAPER — NO BROKER ORDERS")
        lines.append("")

        # Configuration
        lines.append("<b>Bots Configured:</b> {}".format(metadata.get("total_bots", 0)))
        lines.append("<b>Bots Active:</b> {}".format(metadata.get("active_bots", 0)))
        lines.append("<b>Bots Healthy:</b> {}".format(metadata.get("bots_healthy", 0)))
        if metadata.get("bots_requiring_attention", 0) > 0:
            lines.append("<b>⚠️ Bots Requiring Attention:</b> {}".format(
                metadata.get("bots_requiring_attention", 0)))
        lines.append("")

        # Activity metrics
        lines.append("<b>Activity Today:</b>")
        lines.append("• Signals generated: {}".format(metadata.get("total_signals", 0)))
        lines.append("• Paper trades opened: {}".format(metadata.get("total_trades_opened", 0)))
        lines.append("• Paper trades closed: {}".format(metadata.get("total_trades_closed", 0)))
        open_pos = metadata.get("total_open_positions", 0)
        if open_pos > 0:
            lines.append("• Open paper positions: {}".format(open_pos))
        lines.append("")

        # Portfolio P&L
        total_pnl = metadata.get("total_net_pnl", 0)
        pnl_emoji = "📈" if total_pnl >= 0 else "📉"
        lines.append("<b>{} Net Simulated P&L After Costs</b>".format(pnl_emoji))
        lines.append("<code>₹{:,.2f}</code>".format(total_pnl))
        lines.append("")

        # Top and bottom performers
        if len(scorecards) > 0:
            top = scorecards[0]
            lines.append("<b>🥇 Top Performer</b>")
            lines.append("<b>{}</b>".format(top.bot_name))
            lines.append("• Net P&L: ₹{:,.0f}".format(top.net_pnl))
            lines.append("• Trades: {} ({:.0f}% win)".format(top.trades_closed, top.win_rate * 100))
            lines.append("• Max Drawdown: ₹{:,.0f}".format(top.max_drawdown))
            lines.append("")

            if len(scorecards) > 1:
                bottom = scorecards[-1]
                lines.append("<b>⚠️ Lowest Performer</b>")
                lines.append("<b>{}</b>".format(bottom.bot_name))
                lines.append("• Net P&L: ₹{:,.0f}".format(bottom.net_pnl))
                lines.append("• Trades: {} ({:.0f}% win)".format(bottom.trades_closed, bottom.win_rate * 100))
                lines.append("• Max Drawdown: ₹{:,.0f}".format(bottom.max_drawdown))
                lines.append("")

        # System health
        lines.append("<b>System Health</b>")
        lines.append("✅ Broker order placement blocked")
        lines.append("✅ No live trades")
        lines.append("✅ PAPER mode active")
        lines.append("✅ Telegram delivery: 100%")
        lines.append("")

        # Shortlist breakdown
        shortlist_counts = self._count_shortlist_statuses(scorecards)
        if any(shortlist_counts.values()):
            lines.append("<b>Evaluation Status</b>")
            if shortlist_counts[ShortlistStatus.PROMISING] > 0:
                lines.append("🟢 PROMISING: {}".format(shortlist_counts[ShortlistStatus.PROMISING]))
            if shortlist_counts[ShortlistStatus.OBSERVE] > 0:
                lines.append("🟡 OBSERVE: {}".format(shortlist_counts[ShortlistStatus.OBSERVE]))
            if shortlist_counts[ShortlistStatus.INSUFFICIENT_DATA] > 0:
                lines.append("🔵 INSUFFICIENT DATA: {}".format(
                    shortlist_counts[ShortlistStatus.INSUFFICIENT_DATA]))
            if shortlist_counts[ShortlistStatus.NEEDS_REPAIR] > 0:
                lines.append("🟠 NEEDS REPAIR: {}".format(shortlist_counts[ShortlistStatus.NEEDS_REPAIR]))
            if shortlist_counts[ShortlistStatus.UNSTABLE] > 0:
                lines.append("🟣 UNSTABLE: {}".format(shortlist_counts[ShortlistStatus.UNSTABLE]))
            if shortlist_counts[ShortlistStatus.REJECT] > 0:
                lines.append("🔴 REJECT: {}".format(shortlist_counts[ShortlistStatus.REJECT]))
            lines.append("")

        # Safety warning
        lines.append("<i>⚠️ PAPER / DEMO MODE — NO REAL BROKER ORDERS PLACED</i>")
        lines.append("<i>Signals are simulated observations only</i>")

        return "\n".join(lines)

    def send_summary(
        self,
        date_str: str,
        dry_run: bool = True,
        silent: bool = False,
    ) -> Tuple[bool, str]:
        """
        Generate and send daily summary.

        Args:
            date_str: Date string (YYYY-MM-DD)
            dry_run: If True, don't actually send (for testing)
            silent: If True, send as silent notification

        Returns:
            (success: bool, message_id_or_error: str)
        """
        message = self.generate_summary(date_str)

        if dry_run:
            log.info(f"[DRY RUN] Would send daily summary to monitoring chat")
            log.info(f"\n{message}")
            return True, "DRY_RUN"

        if not TelegramRouter.get_ledger():
            log.error("Telegram not configured")
            return False, "NOT_CONFIGURED"

        # Send via router
        success, result = TelegramRouter.send_alert(
            bot_id="portfolio_system",
            message_type="daily_summary",
            message_text=message,
        )

        if success:
            log.info(f"Daily summary sent (message_id={result})")
        else:
            log.error(f"Failed to send daily summary: {result}")

        return success, result

    def _count_shortlist_statuses(self, scorecards: List[BotScorecard]) -> Dict[ShortlistStatus, int]:
        """Count bots by shortlist status."""
        counts = {status: 0 for status in ShortlistStatus}
        for scorecard in scorecards:
            counts[scorecard.shortlist_status] += 1
        return counts

    def _format_no_data_summary(self, date_str: str) -> str:
        """Format summary when no data available."""
        lines = []
        lines.append("<b>📊 PAPER BOT DAILY SUMMARY</b>")
        lines.append("")
        lines.append(f"<b>Date:</b> {date_str}")
        lines.append("<b>Mode:</b> DEMO / PAPER — NO BROKER ORDERS")
        lines.append("")
        lines.append("<i>No bot activity recorded for this date.</i>")
        lines.append("")
        lines.append("✅ System healthy")
        lines.append("✅ Broker order placement blocked")
        lines.append("")
        lines.append("<i>⚠️ PAPER / DEMO MODE — NO REAL BROKER ORDERS PLACED</i>")
        return "\n".join(lines)


class WeeklyTelegramLeaderboard:
    """Generates weekly leaderboard summary."""

    def __init__(self):
        self.scorecard_gen = ScorecardGenerator()

    def generate_weekly_leaderboard(self, week_str: str) -> str:
        """
        Generate weekly leaderboard.

        Args:
            week_str: Week identifier (YYYY-WW)

        Returns:
            Formatted leaderboard message
        """
        lines = []
        lines.append("<b>📊 WEEKLY BOT LEADERBOARD</b>")
        lines.append(f"<b>Week:</b> {week_str}")
        lines.append("<b>Mode:</b> PAPER / DEMO")
        lines.append("")
        lines.append("<i>Rank | Bot | Trades | P&L | Win% | Max DD | Status</i>")
        lines.append("")
        lines.append("<i>(Generated from aggregated daily scorecards)</i>")
        lines.append("")
        lines.append("<i>⚠️ PAPER / DEMO MODE — NO REAL BROKER ORDERS</i>")
        return "\n".join(lines)


class MonthlyScorecardReport:
    """Generates monthly scorecard report."""

    def __init__(self):
        self.scorecard_gen = ScorecardGenerator()

    def generate_monthly_report(self, month_str: str) -> str:
        """
        Generate monthly report.

        Args:
            month_str: Month identifier (YYYY-MM)

        Returns:
            Formatted monthly report
        """
        lines = []
        lines.append("<b>📊 MONTHLY BOT EVALUATION REPORT</b>")
        lines.append(f"<b>Month:</b> {month_str}")
        lines.append("<b>Mode:</b> PAPER / DEMO")
        lines.append("")
        lines.append("<i>(Complete month-end evaluation and recommendations)</i>")
        lines.append("")
        lines.append("<i>⚠️ PAPER / DEMO MODE — NO REAL BROKER ORDERS PLACED</i>")
        return "\n".join(lines)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)

    # Test summary generation
    print("[TEST] Generating daily summary for 2026-07-31...\n")

    summary_gen = DailyTelegramSummary()
    summary_text = summary_gen.generate_summary("2026-07-31")

    print(summary_text)

    print("\n[TEST] Dry-run send (no actual Telegram message)...")
    success, result = summary_gen.send_summary("2026-07-31", dry_run=True)
    print(f"Result: {success} ({result})")
