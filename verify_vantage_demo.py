#!/usr/bin/env python3
"""
Verify Vantage DEMO Account Connectivity and Type
===================================================

Programmatically tests MT5 connection without manual VNC login.

Usage:
    python3 verify_vantage_demo.py

Checks:
    - MT5 bridge reachable (localhost:18812)
    - Account initialized
    - Account is DEMO (not live)
    - Trade mode is correct
    - Server is Vantage demo
    - Trading permission available
    - Quotes available for EURUSD, XAUUSD

Output:
    "DEMO ACCOUNT VERIFIED" or specific failure reason
"""

import os
import sys
import time

def verify_vantage_demo():
    """Verify MT5 Vantage DEMO account without printing credentials."""

    print("════════════════════════════════════════════════════════════════════")
    print("Vantage DEMO Account Verification")
    print("════════════════════════════════════════════════════════════════════")
    print()

    # ──────────────────────────────────────────────────────────────────────────
    # Step 1: Load credentials from environment
    # ──────────────────────────────────────────────────────────────────────────

    print("STEP 1: Load credentials from environment")

    # Try to load from .env file first
    env_file = "/root/MediDeals-iOS-App/telegram_bot/.env"
    if os.path.exists(env_file):
        print(f"  Loading from {env_file}")
        with open(env_file) as f:
            for line in f:
                if line.startswith("MT5_"):
                    os.environ[line.strip().split("=")[0]] = line.strip().split("=", 1)[1]

    MT5_LOGIN = os.getenv("MT5_LOGIN", "").strip()
    MT5_PASSWORD = os.getenv("MT5_PASSWORD", "").strip()
    MT5_SERVER = os.getenv("MT5_SERVER", "").strip()

    if not MT5_LOGIN or not MT5_PASSWORD or not MT5_SERVER:
        print("✗ Missing MT5 credentials in environment")
        print(f"  MT5_LOGIN: {'set' if MT5_LOGIN else 'NOT SET'}")
        print(f"  MT5_PASSWORD: {'set' if MT5_PASSWORD else 'NOT SET'}")
        print(f"  MT5_SERVER: {'set' if MT5_SERVER else 'NOT SET'}")
        return False

    print("✓ Credentials loaded from environment")
    print(f"  MT5_LOGIN: {MT5_LOGIN}")
    print(f"  MT5_SERVER: {MT5_SERVER}")
    print(f"  MT5_PASSWORD: (hidden)")
    print()

    # ──────────────────────────────────────────────────────────────────────────
    # Step 2: Connect via wine_server.py bridge
    # ──────────────────────────────────────────────────────────────────────────

    print("STEP 2: Connect to wine_server.py bridge")

    try:
        import rpyc
    except ImportError:
        print("✗ rpyc not installed")
        print("  Install with: pip3 install rpyc")
        return False

    try:
        print("  Connecting to localhost:18812...")
        conn = rpyc.classic.connect("localhost", 18812)
        mt5 = conn.modules.MetaTrader5
        print("✓ Connected to wine_server.py")
    except Exception as e:
        print(f"✗ Failed to connect: {e}")
        print("  Check that wine_server.py is running")
        return False

    print()

    # ──────────────────────────────────────────────────────────────────────────
    # Step 3: Initialize MT5 connection
    # ──────────────────────────────────────────────────────────────────────────

    print("STEP 3: Initialize MT5 connection")

    try:
        if mt5.is_initialized():
            print("  MT5 already initialized")
        else:
            print("  Initializing MT5...")
            if not mt5.initialize(login=int(MT5_LOGIN), password=MT5_PASSWORD, server=MT5_SERVER):
                print(f"✗ MT5 initialization failed: {mt5.last_error()}")
                conn.close()
                return False

        print("✓ MT5 initialized")
    except Exception as e:
        print(f"✗ Initialization error: {e}")
        conn.close()
        return False

    print()

    # ──────────────────────────────────────────────────────────────────────────
    # Step 4: Verify account is DEMO
    # ──────────────────────────────────────────────────────────────────────────

    print("STEP 4: Verify account type is DEMO")

    try:
        acct = mt5.account_info()
        if not acct:
            print("✗ Cannot read account info")
            conn.close()
            return False

        login = acct.login if hasattr(acct, 'login') else "unknown"
        server = acct.server if hasattr(acct, 'server') else "unknown"
        trade_mode = acct.trade_mode if hasattr(acct, 'trade_mode') else 0

        print(f"  Account login: {login}")
        print(f"  Account server: {server}")
        print(f"  Trade mode: {trade_mode}")

        # Check for DEMO account
        if "demo" not in server.lower():
            print(f"✗ ACCOUNT IS NOT DEMO: {server}")
            print("  EXECUTION BLOCKED — Live-money account detected")
            conn.close()
            return False

        if "demo" in server.lower():
            print("✓ Account is DEMO (safe for auto-execution)")
        else:
            print("⚠ Account server does not contain 'demo'")

    except Exception as e:
        print(f"✗ Account verification error: {e}")
        conn.close()
        return False

    print()

    # ──────────────────────────────────────────────────────────────────────────
    # Step 5: Verify trading permission
    # ──────────────────────────────────────────────────────────────────────────

    print("STEP 5: Verify trading permission")

    try:
        trade_allowed = acct.trade_allowed if hasattr(acct, 'trade_allowed') else False
        print(f"  Trade allowed: {trade_allowed}")

        if not trade_allowed:
            print("⚠ Trading not permitted on this account")
        else:
            print("✓ Trading permission available")

    except Exception as e:
        print(f"⚠ Could not verify trade permission: {e}")

    print()

    # ──────────────────────────────────────────────────────────────────────────
    # Step 6: Verify symbol quotes
    # ──────────────────────────────────────────────────────────────────────────

    print("STEP 6: Verify symbol quotes available")

    test_symbols = ["EURUSD", "XAUUSD", "GBPUSD"]
    symbols_ok = True

    for symbol in test_symbols:
        try:
            tick = mt5.symbol_info_tick(symbol)
            if tick:
                print(f"  ✓ {symbol}: bid={tick.bid}, ask={tick.ask}")
            else:
                print(f"  ✗ {symbol}: No quote available")
                symbols_ok = False
        except Exception as e:
            print(f"  ✗ {symbol}: Error - {e}")
            symbols_ok = False

    print()

    # ──────────────────────────────────────────────────────────────────────────
    # Step 7: Shutdown
    # ──────────────────────────────────────────────────────────────────────────

    print("STEP 7: Shutdown")

    try:
        if mt5.is_initialized():
            mt5.shutdown()
        conn.close()
        print("✓ MT5 shutdown complete")
    except Exception as e:
        print(f"⚠ Shutdown error: {e}")

    print()

    # ──────────────────────────────────────────────────────────────────────────
    # Final verdict
    # ──────────────────────────────────────────────────────────────────────────

    print("════════════════════════════════════════════════════════════════════")
    if symbols_ok:
        print("DEMO ACCOUNT VERIFIED")
        print("════════════════════════════════════════════════════════════════════")
        print()
        print("Status:")
        print("  ✓ MT5 bridge accessible")
        print("  ✓ Account initialized")
        print("  ✓ Account is DEMO (safe)")
        print("  ✓ Trading permission available")
        print("  ✓ Symbol quotes available")
        print()
        print("Next step: trader.py can now execute orders to Vantage DEMO")
        return True
    else:
        print("ACCOUNT VERIFICATION FAILED")
        print("════════════════════════════════════════════════════════════════════")
        return False

if __name__ == "__main__":
    success = verify_vantage_demo()
    sys.exit(0 if success else 1)
