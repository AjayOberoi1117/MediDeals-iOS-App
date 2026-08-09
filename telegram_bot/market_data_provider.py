"""
Market Data Provider — Twelve Data Primary + Yahoo Finance Fallback

Provides normalized OHLC data from either Twelve Data (primary) or yfinance (fallback).
Handles symbol/interval normalization, caching, timeout, and stale-data detection.

Never logs API keys or credentials.
"""

import os
import time
import logging
from datetime import datetime, timedelta

import pandas as pd
import requests
import yfinance as yf

log = logging.getLogger(__name__)


class MarketDataProvider:
    """Fetches OHLC data from Twelve Data (primary) or yfinance (fallback)."""

    # Symbol mapping: internal symbol -> Twelve Data symbol
    TWELVE_DATA_SYMBOLS = {
        "BTC-USD": "BTC/USD",
        "GC=F": "XAU/USD",
        "EURUSD=X": "EUR/USD",
        "GBPUSD=X": "GBP/USD",
    }

    # Interval mapping: yfinance interval -> Twelve Data interval
    INTERVAL_MAP = {
        "1m": "1min",
        "5m": "5min",
        "15m": "15min",
        "30m": "30min",
        "1h": "1h",
        "1d": "1day",
    }

    def __init__(self, cache_ttl_seconds=840, request_timeout=30):
        """
        Initialize provider.

        Args:
            cache_ttl_seconds: Cache time-to-live in seconds
            request_timeout: HTTP request timeout in seconds
        """
        self.cache_ttl = cache_ttl_seconds
        self.timeout = request_timeout
        self.twelve_data_key = os.getenv("TWELVE_DATA_KEY", "").strip()
        self._cache = {}  # {(symbol, interval): (timestamp, dataframe)}

    def fetch_ohlc(self, yf_symbol, period, interval):
        """
        Fetch OHLC data using Twelve Data (primary) or yfinance (fallback).

        Args:
            yf_symbol: Yahoo Finance symbol (e.g., "BTC-USD", "EURUSD=X")
            period: Period for yfinance fallback (e.g., "60d")
            interval: Interval (e.g., "1h", "15m")

        Returns:
            DataFrame with columns [Open, High, Low, Close] or None if all sources fail
        """
        # Check cache
        cache_key = (yf_symbol, interval)
        if cache_key in self._cache:
            ts, df = self._cache[cache_key]
            if time.time() - ts < self.cache_ttl:
                log.debug(f"Cache hit: {yf_symbol} {interval} (age {time.time()-ts:.0f}s)")
                return df

        # Try Twelve Data first
        if self.twelve_data_key:
            df = self._fetch_twelve_data(yf_symbol, interval)
            if df is not None:
                self._cache[cache_key] = (time.time(), df)
                return df
            log.warning(f"TWELVE_DATA_FAILED for {yf_symbol} {interval}, attempting yfinance fallback")

        # Fall back to yfinance
        df = self._fetch_yfinance(yf_symbol, period, interval)
        if df is not None:
            self._cache[cache_key] = (time.time(), df)
            return df

        log.error(f"All data providers failed for {yf_symbol} {interval}")
        return None

    def _fetch_twelve_data(self, yf_symbol, interval):
        """
        Fetch from Twelve Data API.

        Args:
            yf_symbol: Yahoo Finance symbol to convert to Twelve Data format
            interval: Interval (e.g., "1h", "15m")

        Returns:
            DataFrame or None
        """
        if not self.twelve_data_key:
            return None

        # Convert symbol
        twelve_data_symbol = self.TWELVE_DATA_SYMBOLS.get(yf_symbol)
        if not twelve_data_symbol:
            log.warning(f"No Twelve Data symbol mapping for {yf_symbol}")
            return None

        # Convert interval
        twelve_data_interval = self.INTERVAL_MAP.get(interval)
        if not twelve_data_interval:
            log.warning(f"No Twelve Data interval mapping for {interval}")
            return None

        try:
            # Calculate how many bars we need
            bar_count = self._calculate_bar_count(interval)

            # Twelve Data time_series endpoint
            url = "https://api.twelvedata.com/time_series"
            params = {
                "symbol": twelve_data_symbol,
                "interval": twelve_data_interval,
                "outputsize": bar_count,
                "apikey": self.twelve_data_key,  # Will not log this param
            }

            response = requests.get(url, params=params, timeout=self.timeout)
            response.raise_for_status()

            data = response.json()

            # Check for API errors
            if data.get("status") == "error":
                log.warning(f"Twelve Data API error: {data.get('message', 'unknown')}")
                return None

            if "values" not in data or not data["values"]:
                log.warning(f"Twelve Data returned no values for {twelve_data_symbol}")
                return None

            # Parse response
            df = self._parse_twelve_data_response(data, twelve_data_symbol)
            if df is not None and not df.empty:
                log.info(
                    f"Fetched {len(df)} bars from TwelveData: {yf_symbol} {interval} "
                    f"(latest: {df.index[-1]})"
                )
                return df

            return None

        except requests.exceptions.Timeout:
            log.warning(f"Twelve Data request timeout for {yf_symbol}")
            return None
        except requests.exceptions.RequestException as e:
            log.warning(f"Twelve Data request failed for {yf_symbol}: {e}")
            return None
        except Exception as e:
            log.error(f"Twelve Data parsing error for {yf_symbol}: {e}")
            return None

    def _parse_twelve_data_response(self, data, symbol):
        """Parse Twelve Data API response into DataFrame."""
        try:
            values = data.get("values", [])
            if not values:
                return None

            records = []
            for bar in values:
                try:
                    records.append({
                        "datetime": bar.get("datetime"),
                        "open": float(bar.get("open", 0)),
                        "high": float(bar.get("high", 0)),
                        "low": float(bar.get("low", 0)),
                        "close": float(bar.get("close", 0)),
                    })
                except (ValueError, TypeError):
                    log.debug(f"Skipping malformed bar for {symbol}")
                    continue

            if not records:
                return None

            df = pd.DataFrame(records)
            df["datetime"] = pd.to_datetime(df["datetime"])
            df.set_index("datetime", inplace=True)
            df.sort_index(inplace=True)

            # Rename columns to match yfinance output
            df.rename(columns={
                "open": "Open",
                "high": "High",
                "low": "Low",
                "close": "Close",
            }, inplace=True)

            # Check for stale data
            if self._is_stale(df):
                log.warning(f"Data is stale for {symbol}, rejecting")
                return None

            return df[["Open", "High", "Low", "Close"]]

        except Exception as e:
            log.error(f"Error parsing Twelve Data response for {symbol}: {e}")
            return None

    def _fetch_yfinance(self, yf_symbol, period, interval):
        """
        Fetch from yfinance (fallback).

        Args:
            yf_symbol: Yahoo Finance symbol
            period: Period (e.g., "60d", "3mo")
            interval: Interval (e.g., "1h", "1d")

        Returns:
            DataFrame or None
        """
        for attempt in range(3):
            try:
                df = yf.download(
                    yf_symbol,
                    period=period,
                    interval=interval,
                    progress=False,
                    auto_adjust=True,
                    timeout=self.timeout,
                )
                if df is not None and not df.empty:
                    # Handle MultiIndex columns (when single symbol)
                    if isinstance(df.columns, pd.MultiIndex):
                        df.columns = [col[0] for col in df.columns]

                    # Check for stale data
                    if self._is_stale(df):
                        log.warning(f"YahooFallback data is stale for {yf_symbol}, retrying")
                        if attempt < 2:
                            time.sleep(5 * (2 ** attempt))
                        continue

                    log.info(
                        f"Fetched {len(df)} bars from YahooFallback: {yf_symbol} {interval} "
                        f"(latest: {df.index[-1]})"
                    )
                    return df

            except requests.exceptions.Timeout:
                log.warning(f"YahooFallback timeout for {yf_symbol}, attempt {attempt+1}")
            except requests.exceptions.RequestException as e:
                log.warning(f"YahooFallback request failed for {yf_symbol}: {e}")
            except Exception as e:
                log.warning(f"YahooFallback error for {yf_symbol}: {e}")

            if attempt < 2:
                time.sleep(5 * (2 ** attempt))

        return None

    def _is_stale(self, df):
        """Check if DataFrame's latest bar is too old."""
        if df is None or df.empty:
            return True

        latest_timestamp = df.index[-1]

        # Handle both datetime and Timestamp
        if hasattr(latest_timestamp, "to_pydatetime"):
            latest_timestamp = latest_timestamp.to_pydatetime()

        # Allow up to 2 hours staleness for daily data, 5 minutes for intraday
        now = datetime.now(latest_timestamp.tzinfo) if latest_timestamp.tzinfo else datetime.now()
        age = now - latest_timestamp

        # If intraday (bars < 1 hour), allow max 5 minutes staleness
        # If daily+, allow max 2 days staleness
        if age < timedelta(hours=1):
            max_age = timedelta(minutes=5)
        else:
            max_age = timedelta(days=2)

        if age > max_age:
            log.warning(f"Data is stale: {age} old (max {max_age})")
            return True

        return False

    def _calculate_bar_count(self, interval):
        """Calculate number of bars needed based on interval."""
        interval_to_count = {
            "1m": 1440,      # 24 hours
            "5m": 288,       # 2 days
            "15m": 96,       # 2 days
            "30m": 48,       # 2 days
            "1h": 240,       # 10 days
            "1d": 60,        # 60 days
        }
        return interval_to_count.get(interval, 100)


# Singleton instance
_provider = None


def get_provider(cache_ttl=840):
    """Get or create the global market data provider."""
    global _provider
    if _provider is None:
        _provider = MarketDataProvider(cache_ttl_seconds=cache_ttl)
    return _provider


def fetch_ohlc(yf_symbol, period, interval):
    """Convenience function to fetch OHLC data."""
    return get_provider().fetch_ohlc(yf_symbol, period, interval)
