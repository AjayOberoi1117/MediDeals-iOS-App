#!/usr/bin/env python3
"""
DATA LATENCY DIAGNOSTIC TOOL

Measure actual data latency from Yahoo Finance for NIFTY 50 and BANKNIFTY.

Records for each measurement:
- Request timestamp (UTC and IST)
- Latest returned candle timestamp and age
- Candle interval
- Network request duration
- Missing or duplicate candles
- Timezone interpretation
- Provider response status

Run during Indian market hours (9:15 AM - 3:30 PM IST) for live measurements.
If market closed, documents tool readiness and pending live measurement.
"""

import yfinance as yf
import pandas as pd
import numpy as np
from datetime import datetime, timedelta, timezone
import pytz
import time
import os
import csv
from pathlib import Path

# ============================================================================
# CONFIGURATION
# ============================================================================

SYMBOLS = {
    "NIFTY 50": "^NSEI",
    "BANKNIFTY": "^NSEBANK",
}

INTERVALS = ["15m", "1h", "1d"]

IST_TZ = pytz.timezone('Asia/Kolkata')
UTC_TZ = pytz.UTC

REPORT_DIR = Path("reports/data_latency")

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

def get_ist_time(utc_dt):
    """Convert UTC datetime to IST."""
    if utc_dt.tzinfo is None:
        utc_dt = utc_dt.replace(tzinfo=UTC_TZ)
    return utc_dt.astimezone(IST_TZ)

def is_nse_trading_hours():
    """Check if within NSE trading hours."""
    now_ist = datetime.now(IST_TZ)
    market_open = now_ist.replace(hour=9, minute=15, second=0, microsecond=0)
    market_close = now_ist.replace(hour=15, minute=30, second=0, microsecond=0)

    if now_ist.weekday() >= 5:  # Weekend
        return False

    return market_open <= now_ist <= market_close

def calculate_candle_age(latest_candle_time, interval):
    """
    Calculate age of latest candle.

    Args:
        latest_candle_time: Timestamp of latest candle
        interval: "15m", "1h", "1d"

    Returns:
        (minutes_old, expected_close_time)
    """
    now_utc = datetime.now(UTC_TZ)

    # Parse interval
    if interval == "15m":
        candle_duration = timedelta(minutes=15)
    elif interval == "1h":
        candle_duration = timedelta(hours=1)
    elif interval == "1d":
        candle_duration = timedelta(days=1)
    else:
        return None, None

    # Expected close time (start + duration)
    if latest_candle_time.tzinfo is None:
        latest_candle_time = latest_candle_time.replace(tzinfo=UTC_TZ)

    expected_close = latest_candle_time + candle_duration
    age_seconds = (now_utc - expected_close).total_seconds()

    if age_seconds < 0:
        # Candle not yet closed
        return None, expected_close

    return age_seconds / 60, expected_close

def diagnose_symbol(symbol_name, symbol_ticker, interval):
    """
    Diagnose data latency for a symbol and interval.

    Returns:
        Dict with measurement results
    """
    result = {
        "timestamp_utc": datetime.now(UTC_TZ).isoformat(),
        "timestamp_ist": datetime.now(IST_TZ).isoformat(),
        "symbol_name": symbol_name,
        "symbol_ticker": symbol_ticker,
        "interval": interval,
        "request_duration_seconds": None,
        "latest_candle_time_utc": None,
        "latest_candle_time_ist": None,
        "candle_age_minutes": None,
        "expected_candle_close_time_utc": None,
        "is_candle_closed": None,
        "candle_count": None,
        "first_candle_time": None,
        "last_candle_time": None,
        "missing_candles": None,
        "duplicate_candles": None,
        "zero_or_invalid_prices": None,
        "timezone_interpretation": None,
        "status": "UNKNOWN",
        "error_message": None,
    }

    try:
        # Fetch data
        start_time = time.time()
        df = yf.download(symbol_ticker, period="5d", interval=interval, progress=False)
        elapsed = time.time() - start_time

        result["request_duration_seconds"] = elapsed

        if df is None or df.empty:
            result["status"] = "NO_DATA"
            result["error_message"] = "yfinance returned empty DataFrame"
            return result

        # Analyze data
        result["candle_count"] = len(df)
        result["first_candle_time"] = df.index[0].isoformat()
        result["last_candle_time"] = df.index[-1].isoformat()

        # Latest candle
        latest_candle = df.index[-1]
        result["latest_candle_time_utc"] = latest_candle.isoformat()

        # Convert to IST
        if latest_candle.tzinfo is None:
            latest_candle_utc = latest_candle.replace(tzinfo=UTC_TZ)
        else:
            latest_candle_utc = latest_candle

        latest_candle_ist = latest_candle_utc.astimezone(IST_TZ)
        result["latest_candle_time_ist"] = latest_candle_ist.isoformat()
        result["timezone_interpretation"] = f"UTC: {latest_candle_utc.tzinfo}, IST: {latest_candle_ist.tzinfo}"

        # Candle age
        age_minutes, expected_close = calculate_candle_age(latest_candle, interval)
        if age_minutes is not None:
            result["candle_age_minutes"] = round(age_minutes, 2)
            result["is_candle_closed"] = True
            result["expected_candle_close_time_utc"] = expected_close.isoformat()
        else:
            result["is_candle_closed"] = False
            result["expected_candle_close_time_utc"] = expected_close.isoformat()

        # Data quality checks
        # Missing candles (check if time gaps exist)
        time_diffs = df.index.to_series().diff()
        if interval == "15m":
            expected_diff = pd.Timedelta(minutes=15)
        elif interval == "1h":
            expected_diff = pd.Timedelta(hours=1)
        elif interval == "1d":
            expected_diff = pd.Timedelta(days=1)

        missing = (time_diffs > expected_diff * 1.1).sum()  # 10% tolerance
        result["missing_candles"] = int(missing)

        # Duplicate candles (same timestamp)
        duplicates = len(df) - len(df.index.unique())
        result["duplicate_candles"] = int(duplicates)

        # Zero or invalid prices
        invalid = 0
        for col in ['open', 'high', 'low', 'close']:
            if col in df.columns:
                invalid += (df[col] <= 0).sum() + (df[col].isna()).sum()
        result["zero_or_invalid_prices"] = int(invalid)

        result["status"] = "SUCCESS"

    except Exception as e:
        result["status"] = "ERROR"
        result["error_message"] = str(e)

    return result

# ============================================================================
# REPORTING
# ============================================================================

def save_measurement(measurement, csv_file):
    """Append measurement to CSV."""
    fieldnames = [
        "timestamp_utc",
        "timestamp_ist",
        "symbol_name",
        "symbol_ticker",
        "interval",
        "request_duration_seconds",
        "latest_candle_time_utc",
        "latest_candle_time_ist",
        "candle_age_minutes",
        "expected_candle_close_time_utc",
        "is_candle_closed",
        "candle_count",
        "first_candle_time",
        "last_candle_time",
        "missing_candles",
        "duplicate_candles",
        "zero_or_invalid_prices",
        "timezone_interpretation",
        "status",
        "error_message",
    ]

    # Create directory if needed
    csv_file.parent.mkdir(parents=True, exist_ok=True)

    # Append or create
    file_exists = csv_file.exists()
    with open(csv_file, 'a', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        if not file_exists:
            writer.writeheader()
        writer.writerow(measurement)

def generate_summary_report():
    """Generate summary report from all measurements."""
    report_lines = [
        "# DATA LATENCY DIAGNOSTIC SUMMARY\n",
        f"Generated: {datetime.now(IST_TZ).isoformat()}\n",
        "\n",
    ]

    # Check if measurements exist
    nifty_csv = REPORT_DIR / "nifty_latency_report.csv"
    banknifty_csv = REPORT_DIR / "banknifty_latency_report.csv"

    report_lines.append("## Status\n\n")

    if not nifty_csv.exists() and not banknifty_csv.exists():
        report_lines.append("⏳ **NO MEASUREMENTS TAKEN YET**\n\n")
        report_lines.append("Run this diagnostic during Indian market hours (9:15 AM - 3:30 PM IST)\n")
        report_lines.append("to capture live data latency from Yahoo Finance.\n\n")
        report_lines.append("```bash\npython3 tools/data_latency_diagnostic.py\n```\n\n")
    else:
        report_lines.append("✓ Measurements available\n\n")

    report_lines.append("## NIFTY 50 (^NSEI)\n\n")
    if nifty_csv.exists():
        try:
            df = pd.read_csv(nifty_csv)
            latest = df.iloc[-1]

            report_lines.append(f"**Latest Measurement:** {latest['timestamp_ist']}\n\n")
            report_lines.append(f"- Status: {latest['status']}\n")
            report_lines.append(f"- Request Duration: {latest['request_duration_seconds']:.2f}s\n")
            report_lines.append(f"- Latest Candle: {latest['latest_candle_time_ist']}\n")
            if pd.notna(latest['candle_age_minutes']):
                report_lines.append(f"- Candle Age: {latest['candle_age_minutes']:.1f} minutes\n")
            report_lines.append(f"- Candle Count (5d): {int(latest['candle_count'])}\n")
            report_lines.append(f"- Missing Candles: {int(latest['missing_candles'])}\n")
            report_lines.append(f"- Duplicate Candles: {int(latest['duplicate_candles'])}\n")
            report_lines.append(f"- Invalid Prices: {int(latest['zero_or_invalid_prices'])}\n")
            if latest['error_message'] and pd.notna(latest['error_message']):
                report_lines.append(f"- Error: {latest['error_message']}\n")
        except Exception as e:
            report_lines.append(f"Error reading NIFTY data: {e}\n")
    else:
        report_lines.append("*No measurements yet*\n")

    report_lines.append("\n")
    report_lines.append("## BANKNIFTY (^NSEBANK)\n\n")
    if banknifty_csv.exists():
        try:
            df = pd.read_csv(banknifty_csv)
            latest = df.iloc[-1]

            report_lines.append(f"**Latest Measurement:** {latest['timestamp_ist']}\n\n")
            report_lines.append(f"- Status: {latest['status']}\n")
            report_lines.append(f"- Request Duration: {latest['request_duration_seconds']:.2f}s\n")
            report_lines.append(f"- Latest Candle: {latest['latest_candle_time_ist']}\n")
            if pd.notna(latest['candle_age_minutes']):
                report_lines.append(f"- Candle Age: {latest['candle_age_minutes']:.1f} minutes\n")
            report_lines.append(f"- Candle Count (5d): {int(latest['candle_count'])}\n")
            report_lines.append(f"- Missing Candles: {int(latest['missing_candles'])}\n")
            report_lines.append(f"- Duplicate Candles: {int(latest['duplicate_candles'])}\n")
            report_lines.append(f"- Invalid Prices: {int(latest['zero_or_invalid_prices'])}\n")
            if latest['error_message'] and pd.notna(latest['error_message']):
                report_lines.append(f"- Error: {latest['error_message']}\n")
        except Exception as e:
            report_lines.append(f"Error reading BANKNIFTY data: {e}\n")
    else:
        report_lines.append("*No measurements yet*\n")

    report_lines.append("\n")
    report_lines.append("## Interpretation\n\n")

    if not nifty_csv.exists() and not banknifty_csv.exists():
        report_lines.append("**Status:** LIVE MEASUREMENT PENDING\n\n")
        report_lines.append("Data latency has not been measured. The strategy currently uses a fixed assumption of 15-30 minutes.\n")
        report_lines.append("This must be validated with actual measurements during market hours before forward-paper approval.\n\n")
        report_lines.append("**Next Step:** Run diagnostic during NSE market hours (9:15 AM - 3:30 PM IST)\n")
    else:
        report_lines.append("**Status:** MEASUREMENTS AVAILABLE\n\n")
        report_lines.append("Review actual data ages and request durations above.\n")
        report_lines.append("If candle age > 30 minutes, strategy labels should reflect higher latency.\n")
        report_lines.append("If candle age < 5 minutes, strategy is unsuitable for real-time scalping.\n")

    report_lines.append("\n")
    report_lines.append("## CSV Files\n\n")
    report_lines.append(f"- `{nifty_csv.relative_to(REPORT_DIR.parent)}`\n")
    report_lines.append(f"- `{banknifty_csv.relative_to(REPORT_DIR.parent)}`\n")

    # Write summary
    summary_file = REPORT_DIR / "DATA_LATENCY_SUMMARY.md"
    summary_file.parent.mkdir(parents=True, exist_ok=True)
    with open(summary_file, 'w') as f:
        f.writelines(report_lines)

    return "".join(report_lines)

# ============================================================================
# MAIN
# ============================================================================

def main():
    """Run diagnostic for all symbols and intervals."""
    print("\n" + "=" * 80)
    print("DATA LATENCY DIAGNOSTIC")
    print("=" * 80)
    print()

    # Check market hours
    trading_now = is_nse_trading_hours()
    now_ist = datetime.now(IST_TZ)

    print(f"Current time (IST): {now_ist.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"NSE Trading Hours: 9:15 AM - 3:30 PM IST (Mon-Fri)")
    print(f"Currently: {'WITHIN TRADING HOURS ✓' if trading_now else 'OUTSIDE TRADING HOURS (Market closed)'}")
    print()

    if not trading_now:
        print("⚠️ Market is currently closed.")
        print("Measurements will use cached/historical data from Yahoo Finance.")
        print("LIVE data latency measurements require NSE market hours.")
        print()

    # Run diagnostics
    measurements = []

    for interval in INTERVALS:
        print(f"\nTesting interval: {interval}")
        print("-" * 60)

        for symbol_name, symbol_ticker in SYMBOLS.items():
            print(f"  {symbol_name:15} ({symbol_ticker:8}) ... ", end="", flush=True)

            result = diagnose_symbol(symbol_name, symbol_ticker, interval)
            measurements.append(result)

            status = result["status"]
            if status == "SUCCESS":
                if result["is_candle_closed"]:
                    age = result["candle_age_minutes"]
                    print(f"✓ Age: {age:6.1f}m | Candles: {result['candle_count']:3d} | "
                          f"Missing: {result['missing_candles']:2d} | Request: {result['request_duration_seconds']:.2f}s")
                else:
                    print(f"✓ Candle still open (will close at {result['expected_candle_close_time_utc']})")
            elif status == "NO_DATA":
                print(f"✗ No data returned")
            else:
                print(f"✗ {result['error_message']}")

            # Save measurement
            if interval == "15m":
                csv_file = REPORT_DIR / "nifty_latency_report.csv" if "NIFTY" in symbol_name else REPORT_DIR / "banknifty_latency_report.csv"
                save_measurement(result, csv_file)

    # Generate summary report
    print("\n" + "=" * 80)
    print("GENERATING SUMMARY REPORT")
    print("=" * 80)

    summary = generate_summary_report()
    print(summary)

    print("=" * 80)
    print("\nFiles saved:")
    print(f"  {REPORT_DIR / 'nifty_latency_report.csv'}")
    print(f"  {REPORT_DIR / 'banknifty_latency_report.csv'}")
    print(f"  {REPORT_DIR / 'DATA_LATENCY_SUMMARY.md'}")
    print()

    if not trading_now:
        print("\n⚠️  IMPORTANT:")
        print("Market is closed. Actual data latency must be measured during trading hours.")
        print("Re-run this diagnostic during NSE market hours (9:15 AM - 3:30 PM IST)")
        print("for accurate latency measurements.")

if __name__ == "__main__":
    main()
