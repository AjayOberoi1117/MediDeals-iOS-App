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
from datetime import datetime, timedelta

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
        """Test successful Twelve Data fetch."""
        # Mock successful Twelve Data response
        mock_response = {
            "status": "ok",
            "meta": {"symbol": "BTC/USD", "interval": "1h"},
            "values": [
                {
                    "datetime": "2026-08-09 03:00:00",
                    "open": "65000.00",
                    "high": "65500.00",
                    "low": "64800.00",
                    "close": "65400.00",
                },
                {
                    "datetime": "2026-08-09 04:00:00",
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
            self.assertEqual(df.iloc[-1]["Close"], 65700.00)
            self.assertEqual(list(df.columns), ["Open", "High", "Low", "Close"])

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
        # Create old data (6 minutes old for 15m bars)
        old_time = datetime.now() - timedelta(minutes=6)
        dates = [old_time]
        mock_df = pd.DataFrame({
            "Open": [65000],
            "High": [65100],
            "Low": [64900],
            "Close": [65050],
        }, index=dates)

        provider = MarketDataProvider()
        is_stale = provider._is_stale(mock_df)

        self.assertTrue(is_stale)

    def test_fresh_data_accepted_intraday(self):
        """Test that fresh intraday data is accepted."""
        # Create fresh data (1 minute old)
        fresh_time = datetime.now() - timedelta(minutes=1)
        dates = [fresh_time]
        mock_df = pd.DataFrame({
            "Open": [65000],
            "High": [65100],
            "Low": [64900],
            "Close": [65050],
        }, index=dates)

        provider = MarketDataProvider()
        is_stale = provider._is_stale(mock_df)

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
        mock_response = {
            "status": "ok",
            "values": [
                {
                    "datetime": "2026-08-09 04:00:00",
                    "open": "65400.00",
                    "high": "65800.00",
                    "low": "65300.00",
                    "close": "65700.00",
                },
                {
                    "datetime": "2026-08-09 03:00:00",
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


if __name__ == "__main__":
    unittest.main()
