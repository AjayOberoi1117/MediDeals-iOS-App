"""
Verify MT5 connection and initialization.
Tests MT5.initialize() and retrieves terminal/account information.
Does NOT place any orders.
"""

import os
import sys
import logging
from dotenv import load_dotenv

try:
    import MetaTrader5 as mt5
except ImportError:
    print("ERROR: MetaTrader5 package not installed.")
    print("Run: pip install MetaTrader5")
    sys.exit(1)

load_dotenv()

logging.basicConfig(
    format="%(asctime)s | VERIFY_MT5 | %(levelname)s | %(message)s",
    level=logging.INFO,
)
log = logging.getLogger(__name__)

MT5_LOGIN = int(os.getenv("MT5_LOGIN", "0"))
MT5_PASSWORD = os.getenv("MT5_PASSWORD", "")
MT5_SERVER = os.getenv("MT5_SERVER", "")


def verify_mt5_connection():
    """Initialize MT5 and verify connection."""
    if not MT5_LOGIN or not MT5_PASSWORD or not MT5_SERVER:
        log.error("ERROR: Missing MT5_LOGIN, MT5_PASSWORD, or MT5_SERVER in .env")
        return False

    log.info("Attempting MT5 initialization...")
    log.info("  Login:  %d", MT5_LOGIN)
    log.info("  Server: %s", MT5_SERVER)

    # Initialize
    if not mt5.initialize(login=MT5_LOGIN, password=MT5_PASSWORD, server=MT5_SERVER):
        log.error("MT5 initialization failed: %s", mt5.last_error())
        return False

    log.info("✅ MT5 initialization successful")
    return True


def get_terminal_info():
    """Retrieve and display terminal information."""
    try:
        term = mt5.terminal_info()
        if term is None:
            log.error("Failed to get terminal info: %s", mt5.last_error())
            return False

        log.info("")
        log.info("═══════════════════════════════════════════════════════════════════")
        log.info("TERMINAL INFORMATION")
        log.info("═══════════════════════════════════════════════════════════════════")
        log.info("  Platform:       %s", term.platform)
        log.info("  Connected:      %s", term.connected)
        log.info("  Trade Allowed:  %s", term.trade_allowed)
        log.info("  Trade Expert:   %s (AutoTrading enabled in MT5)")
        log.info("")
        return True
    except Exception as e:
        log.error("Error retrieving terminal info: %s", e)
        return False


def get_account_info():
    """Retrieve and display account information."""
    try:
        acc = mt5.account_info()
        if acc is None:
            log.error("Failed to get account info: %s", mt5.last_error())
            return False

        log.info("═══════════════════════════════════════════════════════════════════")
        log.info("ACCOUNT INFORMATION")
        log.info("═══════════════════════════════════════════════════════════════════")
        log.info("  Account:        %s", acc.name)
        log.info("  Login:          %s", "MASKED" if acc.login else "N/A")
        log.info("  Server:         %s", acc.server)
        log.info("  Currency:       %s", acc.currency)
        log.info("  Account Type:   %s", "DEMO" if acc.trade_mode == 0 else "REAL")
        log.info("  Balance:        %.2f %s", acc.balance, acc.currency)
        log.info("  Equity:         %.2f %s", acc.equity, acc.currency)
        log.info("  Leverage:       1:%d", acc.leverage)
        log.info("  Free Margin:    %.2f %s", acc.margin_free, acc.currency)
        log.info("  Margin Level:   %.2f%%", acc.margin_level if acc.margin_level > 0 else 0)
        log.info("")

        # Verify DEMO account
        if acc.trade_mode != 0:
            log.error("⚠️  WARNING: This is a REAL/LIVE account!")
            log.error("    Cannot proceed with testing on live account")
            return False

        log.info("✅ DEMO account confirmed — safe to test")
        return True
    except Exception as e:
        log.error("Error retrieving account info: %s", e)
        return False


def main():
    log.info("MT5 Connection Verification Script")
    log.info("═══════════════════════════════════════════════════════════════════")
    log.info("")

    # Step 1: Initialize
    if not verify_mt5_connection():
        log.error("")
        log.error("VERIFICATION FAILED: Could not initialize MT5")
        sys.exit(1)

    # Step 2: Get terminal info
    if not get_terminal_info():
        log.warning("Warning: Could not retrieve terminal info (may be expected on some systems)")

    # Step 3: Get account info
    if not get_account_info():
        log.error("")
        log.error("VERIFICATION FAILED: Could not retrieve account info or live account detected")
        mt5.shutdown()
        sys.exit(1)

    log.info("═══════════════════════════════════════════════════════════════════")
    log.info("✅ ALL VERIFICATION CHECKS PASSED")
    log.info("═══════════════════════════════════════════════════════════════════")
    log.info("")
    log.info("Next steps:")
    log.info("  1. Run: python verify_symbol_specs.py")
    log.info("  2. Run: python verify_order_check.py")
    log.info("  3. Review test results before enabling live execution")
    log.info("")

    mt5.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
