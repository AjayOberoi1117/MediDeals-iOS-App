#!/usr/bin/env python3
"""Diagnostic script to test Upstox API connectivity and data freshness"""

from dotenv import load_dotenv
load_dotenv()

import requests
import os
from datetime import datetime, timedelta
from urllib.parse import quote
import pandas as pd

UPSTOX_TOKEN = os.getenv("UPSTOX_TOKEN", "eyJ0eXAiOiJKV1QiLCJrZXlfaWQiOiJza191MV4wIiwiYWxnIjoiSFMyNTYifQ.eyJzdWIiOiI1SkNaWjgiLCJqdGkiOiI2YTY2ZmYxNGExNzkxMjcxODk2MzhjMGMiLCJpc011bHRpQ2xpZW50IjpmYWxzZSwiaXNQbHVzUGxhbiI6dHJ1ZSwiaXNFeHRlbmRlZCI6dHJ1ZSwiaWF0IjoxNzg1MTM0ODY4LCJpc3MiOiJ1ZGFwaS1nYXRld2F5LXNlcnZpY2UiLCJleHAiOjE4MTY3MjU2MDB9.UwK3fm_BWVtisx7EIWS_dJsI8gg9Br5xrN4sT8ty_Xo")

print("=" * 70)
print("UPSTOX API DIAGNOSTIC TEST")
print("=" * 70)

# 1. Validate token
print("\n1. TOKEN VALIDATION")
print(f"   Token starts with: {UPSTOX_TOKEN[:30]}...")
print(f"   Token length: {len(UPSTOX_TOKEN)}")

try:
    UPSTOX_TOKEN.encode('ascii')
    print("   ✓ Token is valid ASCII")
except UnicodeEncodeError as e:
    print(f"   ✗ Token contains non-ASCII characters: {e}")
    exit(1)

# 2. Test API connection
print("\n2. API CONNECTION TEST")

HEADERS = {
    "Authorization": f"Bearer {UPSTOX_TOKEN}",
    "Accept": "application/json"
}

# Test with one stock: RELIANCE
ikey = "NSE_EQ|INE002A01018"
key_enc = quote(ikey, safe="")

print(f"   Testing with RELIANCE (key: {ikey})")

# Try 30-minute candles
print("\n   a) Fetching 30-minute candles...")
to_date = datetime.now().strftime("%Y-%m-%d")
from_date = (datetime.now() - timedelta(days=5)).strftime("%Y-%m-%d")
url_30 = f"https://api.upstox.com/v2/historical-candle/{key_enc}/30minute/{to_date}/{from_date}"

try:
    r = requests.get(url_30, headers=HEADERS, timeout=10)
    print(f"      Status: {r.status_code}")

    if r.status_code == 200:
        data = r.json()
        candles = data.get("data", {}).get("candles", [])
        print(f"      Candles fetched: {len(candles)}")

        if candles:
            latest = candles[-1]
            print(f"      Latest candle timestamp: {latest[0]}")

            # Parse and check age
            try:
                candle_time = datetime.fromisoformat(latest[0].replace('Z', '+00:00'))
                now = datetime.now()
                age = (now - candle_time).total_seconds() / 60
                print(f"      Candle age: {age:.1f} minutes")

                if age > 35:
                    print(f"      ⚠️  30-minute candles are STALE (>35 min old)")
                else:
                    print(f"      ✓ Data is relatively fresh")
            except Exception as e:
                print(f"      Error parsing timestamp: {e}")
    else:
        print(f"      Error: {r.text[:200]}")

except Exception as e:
    print(f"      Exception: {e}")

# Try 1-minute candles
print("\n   b) Fetching 1-minute candles...")
url_1 = f"https://api.upstox.com/v2/historical-candle/{key_enc}/1minute/{to_date}/{from_date}"

try:
    r = requests.get(url_1, headers=HEADERS, timeout=10)
    print(f"      Status: {r.status_code}")

    if r.status_code == 200:
        data = r.json()
        candles = data.get("data", {}).get("candles", [])
        print(f"      Candles fetched: {len(candles)}")

        if candles:
            latest = candles[-1]
            print(f"      Latest candle timestamp: {latest[0]}")

            # Parse and check age
            try:
                candle_time = datetime.fromisoformat(latest[0].replace('Z', '+00:00'))
                now = datetime.now()
                age = (now - candle_time).total_seconds() / 60
                print(f"      Candle age: {age:.1f} minutes")

                if age > 2:
                    print(f"      ⚠️  1-minute candles are stale (>2 min old)")
                else:
                    print(f"      ✓ Data is fresh")
            except Exception as e:
                print(f"      Error parsing timestamp: {e}")
    else:
        print(f"      Error: {r.text[:200]}")

except Exception as e:
    print(f"      Exception: {e}")

print("\n" + "=" * 70)
print("RECOMMENDATION:")
print("  • If 30-minute data is >35min old: Use 1-minute candles for real-time signals")
print("  • If 1-minute data is also stale: Upstox API may have connectivity issues")
print("  • If token error: Verify UPSTOX_TOKEN in .env file")
print("=" * 70)
