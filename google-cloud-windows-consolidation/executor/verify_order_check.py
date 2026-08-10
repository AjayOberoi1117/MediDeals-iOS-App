"""
Verify order_check preflight validation.
Tests mt5.order_check() to validate order parameters without placing trades.
Does NOT call order_send().
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
    format="%(asctime)s | VERIFY_ORDERS | %(levelname)s | %(message)s",
    level=logging.INFO,
)
log = logging.getLogger(__name__)

MT5_LOGIN = int(os.getenv("MT5_LOGIN", "0"))
MT5_PASSWORD = os.getenv("MT5_PASSWORD", "")
MT5_SERVER = os.getenv("MT5_SERVER", "")

# Test parameters for each symbol
TEST_ORDERS = [
    {
        "symbol": "EURUSD",
        "direction": "BUY",
        "volume": 0.01,  # Minimum lot
        "entry_offset": 0.0010,
        "sl_pips": 0.0050,
        "tp_pips": 0.0150,
    },
    {
        "symbol": "GBPUSD",
        "direction": "SELL",
        "volume": 0.01,
        "entry_offset": 0.0010,
        "sl_pips": 0.0050,
        "tp_pips": 0.0150,
    },
    {
        "symbol": "XAUUSD",
        "direction": "BUY",
        "volume": 0.01,
        "entry_offset": 1.0,
        "sl_pips": 5.0,
        "tp_pips": 15.0,
    },
    {
        "symbol": "BTCUSD",
        "direction": "SELL",
        "volume": 0.01,
        "entry_offset": 100.0,
        "sl_pips": 500.0,
        "tp_pips": 1500.0,
    },
]


def check_order(symbol: str, direction: str, volume: float, sl: float, tp: float) -> bool:
    """Check an order without sending it."""
    try:
        order_type = mt5.ORDER_TYPE_BUY if direction == "BUY" else mt5.ORDER_TYPE_SELL
        tick = mt5.symbol_info_tick(symbol)

        if tick is None:
            log.warning("  ⚠️  No tick data for %s (market closed)", symbol)
            return False

        price = tick.ask if direction == "BUY" else tick.bid

        req = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": symbol,
            "volume": volume,
            "type": order_type,
            "price": price,
            "sl": sl,
            "tp": tp,
            "deviation": 30,
            "magic": 99999,
            "comment": "PREFLIGHT_CHECK",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }

        result = mt5.order_check(req)
        if result is None:
            log.error("  ❌ order_check returned None: %s", mt5.last_error())
            return False

        if result.retcode == mt5.TRADE_RETCODE_DONE:
            log.info("  ✅ %s %s | Volume: %.2f | Price: %.5f | SL: %.5f | TP: %.5f",
                     direction, symbol, volume, price, sl, tp)
            log.info("     Balance: %.2f | Margin: %.2f | Free: %.2f",
                     result.balance, result.margin, result.margin_free)
            return True
        else:
            log.warning("  ❌ order_check failed | retcode=%d: %s",
                        result.retcode, result.comment)
            return False
    except Exception as e:
        log.error("  ❌ Error checking order: %s", e)
        return False


def main():
    log.info("Order Preflight Verification Script")
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

    log.info("Testing sample orders with order_check() [NO ORDERS SENT]...")
    log.info("")

    passed = 0
    for test in TEST_ORDERS:
        symbol = test["symbol"]
        direction = test["direction"]
        volume = test["volume"]

        # Get current price
        tick = mt5.symbol_info_tick(symbol)
        if tick is None:
            log.warning("Skipping %s (no tick data)", symbol)
            continue

        price = tick.ask if direction == "BUY" else tick.bid
        sl = price - test["sl_pips"] if direction == "BUY" else price + test["sl_pips"]
        tp = price + test["tp_pips"] if direction == "BUY" else price - test["tp_pips"]

        if check_order(symbol, direction, volume, sl, tp):
            passed += 1

    log.info("")
    log.info("═══════════════════════════════════════════════════════════════════")
    log.info("SUMMARY: %d/%d test orders passed preflight", passed, len(TEST_ORDERS))
    log.info("═══════════════════════════════════════════════════════════════════")
    log.info("")

    if passed == len(TEST_ORDERS):
        log.info("✅ All preflight checks passed")
        log.info("")
        log.info("System is ready for execution!")
        log.info("To enable live trading:")
        log.info("  1. Update .env with BOT_EXECUTION_MODE=production")
        log.info("  2. Update .env with LIVE_TRADING_CONFIRMED=YES")
        log.info("  3. Run: python windows_mt5_executor.py")
        mt5.shutdown()
        return 0
    else:
        log.error("❌ Some preflight checks failed")
        mt5.shutdown()
        sys.exit(1)


if __name__ == "__main__":
    sys.exit(main())
