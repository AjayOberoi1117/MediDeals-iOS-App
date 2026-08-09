"""
Unit tests for market_data_provider.py

Tests Twelve Data primary and yfinance fallback paths without hitting real APIs.
Uses mocked HTTP responses.
"""

import os
import time
import json
import unittest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta, timezone

import pandas as pd
import requests

from market_data_provider import MarketDataProvider, fetch_ohlc


class TestMarketDataProvider(unittest.TestCase):
    """Test MarketDataProvider with mocked responses."""

    def setUp(self):
        """Create provider instance for each test."""
        self.provider = MarketDataProvider(cache_ttl_seconds=60)

    def test_symbol_mapping(self):
        """Test that symbol mappings are correct."""
        self.assertEqual(self.provider.TWELVE_DATA_SYMBOLS["BTC-USD"], "BTC/USD")
        self.assertEqual(self.provider.TWELVE_DATA_SYMBOLS["GC=F"], "XAU/USD")
        self.assertEqual(self.provider.TWELVE_DATA_SYMBOLS["EURUSD=X"], "EUR/USD")
        self.assertEqual(self.provider.TWELVE_DATA_SYMBOLS["GBPUSD=X"], "GBP/USD")

    def test_interval_mapping(self):
        """Test that interval mappings are correct."""
        self.assertEqual(self.provider.INTERVAL_MAP["1h"], "1h")
        self.assertEqual(self.provider.INTERVAL_MAP["15m"], "15min")
        self.assertEqual(self.provider.INTERVAL_MAP["1d"], "1day")

    def test_twelve_data_success_path(self):
        """Test successful Twelve Data fetch with UTC-aware timestamps."""
        # Mock successful Twelve Data response (recent times to avoid stale rejection)
        now = datetime.now(timezone.utc)
        recent_time = (now - timedelta(minutes=30)).strftime("%Y-%m-%d %H:%M:%S")

        mock_response = {
            "status": "ok",
            "meta": {"symbol": "BTC/USD", "interval": "1h"},
            "values": [
                {
                    "datetime": recent_time,
                    "open": "65000.00",
                    "high": "65500.00",
                    "low": "64800.00",
                    "close": "65400.00",
                },
                {
                    "datetime": (now - timedelta(minutes=60)).strftime("%Y-%m-%d %H:%M:%S"),
                    "open": "65400.00",
                    "high": "65800.00",
                    "low": "65300.00",
                    "close": "65700.00",
                },
            ],
        }

        with patch.object(requests, "get") as mock_get:
            mock_get.return_value.json.return_value = mock_response
            mock_get.return_value.raise_for_status.return_value = None

            # Provide API key
            os.environ["TWELVE_DATA_KEY"] = "test_key"
            provider = MarketDataProvider()

            df = provider._fetch_twelve_data("BTC-USD", "1h")

            self.assertIsNotNone(df)
            self.assertEqual(len(df), 2)
            # After sorting by datetime, the most recent bar is last
            self.assertEqual(df.iloc[-1]["Close"], 65400.00)  # 30 min old
            self.assertEqual(df.iloc[0]["Close"], 65700.00)   # 60 min old
            self.assertEqual(list(df.columns), ["Open", "High", "Low", "Close"])
            # Verify UTC-aware index
            self.assertIsNotNone(df.index.tz)

    def test_twelve_data_api_error(self):
        """Test Twelve Data API error response."""
        mock_response = {
            "status": "error",
            "message": "Invalid API key",
        }

        with patch.object(requests, "get") as mock_get:
            mock_get.return_value.json.return_value = mock_response
            mock_get.return_value.raise_for_status.return_value = None

            os.environ["TWELVE_DATA_KEY"] = "invalid_key"
            provider = MarketDataProvider()

            df = provider._fetch_twelve_data("BTC-USD", "1h")

            self.assertIsNone(df)

    def test_twelve_data_timeout(self):
        """Test Twelve Data request timeout."""
        with patch.object(requests, "get") as mock_get:
            mock_get.side_effect = requests.exceptions.Timeout("Connection timeout")

            os.environ["TWELVE_DATA_KEY"] = "test_key"
            provider = MarketDataProvider(request_timeout=1)

            df = provider._fetch_twelve_data("BTC-USD", "1h")

            self.assertIsNone(df)

    def test_yfinance_fallback_success(self):
        """Test yfinance fallback when Twelve Data is unavailable."""
        # Create mock DataFrame with recent dates
        now = datetime.now()
        dates = pd.date_range(now - timedelta(hours=5), periods=5, freq="1h")
        mock_df = pd.DataFrame({
            "Open": [65000, 65100, 65200, 65300, 65400],
            "High": [65100, 65200, 65300, 65400, 65500],
            "Low": [64900, 65000, 65100, 65200, 65300],
            "Close": [65050, 65150, 65250, 65350, 65450],
        }, index=dates)

        with patch("yfinance.download") as mock_yf:
            mock_yf.return_value = mock_df

            os.environ["TWELVE_DATA_KEY"] = ""
            provider = MarketDataProvider()

            df = provider._fetch_yfinance("BTC-USD", "60d", "1h")

            self.assertIsNotNone(df)
            self.assertEqual(len(df), 5)

    def test_yfinance_retry_on_failure(self):
        """Test yfinance retries on transient failure."""
        now = datetime.now()
        dates = pd.date_range(now - timedelta(hours=2), periods=2, freq="1h")
        mock_df = pd.DataFrame({
            "Open": [65000, 65100],
            "High": [65100, 65200],
            "Low": [64900, 65000],
            "Close": [65050, 65150],
        }, index=dates)

        with patch("yfinance.download") as mock_yf:
            # First call fails, second succeeds
            mock_yf.side_effect = [
                requests.exceptions.ConnectionError("Network error"),
                mock_df,
            ]

            os.environ["TWELVE_DATA_KEY"] = ""
            provider = MarketDataProvider()

            df = provider._fetch_yfinance("BTC-USD", "60d", "1h")

            self.assertIsNotNone(df)
            self.assertEqual(len(df), 2)

    def test_stale_data_rejection_intraday(self):
        """Test that stale intraday data is rejected."""
        # Create old data (25 minutes old for 15m bars, beyond 15m + 5m grace)
        old_time = datetime.now(timezone.utc) - timedelta(minutes=25)
        dates = pd.DatetimeIndex([old_time], tz="UTC")
        mock_df = pd.DataFrame({
            "Open": [65000],
            "High": [65100],
            "Low": [64900],
            "Close": [65050],
        }, index=dates)

        provider = MarketDataProvider()
        is_stale = provider._is_stale(mock_df, "15min")

        self.assertTrue(is_stale)

    def test_fresh_data_accepted_intraday(self):
        """Test that fresh intraday data is accepted."""
        # Create fresh data (5 minutes old for 15m bar)
        fresh_time = datetime.now(timezone.utc) - timedelta(minutes=5)
        dates = pd.DatetimeIndex([fresh_time], tz="UTC")
        mock_df = pd.DataFrame({
            "Open": [65000],
            "High": [65100],
            "Low": [64900],
            "Close": [65050],
        }, index=dates)

        provider = MarketDataProvider()
        is_stale = provider._is_stale(mock_df, "15min")

        self.assertFalse(is_stale)

    def test_caching(self):
        """Test that data is cached correctly."""
        now = datetime.now()
        dates = pd.date_range(now - timedelta(hours=2), periods=2, freq="1h")
        mock_df = pd.DataFrame({
            "Open": [65000, 65100],
            "High": [65100, 65200],
            "Low": [64900, 65000],
            "Close": [65050, 65150],
        }, index=dates)

        with patch("yfinance.download") as mock_yf:
            mock_yf.return_value = mock_df

            os.environ["TWELVE_DATA_KEY"] = ""
            provider = MarketDataProvider(cache_ttl_seconds=60)

            # First call fetches from yfinance
            df1 = provider.fetch_ohlc("BTC-USD", "60d", "1h")
            self.assertIsNotNone(df1)
            call_count_1 = mock_yf.call_count

            # Second call uses cache (should not call yfinance again)
            df2 = provider.fetch_ohlc("BTC-USD", "60d", "1h")
            self.assertIsNotNone(df2)
            call_count_2 = mock_yf.call_count

            # yfinance should not be called again (cache was used)
            self.assertEqual(call_count_1, call_count_2)

    def test_empty_response_handling(self):
        """Test handling of empty API responses."""
        mock_response = {
            "status": "ok",
            "values": [],
        }

        with patch.object(requests, "get") as mock_get:
            mock_get.return_value.json.return_value = mock_response
            mock_get.return_value.raise_for_status.return_value = None

            os.environ["TWELVE_DATA_KEY"] = "test_key"
            provider = MarketDataProvider()

            df = provider._fetch_twelve_data("BTC-USD", "1h")

            self.assertIsNone(df)

    def test_malformed_response_handling(self):
        """Test handling of malformed API responses."""
        mock_response = {
            "status": "ok",
            "values": [
                {
                    "datetime": "2026-08-09 03:00:00",
                    "open": "invalid",  # Not a number
                    "high": "65500.00",
                    "low": "64800.00",
                    "close": "65400.00",
                },
            ],
        }

        with patch.object(requests, "get") as mock_get:
            mock_get.return_value.json.return_value = mock_response
            mock_get.return_value.raise_for_status.return_value = None

            os.environ["TWELVE_DATA_KEY"] = "test_key"
            provider = MarketDataProvider()

            df = provider._fetch_twelve_data("BTC-USD", "1h")

            # Should skip the malformed bar and return None (not enough bars)
            self.assertIsNone(df)

    def test_fallback_when_twelve_data_unavailable(self):
        """Test fallback to yfinance when Twelve Data is unavailable."""
        now = datetime.now()
        dates = pd.date_range(now - timedelta(hours=2), periods=2, freq="1h")
        mock_yf_df = pd.DataFrame({
            "Open": [65000, 65100],
            "High": [65100, 65200],
            "Low": [64900, 65000],
            "Close": [65050, 65150],
        }, index=dates)

        with patch.object(requests, "get") as mock_get:
            mock_get.side_effect = requests.exceptions.ConnectionError("Twelve Data unavailable")

            with patch("yfinance.download") as mock_yf:
                mock_yf.return_value = mock_yf_df

                os.environ["TWELVE_DATA_KEY"] = "test_key"
                provider = MarketDataProvider()

                df = provider.fetch_ohlc("BTC-USD", "60d", "1h")

                self.assertIsNotNone(df)
                self.assertEqual(len(df), 2)

    def test_datetime_sorting(self):
        """Test that returned data has sorted datetime index."""
        now = datetime.now(timezone.utc)
        newer_time = (now - timedelta(minutes=30)).strftime("%Y-%m-%d %H:%M:%S")
        older_time = (now - timedelta(minutes=90)).strftime("%Y-%m-%d %H:%M:%S")

        mock_response = {
            "status": "ok",
            "values": [
                {
                    "datetime": newer_time,
                    "open": "65400.00",
                    "high": "65800.00",
                    "low": "65300.00",
                    "close": "65700.00",
                },
                {
                    "datetime": older_time,
                    "open": "65000.00",
                    "high": "65500.00",
                    "low": "64800.00",
                    "close": "65400.00",
                },
            ],
        }

        with patch.object(requests, "get") as mock_get:
            mock_get.return_value.json.return_value = mock_response
            mock_get.return_value.raise_for_status.return_value = None

            os.environ["TWELVE_DATA_KEY"] = "test_key"
            provider = MarketDataProvider()

            df = provider._fetch_twelve_data("BTC-USD", "1h")

            self.assertIsNotNone(df)
            # Check that index is sorted ascending
            self.assertTrue(df.index.is_monotonic_increasing)
            # Check that index is UTC-aware
            self.assertIsNotNone(df.index.tz)


class TestMarketDataProviderIntegration(unittest.TestCase):
    """Integration tests for the module-level functions."""

    def test_fetch_ohlc_function(self):
        """Test the convenience function fetch_ohlc."""
        now = datetime.now()
        dates = pd.date_range(now - timedelta(hours=2), periods=2, freq="1h")
        mock_df = pd.DataFrame({
            "Open": [65000, 65100],
            "High": [65100, 65200],
            "Low": [64900, 65000],
            "Close": [65050, 65150],
        }, index=dates)

        with patch("yfinance.download") as mock_yf:
            mock_yf.return_value = mock_df
            os.environ["TWELVE_DATA_KEY"] = ""

            df = fetch_ohlc("BTC-USD", "60d", "1h")

            self.assertIsNotNone(df)
            self.assertEqual(len(df), 2)


class TestTimezoneAwareness(unittest.TestCase):
    """Test UTC-aware timestamp handling and interval-aware freshness."""

    def test_twelve_data_utc_parsing(self):
        """Test that Twelve Data timestamps are parsed as UTC-aware."""
        mock_response = {
            "status": "ok",
            "values": [
                {
                    "datetime": "2026-08-09 06:55:00",  # UTC
                    "open": "65000.00",
                    "high": "65100.00",
                    "low": "64900.00",
                    "close": "65050.00",
                },
            ],
        }

        with patch.object(requests, "get") as mock_get:
            mock_get.return_value.json.return_value = mock_response
            mock_get.return_value.raise_for_status.return_value = None

            os.environ["TWELVE_DATA_KEY"] = "test_key"
            provider = MarketDataProvider()

            df = provider._fetch_twelve_data("BTC-USD", "1h")

            self.assertIsNotNone(df)
            # Check that index is timezone-aware UTC
            self.assertIsNotNone(df.index.tz)
            self.assertEqual(str(df.index.tz), "UTC")

    def test_future_timestamp_rejection(self):
        """Test that future timestamps are rejected."""
        # Create a bar 2 hours in the future
        future_time = datetime.now(timezone.utc) + timedelta(hours=2)
        dates = [future_time]
        mock_df = pd.DataFrame({
            "Open": [65000],
            "High": [65100],
            "Low": [64900],
            "Close": [65050],
        }, index=pd.DatetimeIndex(dates, tz="UTC"))

        provider = MarketDataProvider()
        has_future = provider._has_future_bars(mock_df)

        self.assertTrue(has_future)

    def test_small_clock_skew_accepted(self):
        """Test that small clock skew (< 60s) is accepted."""
        # Create a bar 30 seconds in the future
        skewed_time = datetime.now(timezone.utc) + timedelta(seconds=30)
        dates = [skewed_time]
        mock_df = pd.DataFrame({
            "Open": [65000],
            "High": [65100],
            "Low": [64900],
            "Close": [65050],
        }, index=pd.DatetimeIndex(dates, tz="UTC"))

        provider = MarketDataProvider()
        has_future = provider._has_future_bars(mock_df)

        self.assertFalse(has_future)

    def test_interval_aware_freshness_1m(self):
        """Test 1-minute interval freshness: allow up to 2 minutes old."""
        # Create bar 1 minute old
        old_time = datetime.now(timezone.utc) - timedelta(minutes=1)
        dates = [old_time]
        mock_df = pd.DataFrame({
            "Open": [65000],
            "High": [65100],
            "Low": [64900],
            "Close": [65050],
        }, index=pd.DatetimeIndex(dates, tz="UTC"))

        provider = MarketDataProvider()
        is_stale = provider._is_stale(mock_df, "1min")

        self.assertFalse(is_stale)

    def test_interval_aware_freshness_1m_too_old(self):
        """Test 1-minute interval: reject if >2 minutes old."""
        # Create bar 3 minutes old
        old_time = datetime.now(timezone.utc) - timedelta(minutes=3)
        dates = [old_time]
        mock_df = pd.DataFrame({
            "Open": [65000],
            "High": [65100],
            "Low": [64900],
            "Close": [65050],
        }, index=pd.DatetimeIndex(dates, tz="UTC"))

        provider = MarketDataProvider()
        is_stale = provider._is_stale(mock_df, "1min")

        self.assertTrue(is_stale)

    def test_interval_aware_freshness_15m(self):
        """Test 15-minute interval: accept legitimate completed bar."""
        # Create bar 15 minutes old (legitimate completed bar)
        old_time = datetime.now(timezone.utc) - timedelta(minutes=15)
        dates = [old_time]
        mock_df = pd.DataFrame({
            "Open": [65000],
            "High": [65100],
            "Low": [64900],
            "Close": [65050],
        }, index=pd.DatetimeIndex(dates, tz="UTC"))

        provider = MarketDataProvider()
        is_stale = provider._is_stale(mock_df, "15min")

        # Should be fresh (15m + 5m grace = 20m max, bar is only 15m old)
        self.assertFalse(is_stale)

    def test_interval_aware_freshness_15m_too_old(self):
        """Test 15-minute interval: reject if >20 minutes old."""
        # Create bar 25 minutes old (beyond 15m + 5m grace)
        old_time = datetime.now(timezone.utc) - timedelta(minutes=25)
        dates = [old_time]
        mock_df = pd.DataFrame({
            "Open": [65000],
            "High": [65100],
            "Low": [64900],
            "Close": [65050],
        }, index=pd.DatetimeIndex(dates, tz="UTC"))

        provider = MarketDataProvider()
        is_stale = provider._is_stale(mock_df, "15min")

        self.assertTrue(is_stale)

    def test_interval_aware_freshness_1h(self):
        """Test 1-hour interval: accept legitimate completed bar."""
        # Create bar 1 hour old
        old_time = datetime.now(timezone.utc) - timedelta(hours=1)
        dates = [old_time]
        mock_df = pd.DataFrame({
            "Open": [65000],
            "High": [65100],
            "Low": [64900],
            "Close": [65050],
        }, index=pd.DatetimeIndex(dates, tz="UTC"))

        provider = MarketDataProvider()
        is_stale = provider._is_stale(mock_df, "1h")

        # Should be fresh (1h + 10m grace = 70m max, bar is only 60m old)
        self.assertFalse(is_stale)

    def test_interval_aware_freshness_1d(self):
        """Test 1-day interval: accept bar up to 2 days old."""
        # Create bar 1.5 days old
        old_time = datetime.now(timezone.utc) - timedelta(days=1.5)
        dates = [old_time]
        mock_df = pd.DataFrame({
            "Open": [65000],
            "High": [65100],
            "Low": [64900],
            "Close": [65050],
        }, index=pd.DatetimeIndex(dates, tz="UTC"))

        provider = MarketDataProvider()
        is_stale = provider._is_stale(mock_df, "1day")

        self.assertFalse(is_stale)

    def test_naive_timestamp_rejected(self):
        """Test that naive (non-UTC-aware) timestamps are rejected."""
        # Create bar with naive datetime (no timezone)
        naive_time = datetime.now() - timedelta(hours=1)
        dates = [naive_time]
        mock_df = pd.DataFrame({
            "Open": [65000],
            "High": [65100],
            "Low": [64900],
            "Close": [65050],
        }, index=dates)

        provider = MarketDataProvider()
        is_stale = provider._is_stale(mock_df, "1h")

        # Should reject because timestamp is naive
        self.assertTrue(is_stale)

    def test_ohlc_data_preserved_during_tz_conversion(self):
        """Test that OHLC values are not altered during timezone conversion."""
        mock_response = {
            "status": "ok",
            "values": [
                {
                    "datetime": "2026-08-09 06:55:00",
                    "open": "65000.50",
                    "high": "65100.75",
                    "low": "64899.25",
                    "close": "65050.00",
                },
            ],
        }

        with patch.object(requests, "get") as mock_get:
            mock_get.return_value.json.return_value = mock_response
            mock_get.return_value.raise_for_status.return_value = None

            os.environ["TWELVE_DATA_KEY"] = "test_key"
            provider = MarketDataProvider()

            df = provider._fetch_twelve_data("BTC-USD", "1h")

            self.assertIsNotNone(df)
            # Verify OHLC values are exact
            self.assertAlmostEqual(df.iloc[0]["Open"], 65000.50)
            self.assertAlmostEqual(df.iloc[0]["High"], 65100.75)
            self.assertAlmostEqual(df.iloc[0]["Low"], 64899.25)
            self.assertAlmostEqual(df.iloc[0]["Close"], 65050.00)


if __name__ == "__main__":
    unittest.main()
