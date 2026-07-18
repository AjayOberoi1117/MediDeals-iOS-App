"""
Mac-local trade writer — bypasses GCP signal_server entirely.
Writes the signal CSV directly into MT5's MQL5/Files folder so
TradeFromFile EA can execute it immediately.
"""

import os
import time
import logging

log = logging.getLogger(__name__)

MT5_FILES = os.path.expanduser(
    "~/Library/Application Support/net.metaquotes.wine.metatrader5"
    "/drive_c/Program Files/MetaTrader 5/MQL5/Files"
)

MAGIC_MAP = {
    "EURUSD": 10001,
    "GBPUSD": 10002,
    "USDJPY": 10003,
    "XAUUSD": 10004,
    "BTCUSD": 10005,
}

def queue_trade(symbol, direction, sl, tp, source="", **kwargs):
    magic = MAGIC_MAP.get(symbol, 10000)
    ts    = int(time.time())
    line  = f"{symbol},{direction},{sl},{tp},{magic},{source},{ts}"
    csv_path = os.path.join(MT5_FILES, "mt5_signals.csv")
    try:
        os.makedirs(MT5_FILES, exist_ok=True)
        with open(csv_path, "w") as f:
            f.write(line + "\n")
        log.info("Signal written directly to MT5: %s", line)
    except Exception as exc:
        log.warning("Could not write to MT5 Files: %s", exc)
