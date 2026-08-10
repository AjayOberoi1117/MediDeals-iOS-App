"""
Queue-writer for MT5 auto-trader (Windows Native).
Signal bots import queue_trade() and call it when a signal fires.
Windows MT5 executor reads the queue and executes via MetaTrader5 API.
No MetaTrader5 SDK import here — this stays synchronous and lightweight.
"""

import json
import os
import time
import threading
import logging
from pathlib import Path

log = logging.getLogger(__name__)

# Windows-specific paths
TRADING_BOTS_ROOT = Path("C:\\TradingBots")
STATE_DIR = TRADING_BOTS_ROOT / "state"
STATE_DIR.mkdir(parents=True, exist_ok=True)

QUEUE_FILE = STATE_DIR / ".trade_queue.jsonl"
_lock = threading.Lock()

# Only these symbols are auto-traded on Vantage (Indian market instruments skipped)
TRADEABLE = {"EURUSD", "GBPUSD", "USDJPY", "XAUUSD", "BTCUSD"}


def queue_trade(symbol: str, direction: str, sl: float, tp: float, source: str = "") -> bool:
    """Append a trade signal to the queue file. Returns True if queued."""
    if symbol not in TRADEABLE:
        log.debug("AUTO-TRADE SKIP %s — not in Vantage instrument list", symbol)
        return False
    signal = {
        "symbol":    symbol,
        "direction": direction.upper(),
        "sl":        sl,
        "tp":        tp,
        "source":    source,
        "ts":        time.time(),
    }
    try:
        with _lock:
            with open(QUEUE_FILE, "a", encoding="utf-8") as f:
                f.write(json.dumps(signal) + "\n")
        log.info("AUTO-TRADE QUEUED: %s %s  SL=%.5g  TP=%.5g", direction, symbol, sl, tp)
        return True
    except Exception as exc:
        log.warning("queue_trade failed: %s", exc)
        return False
