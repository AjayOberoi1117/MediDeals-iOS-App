"""
Verify broker symbol specifications.
Checks that required trading symbols are accessible and tradeable.
Does NOT place any orders.
"""

import os
import sys
import logging
from dotenv import load_dotenv
from mt5_connection import initialize_mt5

try:
    import MetaTrader5 as mt5
except ImportError:
    print("ERROR: MetaTrader5 package not installed.")
    sys.exit(1)

load_dotenv()

logging.basicConfig(
    format="%(asctime)s | VERIFY_SYMBOLS | %(levelname)s | %(message)s",
    level=logging.INFO,
)
log = logging.getLogger(__name__)

MT5_LOGIN = int(os.getenv("MT5_LOGIN", "0"))
MT5_PASSWORD = os.getenv("MT5_PASSWORD", "")
MT5_SERVER = os.getenv("MT5_SERVER", "")

# Symbols used by trading bots
REQUIRED_SYMBOLS = [
    "EURUSD",
    "GBPUSD",
    "XAUUSD",
    "BTCUSD",
]

# Optional symbols (may not be available on all brokers)
OPTIONAL_SYMBOLS = [
    "USDJPY",
]


def verify_symbol(symbol: str) -> bool:
    """Verify a single symbol and display its specs."""
    try:
        info = mt5.symbol_info(symbol)
        if info is None:
            log.warning("  ❌ %s — NOT FOUND", symbol)
            return False

        # Check if visible and tradeable
        if not info.visible:
            log.info("  ⚠️  %s — not visible, attempting to select...", symbol)
            mt5.symbol_select(symbol, True)
            info = mt5.symbol_info(symbol)
            if info is None or not info.visible:
                log.warning("  ❌ %s — could not make visible", symbol)
                return False

        # Get tick data
        tick = mt5.symbol_info_tick(symbol)
        if tick is None:
            log.warning("  ⚠️  %s — no tick data (market may be closed)", symbol)
        else:
            bid = tick.bid
            ask = tick.ask
            log.info("  ✅ %s | Bid: %.5f | Ask: %.5f", symbol, bid, ask)

        # Display symbol specifications
        log.info("     Digits: %d | Point: %g | Volume Min: %.0f | Volume Max: %.0f",
                 info.digits, info.point, info.volume_min, info.volume_max)
        log.info("     Volume Step: %.0f | Trade Stops Level: %d | Trade Mode: %s",
                 info.volume_step, info.trade_stops_level, info.trade_mode)

        mode_name = "BUY/SELL" if info.trade_mode == mt5.SYMBOL_TRADE_MODE_FULL else \
                    "LONG" if info.trade_mode == mt5.SYMBOL_TRADE_MODE_LONG else \
                    "SHORT" if info.trade_mode == mt5.SYMBOL_TRADE_MODE_SHORT else \
                    "CLOSE" if info.trade_mode == mt5.SYMBOL_TRADE_MODE_CLOSE_ONLY else "UNKNOWN"
        log.info("     Allowed Trade Mode: %s", mode_name)

        return True
    except Exception as e:
        log.error("  ❌ %s — error: %s", symbol, e)
        return False


def main():
    log.info("Symbol Specification Verification Script")
    log.info("═══════════════════════════════════════════════════════════════════")
    log.info("")

    # Initialize MT5
    initialized, terminal_path = initialize_mt5(
        mt5, login=MT5_LOGIN, password=MT5_PASSWORD, server=MT5_SERVER
    )
    log.info("Terminal executable: %s", terminal_path or "NOT FOUND")
    if not initialized:
        log.error("MT5 initialization failed: %s", mt5.last_error())
        sys.exit(1)

    log.info("Checking REQUIRED symbols...")
    log.info("")
    required_ok = 0
    for symbol in REQUIRED_SYMBOLS:
        if verify_symbol(symbol):
            required_ok += 1
    log.info("")

    log.info("Checking OPTIONAL symbols...")
    log.info("")
    optional_ok = 0
    for symbol in OPTIONAL_SYMBOLS:
        if verify_symbol(symbol):
            optional_ok += 1
    log.info("")

    log.info("═══════════════════════════════════════════════════════════════════")
    log.info("SUMMARY: %d/%d required symbols available | %d/%d optional symbols available",
             required_ok, len(REQUIRED_SYMBOLS), optional_ok, len(OPTIONAL_SYMBOLS))
    log.info("═══════════════════════════════════════════════════════════════════")
    log.info("")

    if required_ok == len(REQUIRED_SYMBOLS):
        log.info("✅ All required symbols verified")
        log.info("")
        log.info("Next step: python verify_order_check.py")
        mt5.shutdown()
        return 0
    else:
        log.error("❌ Some required symbols not available")
        log.error("    Execution cannot proceed without all required symbols")
        mt5.shutdown()
        sys.exit(1)


if __name__ == "__main__":
    sys.exit(main())
