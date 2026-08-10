"""Read-only Windows MT5 connection and account verification.

The script initializes the local terminal and reads metadata only.  It never
selects symbols, checks orders, sends orders, or changes terminal settings.
"""

import logging
import os
import sys

from dotenv import load_dotenv

try:
    import MetaTrader5 as mt5
except ImportError:
    print("ERROR: MetaTrader5 package not installed.")
    sys.exit(1)

from mt5_connection import discover_terminal_path, initialize_mt5

load_dotenv()

logging.basicConfig(
    format="%(asctime)s | VERIFY_MT5 | %(levelname)s | %(message)s",
    level=logging.INFO,
)
log = logging.getLogger(__name__)

MT5_LOGIN = int(os.getenv("MT5_LOGIN", "0"))
MT5_PASSWORD = os.getenv("MT5_PASSWORD", "")
MT5_SERVER = os.getenv("MT5_SERVER", "")


def trade_mode_name(mode):
    names = {
        getattr(mt5, "ACCOUNT_TRADE_MODE_DEMO", 0): "DEMO",
        getattr(mt5, "ACCOUNT_TRADE_MODE_CONTEST", 1): "CONTEST",
        getattr(mt5, "ACCOUNT_TRADE_MODE_REAL", 2): "REAL",
    }
    return names.get(mode, f"UNKNOWN ({mode})")


def main():
    terminal_path = discover_terminal_path()
    log.info("terminal executable path: %s", terminal_path or "NOT FOUND")

    if not MT5_LOGIN or not MT5_PASSWORD or not MT5_SERVER:
        log.error("initialize: False")
        log.error("last_error: configuration missing MT5_LOGIN, MT5_PASSWORD, or MT5_SERVER")
        return 1

    initialized, terminal_path = initialize_mt5(
        mt5, login=MT5_LOGIN, password=MT5_PASSWORD, server=MT5_SERVER
    )
    log.info("initialize: %s", initialized)
    log.info("last_error: %s", mt5.last_error())
    if not initialized:
        return 1

    try:
        account = mt5.account_info()
        terminal = mt5.terminal_info()
        symbols_total = mt5.symbols_total()

        log.info("account login: %s", account.login if account else "UNAVAILABLE")
        log.info("server: %s", account.server if account else "UNAVAILABLE")
        log.info("company: %s", account.company if account else "UNAVAILABLE")
        log.info("trade_mode: %s", trade_mode_name(account.trade_mode) if account else "UNAVAILABLE")
        log.info("terminal connected: %s", terminal.connected if terminal else "UNAVAILABLE")
        log.info("trade_allowed: %s", terminal.trade_allowed if terminal else "UNAVAILABLE")
        log.info("symbols_total: %s", symbols_total)

        if account is None or terminal is None:
            log.error("Read-only verification incomplete: %s", mt5.last_error())
            return 1
        if account.trade_mode == getattr(mt5, "ACCOUNT_TRADE_MODE_REAL", 2):
            log.error("REAL account detected; execution remains prohibited")
            return 2
        if not terminal.connected:
            log.error("Terminal initialized but is not connected")
            return 1
        return 0
    finally:
        mt5.shutdown()


if __name__ == "__main__":
    sys.exit(main())
