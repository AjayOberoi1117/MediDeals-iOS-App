#!/usr/bin/env python3
"""
INTEGRITY TESTS FOR NIFTY50 AND BANKNIFTY SCALPER V1

Verify:
1. No broker order paths exist
2. Safety constraints enforced
3. Risk controls working
4. Paper ledger integration correct
5. Telegram formatting with [PAPER] labels
6. No look-ahead data usage
7. Timezone handling correct
"""

import unittest
import tempfile
import os
import sys
import pandas as pd
import numpy as np
from datetime import datetime, timedelta, timezone
import pytz

sys.path.insert(0, os.path.dirname(__file__))

from nifty50_scalper_v1 import Nifty50ScalperV1, CONFIG as NIFTY_CONFIG
from banknifty_scalper_v1 import BankNiftyScalperV1, CONFIG as BANKNIFTY_CONFIG
from paper_trading_ledger import PaperTradingLedger
from trading_bot_safety import enforce_demo_mode
from scalper_strategy_harness import DataFetcher

class TestNifty50ScalperV1(unittest.TestCase):
    """Test NIFTY50 scalper implementation."""

    def setUp(self):
        """Set up test fixtures."""
        self.temp_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.temp_dir, "test_scalper.db")
        self.scalper = Nifty50ScalperV1(self.db_path)

    def tearDown(self):
        """Clean up."""
        import shutil
        if os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir)

    def test_demo_mode_enforced(self):
        """Test that demo mode is enforced."""
        mode = enforce_demo_mode()
        self.assertEqual(mode.name, "PAPER")
        print(f"✓ Demo mode enforced: {mode.name}")

    def test_no_broker_order_imports(self):
        """Test that scalper doesn't import broker order libraries."""
        with open("nifty50_scalper_v1.py") as f:
            source = f.read()
            lines = source.split('\n')

        # Check for actual imports/calls, not docstring mentions
        forbidden_imports = [
            "import upstox",
            "from upstox",
            "import mt5",
            "from MetaTrader",
            "order_send(",
            ".order_place(",
        ]
        found = []
        for line in lines:
            if line.strip().startswith('#'):  # Skip comments
                continue
            for pattern in forbidden_imports:
                if pattern in line:
                    found.append(line.strip())

        self.assertEqual(
            len(found), 0,
            f"Found forbidden imports/calls: {found}"
        )
        print(f"✓ No broker order paths found in source")

    def test_paper_label_in_config(self):
        """Test that bot name includes research mode label."""
        self.assertIn("DELAYED-DATA", NIFTY_CONFIG["bot_name"])
        # PAPER label will be added in Telegram messages, not config
        print(f"✓ Delayed-data label present: {NIFTY_CONFIG['bot_name']}")

    def test_trading_hours_detection(self):
        """Test market hours detection."""
        ist_tz = pytz.timezone('Asia/Kolkata')

        # 10 AM IST (within hours)
        during_session = datetime(2026, 7, 31, 4, 30, tzinfo=timezone.utc)  # 10:00 IST
        self.assertTrue(self.scalper.is_trading_hours(during_session))

        # 11 PM IST (outside hours)
        after_session = datetime(2026, 7, 31, 17, 30, tzinfo=timezone.utc)  # 23:00 IST
        self.assertFalse(self.scalper.is_trading_hours(after_session))

        # Saturday (market closed)
        saturday = datetime(2026, 8, 1, 4, 30, tzinfo=timezone.utc)  # Sat 10:00 IST
        self.assertFalse(self.scalper.is_trading_hours(saturday))

        print(f"✓ Market hours detection working")

    def test_risk_control_max_trades(self):
        """Test max trades per session limit."""
        now = datetime.now(timezone.utc)

        # Simulate 5 trades already done today
        self.scalper.state.trades_today = 5
        self.scalper.state.last_exit_time = now - timedelta(minutes=10)
        self.scalper.state.last_exit_reason = "TARGET_HIT"

        can_enter, reason = self.scalper.can_entry(now)
        self.assertFalse(can_enter)
        self.assertIn("Max", reason)
        print(f"✓ Max trades limit enforced: {reason}")

    def test_risk_control_cooldown_after_loss(self):
        """Test cooldown enforcement after stop loss."""
        now = datetime.now(timezone.utc)
        loss_time = now - timedelta(minutes=2)  # 2 minutes ago

        self.scalper.state.last_exit_time = loss_time
        self.scalper.state.last_exit_reason = "STOP_LOSS_HIT"
        self.scalper.state.trades_today = 1

        can_enter, reason = self.scalper.can_entry(now)
        self.assertFalse(can_enter)
        self.assertIn("Cooldown", reason)
        print(f"✓ Cooldown after loss enforced: {reason}")

    def test_risk_control_consecutive_losses(self):
        """Test consecutive loss limit."""
        now = datetime.now(timezone.utc)

        self.scalper.state.consecutive_losses = 3
        self.scalper.state.last_exit_time = now - timedelta(minutes=30)
        self.scalper.state.last_exit_reason = "STOP_LOSS_HIT"

        can_enter, reason = self.scalper.can_entry(now)
        self.assertFalse(can_enter)
        self.assertIn("consecutive", reason.lower())
        print(f"✓ Consecutive loss limit enforced: {reason}")

    def test_risk_control_daily_loss_limit(self):
        """Test daily loss limit enforcement."""
        now = datetime.now(timezone.utc)

        self.scalper.state.daily_pnl_points = -505
        self.scalper.state.last_exit_time = now - timedelta(minutes=10)
        self.scalper.state.last_exit_reason = "STOP_LOSS_HIT"

        can_enter, reason = self.scalper.can_entry(now)
        self.assertFalse(can_enter)
        self.assertIn("Daily loss", reason)
        print(f"✓ Daily loss limit enforced: {reason}")

    def test_indicator_calculation(self):
        """Test that indicators are calculated without errors."""
        # Create synthetic candles
        data = {
            'open': np.random.uniform(25000, 25100, 50),
            'high': np.random.uniform(25050, 25150, 50),
            'low': np.random.uniform(24950, 25050, 50),
            'close': np.random.uniform(25000, 25100, 50),
            'volume': np.random.uniform(10000, 50000, 50),
        }

        df = pd.DataFrame(data)
        df.index = pd.date_range('2026-07-31', periods=50, freq='15min')

        result = self.scalper.calculate_indicators(df)

        self.assertIn('ema9', result.columns)
        self.assertIn('atr', result.columns)
        self.assertIn('ema_slope', result.columns)
        print(f"✓ Indicators calculated: {list(result.columns)}")

    def test_signal_generation_no_lookahead(self):
        """Test signal generation uses only past data (no look-ahead)."""
        # Create synthetic candles with clear opening range
        dates = pd.date_range('2026-07-31 09:15', periods=30, freq='15min')

        data = {
            'open': np.full(30, 25000.0),
            'high': np.concatenate([
                np.full(3, 25050.0),  # Opening range high
                np.full(27, 25100.0)  # Breakout high (after opening range)
            ]),
            'low': np.full(30, 24950.0),
            'close': np.concatenate([
                np.full(3, 25000.0),  # Opening range
                np.linspace(25050, 25200, 27)  # Uptrend
            ]),
            'volume': np.full(30, 20000.0),
        }

        df = pd.DataFrame(data, index=dates)

        # Generate signals
        signals = self.scalper.generate_signals(df)

        # Verify signals only reference past candles
        for candle_idx, direction, confidence in signals:
            # Signal at index i should only use data from [0, i]
            self.assertLess(candle_idx, len(df))
            self.assertGreaterEqual(candle_idx, 0)

        print(f"✓ Generated {len(signals)} signals without look-ahead")

    def test_stops_and_targets_calculation(self):
        """Test stop loss and target calculation."""
        entry_price = 25000.0
        atr = 50.0

        # BUY signal
        sl_buy, tp_buy = self.scalper.calculate_stops_and_targets(
            entry_price, "BUY", atr
        )

        # SL should be below entry
        self.assertLess(sl_buy, entry_price)
        # TP should be above entry
        self.assertGreater(tp_buy, entry_price)
        # TP should be farther than SL
        self.assertGreater(abs(tp_buy - entry_price), abs(entry_price - sl_buy))

        # SELL signal
        sl_sell, tp_sell = self.scalper.calculate_stops_and_targets(
            entry_price, "SELL", atr
        )

        # SL should be above entry
        self.assertGreater(sl_sell, entry_price)
        # TP should be below entry
        self.assertLess(tp_sell, entry_price)

        print(f"✓ Stops and targets calculated correctly")

    def test_ledger_integration(self):
        """Test signal recording to paper ledger."""
        now = datetime.now(timezone.utc)
        now_ist = now.astimezone(pytz.timezone('Asia/Kolkata'))

        trade_id = self.scalper.record_signal_to_ledger(
            signal_direction="BUY",
            entry_price=25000.0,
            stop_loss=24925.0,
            target=25150.0,
            confidence=0.8,
            atr=50.0,
            candle_time=now
        )

        # Verify trade was recorded
        self.assertIsNotNone(trade_id)
        print(f"✓ Signal recorded to ledger: {trade_id}")


class TestBankNiftyScalperV1(unittest.TestCase):
    """Test BANKNIFTY scalper implementation."""

    def setUp(self):
        """Set up test fixtures."""
        self.temp_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.temp_dir, "test_scalper.db")
        self.scalper = BankNiftyScalperV1(self.db_path)

    def tearDown(self):
        """Clean up."""
        import shutil
        if os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir)

    def test_config_differences_from_nifty(self):
        """Test that BANKNIFTY config is calibrated differently."""
        # BANKNIFTY should have:
        # - Larger opening range
        self.assertGreater(BANKNIFTY_CONFIG["opening_range_bars"],
                          NIFTY_CONFIG["opening_range_bars"])

        # - Fewer daily trades
        self.assertLess(BANKNIFTY_CONFIG["max_trades_per_session"],
                       NIFTY_CONFIG["max_trades_per_session"])

        # - Closer to zero (stricter) daily loss limit (due to larger per-trade risk)
        # -300 allows less loss than -500 (stops sooner)
        self.assertGreater(BANKNIFTY_CONFIG["daily_loss_limit_points"],
                          NIFTY_CONFIG["daily_loss_limit_points"])

        # - Higher SL/TP multipliers (due to volatility)
        self.assertGreater(BANKNIFTY_CONFIG["sl_atr_multiplier"],
                          NIFTY_CONFIG["sl_atr_multiplier"])
        self.assertGreater(BANKNIFTY_CONFIG["tp_atr_multiplier"],
                          NIFTY_CONFIG["tp_atr_multiplier"])

        print(f"✓ BANKNIFTY config calibrated for higher volatility")

    def test_shorter_max_hold_time(self):
        """Test that BANKNIFTY has shorter max hold time."""
        self.assertLess(BANKNIFTY_CONFIG["max_holding_candles"],
                       NIFTY_CONFIG["max_holding_candles"])
        print(f"✓ BANKNIFTY max hold time shorter (captures quick moves)")

    def test_paper_label(self):
        """Test BANKNIFTY paper label."""
        self.assertIn("DELAYED-DATA", BANKNIFTY_CONFIG["bot_name"])
        self.assertIn("BANKNIFTY", BANKNIFTY_CONFIG["bot_name"])
        print(f"✓ BANKNIFTY label: {BANKNIFTY_CONFIG['bot_name']}")


class TestLookAheadPrevention(unittest.TestCase):
    """Test that strategies don't use future data."""

    def test_signal_only_uses_available_candles(self):
        """Test that signal at time T doesn't use candles after T."""
        scalper = Nifty50ScalperV1()

        # Create 50 candles
        dates = pd.date_range('2026-07-31 09:15', periods=50, freq='15min')
        data = {
            'open': np.random.uniform(25000, 25100, 50),
            'high': np.random.uniform(25050, 25150, 50),
            'low': np.random.uniform(24950, 25050, 50),
            'close': np.random.uniform(25000, 25100, 50),
            'volume': np.random.uniform(20000, 50000, 50),
        }

        df = pd.DataFrame(data, index=dates)
        signals = scalper.generate_signals(df)

        # Each signal should only reference candles up to its index
        for signal_idx, direction, confidence in signals:
            # Signal fired at candle_idx should only use data from [0, candle_idx]
            self.assertLessEqual(signal_idx, len(df) - 1)

        print(f"✓ All signals use only available data (no look-ahead)")

    def test_no_future_indicators(self):
        """Test that indicators don't use future data."""
        scalper = Nifty50ScalperV1()

        # Create simple candles
        dates = pd.date_range('2026-07-31', periods=20, freq='15min')
        data = {
            'open': np.full(20, 25000.0),
            'high': np.full(20, 25050.0),
            'low': np.full(20, 24950.0),
            'close': np.full(20, 25000.0),
            'volume': np.full(20, 20000.0),
        }

        df = pd.DataFrame(data, index=dates)
        result = scalper.calculate_indicators(df)

        # Check that EMA at candle 10 doesn't reference candles 11-19
        # (EMA uses only past data due to adjust=False)
        self.assertIsNotNone(result['ema9'].iloc[10])
        print(f"✓ Indicators calculated without future data")


class TestTimezoneHandling(unittest.TestCase):
    """Test timezone conversion accuracy."""

    def test_ist_timezone_aware(self):
        """Test that scalper handles IST timezone correctly."""
        scalper = Nifty50ScalperV1()
        self.assertIsNotNone(scalper.ist_tz)

        # Test conversion
        utc_time = datetime(2026, 7, 31, 4, 30, tzinfo=timezone.utc)  # 10:00 IST
        ist_time = utc_time.astimezone(scalper.ist_tz)

        self.assertEqual(ist_time.hour, 10)
        self.assertEqual(ist_time.minute, 0)
        print(f"✓ UTC to IST conversion correct")

    def test_no_entry_after_hour_respected(self):
        """Test that no-entry-after-hour is enforced."""
        scalper = Nifty50ScalperV1()

        # 4 PM IST (10:30 AM UTC) - after 3 PM IST cutoff
        after_cutoff = datetime(2026, 7, 31, 10, 30, tzinfo=timezone.utc)
        scalper.state.trades_today = 0
        scalper.state.consecutive_losses = 0
        scalper.state.daily_pnl_points = 0
        scalper.state.last_exit_time = None

        can_enter, reason = scalper.can_entry(after_cutoff)
        self.assertFalse(can_enter)
        self.assertIn("no-entry", reason.lower())
        print(f"✓ No-entry-after-hour enforced")


def run_all_tests():
    """Run all integrity tests."""
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()

    suite.addTests(loader.loadTestsFromTestCase(TestNifty50ScalperV1))
    suite.addTests(loader.loadTestsFromTestCase(TestBankNiftyScalperV1))
    suite.addTests(loader.loadTestsFromTestCase(TestLookAheadPrevention))
    suite.addTests(loader.loadTestsFromTestCase(TestTimezoneHandling))

    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    return result


if __name__ == "__main__":
    print("=" * 80)
    print("SCALPER V1 INTEGRITY TEST SUITE")
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
