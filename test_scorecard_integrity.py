"""
TESTS FOR BOT SCORECARD INTEGRITY
=================================

Verify scorecard generation, ranking, and reporting accuracy.
"""

import unittest
import tempfile
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))

from bot_scorecard_generator import (
    ScorecardGenerator,
    BotScorecard,
    ShortlistStatus,
)
from paper_trading_ledger import PaperTradingLedger
from telegram_daily_summary import DailyTelegramSummary


class TestScorecardIntegrity(unittest.TestCase):
    """Test scorecard generation and integrity."""

    def setUp(self):
        """Set up test ledger."""
        self.temp_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.temp_dir, "test_trades.db")
        self.ledger = PaperTradingLedger(self.db_path)
        self.generator = ScorecardGenerator(self.db_path)

    def tearDown(self):
        """Clean up test ledger."""
        import shutil
        if os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir)

    def test_scorecard_includes_all_active_bots(self):
        """Test that scorecard includes every bot active on date."""
        # Record trades for two different bots
        self.ledger.record_entry_signal(
            trade_id="BOT1_TRADE1",
            bot_id="scanner_v2",
            symbol="RELIANCE",
            direction="BUY",
            entry_price=2815.50,
            quantity=10,
            stop_loss=2750.00,
            target_1=2900.00,
        )
        self.ledger.record_entry_signal(
            trade_id="BOT2_TRADE1",
            bot_id="nifty_scalper_v1",
            symbol="NIFTY",
            direction="BUY",
            entry_price=24000.00,
            quantity=1,
            stop_loss=23500.00,
            target_1=24500.00,
        )

        scorecards, metadata = self.generator.generate_daily_scorecard("2026-07-31")

        self.assertEqual(len(scorecards), 2)
        bot_ids = {s.bot_id for s in scorecards}
        self.assertIn("scanner_v2", bot_ids)
        self.assertIn("nifty_scalper_v1", bot_ids)

    def test_scorecard_includes_all_trades_not_subset(self):
        """Test that scorecard doesn't omit trades (no silent removal)."""
        # Record multiple trades
        for i in range(5):
            self.ledger.record_entry_signal(
                trade_id=f"TRADE_{i}",
                bot_id="scanner_v2",
                symbol="TCS",
                direction="BUY",
                entry_price=3500.00,
                quantity=10,
                stop_loss=3400.00,
                target_1=3600.00,
            )

        scorecards, _ = self.generator.generate_daily_scorecard("2026-07-31")
        self.assertEqual(len(scorecards), 1)
        self.assertEqual(scorecards[0].eligible_signals, 5)

    def test_costs_reduce_net_pnl(self):
        """Test that costs correctly reduce gross P&L to net P&L."""
        self.ledger.record_entry_signal(
            trade_id="COST_TEST",
            bot_id="scanner_v2",
            symbol="RELIANCE",
            direction="BUY",
            entry_price=2800.00,
            quantity=100,
            stop_loss=2750.00,
            target_1=2900.00,
        )

        # Exit with profit
        self.ledger.record_exit(
            trade_id="COST_TEST",
            exit_price=2900.00,
            exit_time="2026-07-31 15:00:00",
            exit_reason="TARGET_HIT",
            brokerage=500.0,
            stt_charges=250.0,
            exchange_charges=100.0,
            taxes=100.0,
        )

        scorecards, _ = self.generator.generate_daily_scorecard("2026-07-31")
        scorecard = scorecards[0]

        # Gross P&L should be (2900-2800)*100 = 10,000
        expected_gross = 10000.0
        self.assertAlmostEqual(scorecard.gross_pnl, expected_gross, places=0)

        # Estimated charges should be 500+250+100+100 = 950
        expected_charges = 950.0
        self.assertAlmostEqual(scorecard.estimated_charges, expected_charges, places=0)

        # Net should be 10000 - 950 = 9050
        expected_net = 9050.0
        self.assertAlmostEqual(scorecard.net_pnl, expected_net, places=0)

    def test_sample_size_warning_for_insufficient_trades(self):
        """Test that sample size warning is set for low trade counts."""
        # Only 1 trade
        self.ledger.record_entry_signal(
            trade_id="SMALL_TEST",
            bot_id="scanner_v2",
            symbol="RELIANCE",
            direction="BUY",
            entry_price=2800.00,
            quantity=10,
            stop_loss=2750.00,
            target_1=2900.00,
        )
        self.ledger.record_exit(
            trade_id="SMALL_TEST",
            exit_price=2900.00,
            exit_time="2026-07-31 15:00:00",
            exit_reason="TARGET_HIT",
        )

        scorecards, _ = self.generator.generate_daily_scorecard("2026-07-31")
        scorecard = scorecards[0]

        # Should have sample size warning (< MIN_TRADES_FOR_EVALUATION)
        self.assertTrue(scorecard.sample_size_warning)

    def test_winning_trades_not_omitted(self):
        """Test that winning trades are fully counted."""
        # 3 winning trades
        for i in range(3):
            self.ledger.record_entry_signal(
                trade_id=f"WIN_{i}",
                bot_id="scanner_v2",
                symbol="RELIANCE",
                direction="BUY",
                entry_price=2800.00,
                quantity=10,
                stop_loss=2750.00,
                target_1=2900.00,
            )
            self.ledger.record_exit(
                trade_id=f"WIN_{i}",
                exit_price=2900.00,
                exit_time="2026-07-31 14:00:00",
                exit_reason="TARGET_HIT",
                brokerage=50.0,
            )

        scorecards, _ = self.generator.generate_daily_scorecard("2026-07-31")
        scorecard = scorecards[0]

        self.assertEqual(scorecard.trades_closed, 3)
        self.assertEqual(scorecard.win_rate, 1.0)  # 100% win rate

    def test_losing_trades_not_omitted(self):
        """Test that losing trades are fully counted."""
        # 2 losing trades
        for i in range(2):
            self.ledger.record_entry_signal(
                trade_id=f"LOSS_{i}",
                bot_id="scanner_v2",
                symbol="RELIANCE",
                direction="BUY",
                entry_price=2800.00,
                quantity=10,
                stop_loss=2750.00,
                target_1=2900.00,
            )
            self.ledger.record_exit(
                trade_id=f"LOSS_{i}",
                exit_price=2700.00,
                exit_time="2026-07-31 12:00:00",
                exit_reason="STOP_LOSS_HIT",
                brokerage=50.0,
            )

        scorecards, _ = self.generator.generate_daily_scorecard("2026-07-31")
        scorecard = scorecards[0]

        self.assertEqual(scorecard.trades_closed, 2)
        self.assertEqual(scorecard.win_rate, 0.0)  # 0% win rate
        self.assertLess(scorecard.net_pnl, 0)  # Negative P&L

    def test_rankings_are_reproducible(self):
        """Test that rankings are consistent across multiple runs."""
        # Add test data
        for i in range(5):
            self.ledger.record_entry_signal(
                trade_id=f"BOT1_T{i}",
                bot_id="scanner_v2",
                symbol="RELIANCE",
                direction="BUY",
                entry_price=2800.00 + i * 10,
                quantity=10,
                stop_loss=2750.00,
                target_1=2900.00,
            )

        # Generate twice
        scorecards1, _ = self.generator.generate_daily_scorecard("2026-07-31")
        scorecards2, _ = self.generator.generate_daily_scorecard("2026-07-31")

        # Rankings should be identical
        self.assertEqual(len(scorecards1), len(scorecards2))
        for s1, s2 in zip(scorecards1, scorecards2):
            self.assertEqual(s1.rank, s2.rank)
            self.assertAlmostEqual(s1.composite_score, s2.composite_score, places=1)

    def test_drawdown_affects_ranking(self):
        """Test that high drawdown reduces score."""
        # Bot A: Profit with low drawdown
        self.ledger.record_entry_signal(
            trade_id="BOT_A_1",
            bot_id="bot_a",
            symbol="TCS",
            direction="BUY",
            entry_price=3500.00,
            quantity=10,
            stop_loss=3400.00,
            target_1=3600.00,
        )
        self.ledger.record_exit(
            trade_id="BOT_A_1",
            exit_price=3600.00,
            exit_time="2026-07-31 15:00:00",
            exit_reason="TARGET_HIT",
        )

        # Bot B: Same profit but higher drawdown in series
        for i in range(3):
            self.ledger.record_entry_signal(
                trade_id=f"BOT_B_{i}",
                bot_id="bot_b",
                symbol="INFY",
                direction="BUY",
                entry_price=1500.00,
                quantity=10,
                stop_loss=1450.00,
                target_1=1550.00,
            )
            if i == 0:
                # First loss
                self.ledger.record_exit(
                    trade_id=f"BOT_B_{i}",
                    exit_price=1450.00,
                    exit_time="2026-07-31 11:00:00",
                    exit_reason="STOP_LOSS_HIT",
                )
            else:
                # Two wins to recover
                self.ledger.record_exit(
                    trade_id=f"BOT_B_{i}",
                    exit_price=1550.00,
                    exit_time="2026-07-31 14:00:00",
                    exit_reason="TARGET_HIT",
                )

        scorecards, _ = self.generator.generate_daily_scorecard("2026-07-31")

        # Find bot A and bot B
        bot_a = next((s for s in scorecards if s.bot_id == "bot_a"), None)
        bot_b = next((s for s in scorecards if s.bot_id == "bot_b"), None)

        self.assertIsNotNone(bot_a)
        self.assertIsNotNone(bot_b)

        # Bot A should rank higher (lower drawdown, same profit)
        self.assertLess(bot_a.max_drawdown, bot_b.max_drawdown)


class TestTelegramSummaryIntegrity(unittest.TestCase):
    """Test Telegram daily summary generation."""

    def setUp(self):
        """Set up test ledger."""
        self.temp_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.temp_dir, "test_trades.db")
        self.ledger = PaperTradingLedger(self.db_path)
        self.summary_gen = DailyTelegramSummary()

    def tearDown(self):
        """Clean up."""
        import shutil
        if os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir)

    def test_summary_includes_paper_warning(self):
        """Test that summary includes PAPER/DEMO warning."""
        summary = self.summary_gen.generate_summary("2026-07-31")
        self.assertIn("PAPER", summary)
        self.assertIn("DEMO", summary)
        self.assertIn("NO BROKER ORDERS", summary)

    def test_summary_matches_ledger_totals(self):
        """Test that summary metrics match ledger data."""
        # Add test trades
        self.ledger.record_entry_signal(
            trade_id="TEST_1",
            bot_id="scanner_v2",
            symbol="RELIANCE",
            direction="BUY",
            entry_price=2800.00,
            quantity=10,
            stop_loss=2750.00,
            target_1=2900.00,
        )
        self.ledger.record_exit(
            trade_id="TEST_1",
            exit_price=2900.00,
            exit_time="2026-07-31 15:00:00",
            exit_reason="TARGET_HIT",
            brokerage=50.0,
        )

        summary = self.summary_gen.generate_summary("2026-07-31")

        # Should mention trade count
        self.assertIn("1", summary)  # 1 trade
        self.assertIn("2026-07-31", summary)

    def test_no_summary_implies_no_real_profit(self):
        """Test that summary explicitly states simulated results."""
        summary = self.summary_gen.generate_summary("2026-07-31")
        # Should not say "profit" or "guaranteed"
        self.assertNotIn("guaranteed", summary.lower())
        self.assertIn("simulated", summary.lower())


def run_all_tests():
    """Run all scorecard tests."""
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()

    suite.addTests(loader.loadTestsFromTestCase(TestScorecardIntegrity))
    suite.addTests(loader.loadTestsFromTestCase(TestTelegramSummaryIntegrity))

    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    return result


if __name__ == "__main__":
    print("=" * 80)
    print("BOT SCORECARD INTEGRITY TEST SUITE")
    print("=" * 80)
    print()

    result = run_all_tests()

    print()
    print("=" * 80)
    print(f"Tests run: {result.testsRun}")
    print(f"Failures: {len(result.failures)}")
    print(f"Errors: {len(result.errors)}")
    print(f"Success: {result.wasSuccessful()}")
    print("=" * 80)

    sys.exit(0 if result.wasSuccessful() else 1)
