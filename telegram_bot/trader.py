"""
MT5 Auto-Trader via Wine bridge (mt5linux)
============================================
No MetaAPI signup needed. MT5 terminal runs headlessly on this VPS under Wine.
wine_server.py must be running before this script starts.

Architecture:
  [MT5 terminal (Wine)] ← [MetaTrader5 pkg (Wine Python)] ← [wine_server.py :18812]
                                                                       ↑
  [trader.py - native Python] ← mt5linux client ────────────────────────

Setup: run setup_wine_mt5.sh once, then start_mt5_bridge.sh on every boot.
"""

import os
import sys
import json
import time
import logging
from datetime import datetime
from dotenv import load_dotenv

load_dotenv()

logging.basicConfig(
    format="%(asctime)s | TRADER   | %(levelname)s | %(message)s",
    level=logging.INFO,
)
log = logging.getLogger(__name__)

MT5_HOST     = os.getenv("MT5_HOST",     "localhost")
MT5_PORT     = int(os.getenv("MT5_PORT", "18812"))
MT5_LOGIN    = int(os.getenv("MT5_LOGIN",    "25285913"))
MT5_PASSWORD = os.getenv("MT5_PASSWORD", "")
MT5_SERVER   = os.getenv("MT5_SERVER",   "VantageMarkets-Demo")

QUEUE_FILE   = os.path.join(os.path.dirname(__file__), ".trade_queue.jsonl")
HISTORY_FILE = os.path.join(os.path.dirname(__file__), ".trade_history.jsonl")

LOT_SIZE      = 0.01   # micro lot — safe for demo
POLL_SECS     = 5
MAX_QUEUE_AGE = 300    # skip signals older than 5 minutes
DEVIATION     = 20     # max price slippage in points

# Magic numbers per bot+timeframe — visible in MT5 History tab
MAGIC_MAP = {
    "EURUSD_1H":  10101,
    "GBPUSD_1H":  10201,
    "USDJPY_1H":  10301,
    "XAUUSD_1H":  10401,
    "BTCUSD_1H":  10501,
    "EURUSD_15m": 10102,
    "GBPUSD_15m": 10202,
    "USDJPY_15m": 10302,
    "XAUUSD_15m": 10402,
}
DEFAULT_MAGIC = 10000


def _read_and_clear_queue() -> list:
    if not os.path.exists(QUEUE_FILE):
        return []
    try:
        with open(QUEUE_FILE, "r+") as f:
            lines = f.readlines()
            f.seek(0)
            f.truncate()
        signals = []
        for line in lines:
            line = line.strip()
            if line:
                try:
                    signals.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
        return signals
    except Exception as exc:
        log.warning("Queue read error: %s", exc)
        return []


def _write_history(signal: dict, result: str) -> None:
    try:
        record = dict(signal)
        record["result"]      = result
        record["executed_at"] = datetime.now().isoformat()
        with open(HISTORY_FILE, "a") as f:
            f.write(json.dumps(record) + "\n")
    except Exception:
        pass


def connect_mt5(mt5) -> bool:
    if not mt5.initialize():
        log.error("MT5 initialize failed: %s", mt5.last_error())
        return False
    if not mt5.login(MT5_LOGIN, password=MT5_PASSWORD, server=MT5_SERVER):
        log.error("MT5 login failed: %s", mt5.last_error())
        mt5.shutdown()
        return False
    info = mt5.account_info()
    log.info("MT5 connected | Login: %s | Balance: %.2f %s | Server: %s",
             info.login, info.balance, info.currency, MT5_SERVER)
    return True


def place_order(mt5, symbol: str, direction: str, sl: float, tp: float,
                magic: int, comment: str):
    # Make sure symbol is in Market Watch
    if not mt5.symbol_select(symbol, True):
        log.warning("symbol_select failed for %s — adding to Market Watch", symbol)

    tick = mt5.symbol_info_tick(symbol)
    if tick is None:
        log.error("No tick for %s — symbol unavailable on this account", symbol)
        return None

    order_type = mt5.ORDER_TYPE_BUY if direction == "BUY" else mt5.ORDER_TYPE_SELL
    price      = tick.ask              if direction == "BUY" else tick.bid

    request = {
        "action":       mt5.TRADE_ACTION_DEAL,
        "symbol":       symbol,
        "volume":       LOT_SIZE,
        "type":         order_type,
        "price":        price,
        "sl":           sl,
        "tp":           tp,
        "deviation":    DEVIATION,
        "magic":        magic,
        "comment":      comment,
        "type_time":    mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_IOC,
    }
    result = mt5.order_send(request)
    if result is None or result.retcode != mt5.TRADE_RETCODE_DONE:
        code = result.retcode if result else "None"
        msg  = result.comment if result else ""
        log.error("Order FAILED: %s %s  retcode=%s  %s", direction, symbol, code, msg)
        return None

    log.info("Trade placed: %s %s  lot=%.2f  price=%.5g  ticket=%d  magic=%d",
             direction, symbol, LOT_SIZE, result.price, result.order, magic)
    return result


def main():
    if not MT5_PASSWORD:
        log.error("MT5_PASSWORD not set in .env")
        sys.exit(1)

    try:
        from mt5linux import MetaTrader5
    except ImportError:
        log.error("mt5linux not installed. Run: pip install mt5linux")
        sys.exit(1)

    mt5 = MetaTrader5(host=MT5_HOST, port=MT5_PORT)

    log.info("Connecting to MT5 bridge at %s:%d ...", MT5_HOST, MT5_PORT)
    while not connect_mt5(mt5):
        log.warning("Retrying in 30s — make sure start_mt5_bridge.sh is running")
        time.sleep(30)

    log.info("Trader ready | lot=%.2f  poll=%ds  login=%d", LOT_SIZE, POLL_SECS, MT5_LOGIN)

    while True:
        time.sleep(POLL_SECS)

        # Reconnect if connection dropped
        if mt5.account_info() is None:
            log.warning("MT5 connection lost — reconnecting...")
            if not connect_mt5(mt5):
                time.sleep(30)
                continue

        signals = _read_and_clear_queue()
        for sig in signals:
            age = time.time() - sig.get("ts", 0)
            if age > MAX_QUEUE_AGE:
                log.warning("SKIP stale %s %s (age=%.0fs)",
                            sig.get("direction"), sig.get("symbol"), age)
                _write_history(sig, f"skipped_stale age={age:.0f}s")
                continue

            symbol    = sig["symbol"]
            direction = sig["direction"].upper()
            sl        = float(sig["sl"])
            tp        = float(sig["tp"])
            src       = sig.get("source", "")
            magic     = MAGIC_MAP.get(src, DEFAULT_MAGIC)
            comment   = f"{src} #{magic}"

            log.info("Signal: %s %s  SL=%.5g  TP=%.5g  magic=%d  src=%s",
                     direction, symbol, sl, tp, magic, src)

            result = place_order(mt5, symbol, direction, sl, tp, magic, comment)
            if result:
                _write_history(sig, f"ok ticket={result.order} price={result.price}")
            else:
                _write_history(sig, "error: order_send failed — check trader.log")


if __name__ == "__main__":
    main()
