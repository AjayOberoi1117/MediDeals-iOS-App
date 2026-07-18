"""
MT5 File-Bridge Trader
======================
Reads signals from .trade_queue.jsonl and writes them to MT5's MQL5/Files
folder as mt5_signals.csv. The TradeFromFile.mq5 EA reads that file and
executes trades natively inside MT5 — no Wine Python API needed.

Architecture:
  signal bots → .trade_queue.jsonl → trader.py → mt5_signals.csv
                                                       ↓
                               TradeFromFile.mq5 EA (inside MT5)
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

# MT5 MQL5/Files folder — where the EA reads signals from
MT5_FILES    = os.getenv("MT5_FILES_PATH",
    "/root/.wine_mt5/drive_c/Program Files/MetaTrader 5/MQL5/Files")
SIGNALS_FILE = os.path.join(MT5_FILES, "mt5_signals.csv")

QUEUE_FILE   = os.path.join(os.path.dirname(__file__), ".trade_queue.jsonl")
HISTORY_FILE = os.path.join(os.path.dirname(__file__), ".trade_history.jsonl")

POLL_SECS     = 5
MAX_QUEUE_AGE = 300    # skip signals older than 5 minutes

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


def _write_signal(symbol, direction, sl, tp, magic, source, ts):
    """Append one CSV line to MT5's Files folder for the EA to pick up."""
    os.makedirs(MT5_FILES, exist_ok=True)
    line = f"{symbol},{direction},{sl:.5f},{tp:.5f},{magic},{source},{ts:.0f}\n"
    with open(SIGNALS_FILE, "a") as f:
        f.write(line)
    log.info("Signal → MT5: %s %s  sl=%.5g  tp=%.5g  magic=%d  src=%s",
             direction, symbol, sl, tp, magic, source)


def main():
    if not os.path.isdir(MT5_FILES):
        log.error("MT5 Files folder not found: %s", MT5_FILES)
        log.error("Is MT5 running under Wine? Check MT5_FILES_PATH in .env")
        sys.exit(1)

    log.info("Trader ready (file-bridge mode)")
    log.info("MT5 Files: %s", MT5_FILES)
    log.info("Polling queue every %ds", POLL_SECS)

    while True:
        time.sleep(POLL_SECS)

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
            ts        = sig.get("ts", time.time())

            _write_signal(symbol, direction, sl, tp, magic, src, ts)
            _write_history(sig, f"forwarded_to_ea magic={magic}")


if __name__ == "__main__":
    main()
