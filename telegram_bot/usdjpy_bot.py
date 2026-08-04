"""Forex Trading Signal Bot — USDJPY"""
import os, time, logging
TELEGRAM_TOKEN = os.getenv("VANTAGE_EA_TOKEN", "")
CHAT_ID = os.getenv("SIGNAL_CHAT_ID", "")
logging.basicConfig(level=logging.INFO)
if __name__ == "__main__":
    if not TELEGRAM_TOKEN or not CHAT_ID:
        raise SystemExit("VANTAGE_EA_TOKEN and SIGNAL_CHAT_ID required")
    while True: time.sleep(60)
