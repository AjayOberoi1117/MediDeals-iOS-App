#!/usr/bin/env python3
"""
Unit tests for Operations Engineer V2 components.
"""

import unittest
import tempfile
from pathlib import Path
from datetime import datetime, timedelta
from signal_ledger import SignalLedger
from market_calendar import NSEMarketCalendar


class TestSignalLedger(unittest.TestCase):
    """Test signal ledger functionality."""

    def setUp(self):
        """Create temporary database for testing."""
        self.temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        self.temp_db.close()
        self.ledger = SignalLedger(self.temp_db.name)

    def tearDown(self):
        """Clean up temporary database."""
        Path(self.temp_db.name).unlink(missing_ok=True)

    def test_insert_signal(self):
        """Test inserting a signal."""
        signal_data = {
            'signal_id': 'TEST_001',
            'timestamp': '2026-07-31T11:30:00',
            'symbol': 'RELIANCE',
            'direction': 'BUY',
            'confidence': 'HIGH',
            'entry_price': 3000.0,
            'stop_loss': 2950.0,
            'target_1': 3100.0,
            'target_2': 3150.0,
            'qty': 10,
            'rsi': 65.0,
            'ema_fast': 3010.0,
            'ema_slow': 3005.0
        }

        signal_id = self.ledger.insert_signal(signal_data)
        self.assertEqual(signal_id, 'TEST_001')

    def test_unique_signal_id(self):
        """Test that duplicate signal IDs are rejected."""
        signal_data = {
            'signal_id': 'DUP_001',
            'timestamp': '2026-07-31T11:30:00',
            'symbol': 'INFY',
            'direction': 'BUY',
            'confidence': 'MEDIUM',
            'entry_price': 1200.0
        }

        self.ledger.insert_signal(signal_data)

        # Try to insert same signal ID again
        with self.assertRaises(Exception):
            self.ledger.insert_signal(signal_data)

    def test_get_signals_by_date(self):
        """Test retrieving signals by date."""
        signals = [
            {
                'signal_id': 'SIG_001',
                'timestamp': '2026-07-31T09:30:00',
                'symbol': 'TCS',
                'direction': 'BUY',
                'confidence': 'HIGH'
            },
            {
                'signal_id': 'SIG_002',
                'timestamp': '2026-07-31T10:30:00',
                'symbol': 'HDFCBANK',
                'direction': 'BUY',
                'confidence': 'MEDIUM'
            }
        ]

        for sig in signals:
            self.ledger.insert_signal(sig)

        retrieved = self.ledger.get_signals_by_date('2026-07-31')
        self.assertEqual(len(retrieved), 2)

    def test_statistics(self):
        """Test statistics calculation."""
        # Insert some test signals
        self.ledger.insert_signal({
            'signal_id': 'STAT_001',
            'timestamp': '2026-07-31T09:30:00',
            'symbol': 'RELIANCE',
            'direction': 'BUY',
            'confidence': 'HIGH'
        })

        stats = self.ledger.get_statistics('2026-07-31', '2026-07-31')
        self.assertEqual(stats['total_signals'], 1)


class TestMarketCalendar(unittest.TestCase):
    """Test market calendar functionality."""

    def test_is_trading_day_weekday(self):
        """Test that weekdays are trading days."""
        # Monday, 2026-07-27
        monday = datetime(2026, 7, 27)
        self.assertTrue(NSEMarketCalendar.is_trading_day(monday))

    def test_is_trading_day_weekend(self):
        """Test that weekends are not trading days."""
        # Saturday, 2026-07-25
        saturday = datetime(2026, 7, 25)
        self.assertFalse(NSEMarketCalendar.is_trading_day(saturday))

        # Sunday, 2026-07-26
        sunday = datetime(2026, 7, 26)
        self.assertFalse(NSEMarketCalendar.is_trading_day(sunday))

    def test_is_trading_day_holiday(self):
        """Test that holidays are not trading days."""
        # 2026-01-26 is Republic Day (holiday)
        holiday = datetime(2026, 1, 26)
        self.assertFalse(NSEMarketCalendar.is_trading_day(holiday))

    def test_is_market_open(self):
        """Test market open hours detection."""
        # 9:15 AM - market just opened
        self.assertTrue(NSEMarketCalendar.is_market_open(9, 15))

        # 12:00 PM - market is open
        self.assertTrue(NSEMarketCalendar.is_market_open(12, 0))

        # 3:30 PM - market just closed
        self.assertTrue(NSEMarketCalendar.is_market_open(15, 30))

        # 8:00 AM - market not open
        self.assertFalse(NSEMarketCalendar.is_market_open(8, 0))

        # 4:00 PM - market closed
        self.assertFalse(NSEMarketCalendar.is_market_open(16, 0))

    def test_next_trading_day(self):
        """Test next trading day calculation."""
        # Friday 2026-07-31
        friday = datetime(2026, 7, 31)
        next_day = NSEMarketCalendar.next_trading_day(friday)

        # Should skip Saturday and Sunday, return Monday
        self.assertEqual(next_day.weekday(), 0)  # Monday

    def test_trading_days_in_range(self):
        """Test getting trading days in a range."""
        start = datetime(2026, 7, 27)  # Monday
        end = datetime(2026, 7, 31)    # Friday

        days = NSEMarketCalendar.trading_days_in_range(start, end)

        # Should be 5 trading days
        self.assertEqual(len(days), 5)


class TestProcessManager(unittest.TestCase):
    """Test process manager functionality."""

    def test_pid_file_operations(self):
        """Test PID file read/write."""
        from process_manager import BotProcessManager
        import sys

        with tempfile.TemporaryDirectory() as tmpdir:
            # Create dummy bot script
            bot_script = Path(tmpdir) / "scanner_bot.py"
            bot_script.write_text("print('test')")

            manager = BotProcessManager(tmpdir, "scanner_bot.py")

            # Test writing PID
            manager._write_pid(12345)
            assert manager.pid_file.exists()


if __name__ == '__main__':
    unittest.main()
