"""
Forex Trading Signal Bot — EURUSD
Strategy : EMA(9/21) crossover + RSI(14) on 1-hour bars
Data     : Yahoo Finance EURUSD with caching
Signals  : Telegram via VANTAGE_EA_TOKEN
"""

import os
import time
import logging
from datetime import datetime

TELEGRAM_TOKEN = os.getenv("VANTAGE_EA_TOKEN", "")
CHAT_ID = os.getenv("SIGNAL_CHAT_ID", "")

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

if __name__ == "__main__":
    if not TELEGRAM_TOKEN or not CHAT_ID:
        raise SystemExit("VANTAGE_EA_TOKEN and SIGNAL_CHAT_ID required in .env")
    log.info("EURUSD Bot started")
    while True:
        time.sleep(60)
