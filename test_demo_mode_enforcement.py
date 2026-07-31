"""
TESTS FOR PHASE 2: DEMO-MODE ENFORCEMENT
========================================

Verify that all broker order methods are properly blocked in PAPER mode.
"""

import unittest
import sys
import os

# Add repo to path
sys.path.insert(0, os.path.dirname(__file__))

from trading_bot_safety import (
    TradingMode,
    enforce_demo_mode,
    block_upstox_orders,
    block_metatrader_orders,
    block_all_broker_orders,
    test_broker_order_blocking,
    get_paper_trading_label,
    get_simulated_trade_marker,
)


class TestDemoModeEnforcement(unittest.TestCase):
    """Test demo-mode enforcement."""

    def setUp(self):
        """Clear environment variables before each test."""
        for var in ["TRADING_MODE", "LIVE_TRADING_ENABLED"]:
            if var in os.environ:
                del os.environ[var]

    def test_enforce_demo_mode_defaults_to_paper(self):
        """Test that enforce_demo_mode defaults to PAPER."""
        mode = enforce_demo_mode()
        self.assertEqual(mode, TradingMode.PAPER)

    def test_enforce_demo_mode_respects_env_var(self):
        """Test that TRADING_MODE env var is respected."""
        os.environ["TRADING_MODE"] = "PAPER"
        mode = enforce_demo_mode()
        self.assertEqual(mode, TradingMode.PAPER)

    def test_enforce_demo_mode_blocks_live_mode(self):
        """Test that live mode request raises exception."""
        os.environ["TRADING_MODE"] = "LIVE"
        with self.assertRaises(RuntimeError):
            enforce_demo_mode()

    def test_upstox_orders_blocked_in_paper_mode(self):
        """Test that Upstox orders are blocked in PAPER mode."""
        mode = TradingMode.PAPER
        blocked = block_upstox_orders(mode)
        self.assertTrue(blocked)

    def test_metatrader_orders_blocked_in_paper_mode(self):
        """Test that MetaTrader orders are blocked in PAPER mode."""
        mode = TradingMode.PAPER
        blocked = block_metatrader_orders(mode)
        self.assertTrue(blocked)

    def test_all_broker_orders_blocked_in_paper_mode(self):
        """Test that all broker orders are blocked in PAPER mode."""
        mode = TradingMode.PAPER
        blocked = block_all_broker_orders(mode)
        self.assertTrue(blocked)

    def test_paper_trading_label_formatting(self):
        """Test paper trading label formatting."""
        label = get_paper_trading_label("SCANNER-V2", TradingMode.PAPER)
        self.assertEqual(label, "[PAPER][SCANNER-V2]")
        self.assertIn("PAPER", label)

    def test_simulated_trade_marker(self):
        """Test that simulated trade marker is present."""
        marker = get_simulated_trade_marker()
        self.assertIn("PAPER", marker)
        self.assertIn("NOT SENT TO BROKER", marker)

    def test_broker_order_blocking_results(self):
        """Test broker order blocking results."""
        results = test_broker_order_blocking()
        self.assertTrue(results["upstox_blocked"])
        self.assertTrue(results["metatrader_blocked"])
        self.assertTrue(results["all_blocked"])
        self.assertEqual(results["mode"], "PAPER")


class TestTelegramMonitoring(unittest.TestCase):
    """Test Telegram monitoring integration."""

    def test_telegram_router_import(self):
        """Test that telegram_router can be imported."""
        from telegram_router import TelegramRouter, BotRegistry, TelegramFormatter
        self.assertIsNotNone(TelegramRouter)
        self.assertIsNotNone(BotRegistry)
        self.assertIsNotNone(TelegramFormatter)

    def test_bot_registry_has_bots(self):
        """Test that bot registry contains expected bots."""
        from telegram_router import BotRegistry
        self.assertIn("scanner_v2", BotRegistry.BOTS)
        self.assertTrue(BotRegistry.is_enabled("scanner_v2"))

    def test_telegram_formatting_includes_paper_label(self):
        """Test that Telegram messages include [PAPER] label."""
        from telegram_router import TelegramFormatter
        msg = TelegramFormatter.entry_signal(
            bot_id="scanner_v2",
            symbol="RELIANCE",
            direction="BUY",
            signal_time="2026-07-31 11:30:00",
            timeframe="30m",
            confidence="HIGH",
            entry_price=2815.50,
            stop_loss=2750.00,
            target=2900.00,
            quantity=10,
            signal_id="SIG_001",
            strategy_version="v1",
        )
        self.assertIn("[PAPER]", msg)
        self.assertIn("NO BROKER ORDER", msg)
        self.assertIn("Simulated entry only", msg)


class TestPaperTradingLedger(unittest.TestCase):
    """Test paper-trading ledger."""

    def setUp(self):
        """Set up test ledger in temp location."""
        import tempfile
        self.temp_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.temp_dir, "test_trades.db")

    def tearDown(self):
        """Clean up temp ledger."""
        import shutil
        if os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir)

    def test_ledger_initialization(self):
        """Test that ledger can be initialized."""
        from paper_trading_ledger import PaperTradingLedger
        ledger = PaperTradingLedger(self.db_path)
        self.assertTrue(os.path.exists(self.db_path))

    def test_ledger_records_entry_signal(self):
        """Test that ledger can record entry signals."""
        from paper_trading_ledger import PaperTradingLedger
        ledger = PaperTradingLedger(self.db_path)
        success = ledger.record_entry_signal(
            trade_id="TEST_001",
            bot_id="scanner_v2",
            symbol="RELIANCE",
            direction="BUY",
            entry_price=2815.50,
            quantity=10,
            stop_loss=2750.00,
            target_1=2900.00,
            confidence_level="HIGH",
        )
        self.assertTrue(success)

    def test_ledger_records_exit(self):
        """Test that ledger can record trade exits."""
        from paper_trading_ledger import PaperTradingLedger
        ledger = PaperTradingLedger(self.db_path)

        # Record entry
        ledger.record_entry_signal(
            trade_id="TEST_002",
            bot_id="scanner_v2",
            symbol="TCS",
            direction="BUY",
            entry_price=3500.00,
            quantity=10,
            stop_loss=3400.00,
            target_1=3600.00,
        )

        # Record exit
        success = ledger.record_exit(
            trade_id="TEST_002",
            exit_price=3600.00,
            exit_time="2026-07-31 15:00:00",
            exit_reason="TARGET_HIT",
            brokerage=100.0,
        )
        self.assertTrue(success)


def run_all_tests():
    """Run all tests and return results."""
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()

    suite.addTests(loader.loadTestsFromTestCase(TestDemoModeEnforcement))
    suite.addTests(loader.loadTestsFromTestCase(TestTelegramMonitoring))
    suite.addTests(loader.loadTestsFromTestCase(TestPaperTradingLedger))

    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    return result


if __name__ == "__main__":
    print("=" * 80)
    print("PHASE 2 DEMO-MODE ENFORCEMENT TEST SUITE")
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
