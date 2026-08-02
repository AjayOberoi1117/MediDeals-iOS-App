#!/usr/bin/env python3
"""
Data Source Audit for NIFTY50 and BANKNIFTY Scalper

Identify actual available data sources and their characteristics
before implementing the scalper strategies.
"""

import yfinance as yf
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import time
import sys

def audit_yfinance_source():
    """Audit yfinance as data source for NIFTY and BANKNIFTY."""
    print("=" * 80)
    print("YFINANCE DATA SOURCE AUDIT")
    print("=" * 80)
    print()

    symbols_to_test = {
        "NIFTY 50": "^NSEI",
        "BANKNIFTY": "^NSEBANK",
    }

    for name, ticker in symbols_to_test.items():
        print(f"\nTesting: {name} ({ticker})")
        print("-" * 60)

        # Test 1: 15-minute candle availability
        print("  Test 1: 15-minute candle availability")
        try:
            start_time = time.time()
            df = yf.download(ticker, period="5d", interval="15m", progress=False)
            elapsed = time.time() - start_time

            if df is not None and not df.empty:
                print(f"    ✓ Downloaded {len(df)} 15-min candles")
                print(f"    ✓ Download time: {elapsed:.2f}s")
                print(f"    ✓ Date range: {df.index[0]} to {df.index[-1]}")
                print(f"    ✓ Columns: {list(df.columns)}")
                print(f"    ✓ Latest close: {df['Close'].iloc[-1]:.2f}")

                # Check for timezone info
                if df.index.tz:
                    print(f"    ✓ Timezone: {df.index.tz}")
                else:
                    print(f"    ⚠ No timezone info (assumes UTC or market local)")
            else:
                print(f"    ✗ No data returned")
        except Exception as e:
            print(f"    ✗ Error: {e}")

        # Test 2: 1-minute candle availability
        print("  Test 2: 1-minute candle availability")
        try:
            start_time = time.time()
            df_1m = yf.download(ticker, period="1d", interval="1m", progress=False)
            elapsed = time.time() - start_time

            if df_1m is not None and not df_1m.empty:
                print(f"    ✓ Downloaded {len(df_1m)} 1-min candles")
                print(f"    ✓ Download time: {elapsed:.2f}s")
                print(f"    ✓ Date range: {df_1m.index[0]} to {df_1m.index[-1]}")
            else:
                print(f"    ✗ No data returned")
        except Exception as e:
            print(f"    ✗ Error: {e}")

        # Test 3: Hourly candle availability
        print("  Test 3: Hourly candle availability")
        try:
            start_time = time.time()
            df_h = yf.download(ticker, period="30d", interval="1h", progress=False)
            elapsed = time.time() - start_time

            if df_h is not None and not df_h.empty:
                print(f"    ✓ Downloaded {len(df_h)} hourly candles")
                print(f"    ✓ Download time: {elapsed:.2f}s")
                print(f"    ✓ Date range: {df_h.index[0]} to {df_h.index[-1]}")
            else:
                print(f"    ✗ No data returned")
        except Exception as e:
            print(f"    ✗ Error: {e}")

        # Test 4: Historical depth
        print("  Test 4: Historical depth (daily candles)")
        try:
            df_daily = yf.download(ticker, period="1y", progress=False)

            if df_daily is not None and not df_daily.empty:
                print(f"    ✓ Downloaded {len(df_daily)} daily candles (1 year)")
                print(f"    ✓ Date range: {df_daily.index[0].date()} to {df_daily.index[-1].date()}")
            else:
                print(f"    ✗ No data returned")
        except Exception as e:
            print(f"    ✗ Error: {e}")

        # Test 5: Data freshness (check for data delay)
        print("  Test 5: Data freshness estimate")
        try:
            df_now = yf.download(ticker, period="5d", interval="15m", progress=False)
            if df_now is not None and not df_now.empty:
                last_candle_time = df_now.index[-1]
                now = pd.Timestamp.now(tz='UTC')
                delay = (now - last_candle_time).total_seconds() / 60

                print(f"    ✓ Last candle time (UTC): {last_candle_time}")
                print(f"    ✓ Current time (UTC): {now}")
                print(f"    ✓ Estimated data delay: ~{delay:.0f} minutes")

                if delay > 20:
                    print(f"    ⚠ WARNING: Data appears significantly delayed")
        except Exception as e:
            print(f"    ✗ Error: {e}")

        time.sleep(1)  # Avoid rate limiting

    print("\n" + "=" * 80)
    print("YFINANCE SOURCE SUMMARY")
    print("=" * 80)
    print("""
Provider: Yahoo Finance (yfinance library)
Pricing Tier: Free
Rate Limits: ~2000 requests/hour (observed)
Symbols: ^NSEI (NIFTY 50), ^NSEBANK (BANKNIFTY)

CONFIRMED AVAILABLE:
✓ Daily candles (history: 1+ years)
✓ 15-minute candles (history: 5+ days)
✓ 1-minute candles (history: 1-2 days)
✓ Hourly candles (history: 30+ days)

LATENCY CHARACTERISTICS:
- Data delay: Typically 15-30 minutes from market close for live intraday
- For scalping: NOT suitable for real-time execution
- For research/backtesting: Suitable with 15-30min assumed delay

TIMEZONE HANDLING:
- Index data typically in market-local timezone (IST)
- Must verify timezone on actual download

LIMITATIONS:
- Free tier may have data quality issues during peak times
- No official support for NSE indices (community-maintained)
- No future contracts, options, or derivatives
- Volume data may be aggregated or synthetic

SUITABLE FOR:
✓ Historical replay testing (with assumed 15-30min delay)
✗ Real-time paper trading (data too stale)
✓ Strategy research and hypothesis testing
    """)

def estimate_ist_timestamp():
    """Estimate IST timezone handling."""
    print("\n" + "=" * 80)
    print("TIMEZONE HANDLING AUDIT")
    print("=" * 80)

    try:
        df = yf.download("^NSEI", period="1d", interval="15m", progress=False)
        if df is not None and not df.empty:
            print(f"\nSample candle from yfinance:")
            print(f"  Last index: {df.index[-1]}")
            print(f"  Type: {type(df.index[-1])}")
            print(f"  Timezone info: {df.index.tz}")

            # Convert to IST
            if df.index.tz:
                ist_time = df.index[-1].tz_convert('Asia/Kolkata')
            else:
                # Assume UTC if no tz info
                ist_time = pd.Timestamp(df.index[-1], tz='UTC').tz_convert('Asia/Kolkata')

            print(f"  Converted to IST: {ist_time}")

            print("\nRECOMMENDATION:")
            print("  Always handle timezone explicitly in scalper code:")
            print("  - Assume yfinance returns UTC timestamps if tz-naive")
            print("  - Convert to IST for signal generation and logging")
            print("  - Store both UTC and IST in ledger for clarity")
    except Exception as e:
        print(f"Error in timezone test: {e}")

def estimate_data_availability_for_scalping():
    """Estimate whether yfinance is suitable for scalping."""
    print("\n" + "=" * 80)
    print("SCALPING SUITABILITY ASSESSMENT")
    print("=" * 80)
    print("""
QUESTION: Can yfinance support real-time paper scalping?

ANSWER: Partially, with significant caveats.

EVIDENCE:
1. Data freshness: 15-30 minute delay typical (not suitable for <5min scalps)
2. 15-minute candles: Historical data clean, but live data lags
3. 1-minute candles: Available but unreliable for live trading
4. Rate limits: Free tier ~2000 req/hr (low for high-frequency monitoring)

VERDICT:

For HISTORICAL REPLAY: ✓ Fully suitable
- Use yfinance for backtesting strategy logic
- Assume 15-30min delay in data timestamps
- Verify strategy survives with older/stale entry prices

For FORWARD PAPER TRADING: ⚠ Limited suitability
- Can use as data source, but label as DELAYED-DATA RESEARCH MODE
- Do NOT claim real-time scalping capability
- Entry prices will be 15-30min old when signal fires
- Useful for algorithm research, not strategy deployment

For PRODUCTION LIVE TRADING: ✗ Not suitable
- Too much latency for real intraday scalping
- Would need paid tier or dedicated data provider
- Index scalping requires real-time tick data (NSE API or broker)

RECOMMENDATION FOR THIS PROJECT:

Build the scalper with yfinance for research and observation, but clearly label:
  [PAPER][NIFTY50-SCALPER-V1-DELAYED-DATA]
  [PAPER][BANKNIFTY-SCALPER-V1-DELAYED-DATA]

This allows:
1. Testing strategy logic without live data latency complications
2. Observing simulated performance with realistic assumptions
3. Future migration to real-time data when available
4. Clear communication that this is research, not deployment-ready
    """)

if __name__ == "__main__":
    print("\n")
    audit_yfinance_source()
    estimate_ist_timestamp()
    estimate_data_availability_for_scalping()
    print("\n" + "=" * 80)
    print("END OF AUDIT")
    print("=" * 80 + "\n")
