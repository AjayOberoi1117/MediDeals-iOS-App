"""
signal_server.py — Tiny HTTP server on GCP
Serves the latest trade signal as CSV so the Mac sync script can fetch it.
Port 8080. Runs alongside the trading bots.

The signal bots call queue_trade() → trade_executor.py appends to
.trade_queue.jsonl. This server reads that queue, converts to CSV,
serves it, then clears the queue so each signal fires only once.

CSV format (matches TradeFromFile.mq5):
    SYMBOL,DIRECTION,SL,TP,MAGIC,SOURCE,TIMESTAMP
"""

import json
import os
import time
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

QUEUE_FILE  = os.path.join(os.path.dirname(__file__), ".trade_queue.jsonl")
PORT        = 8080
_lock       = threading.Lock()
_pending    = []   # list of CSV lines ready to serve

MAGIC_MAP = {
    "EURUSD": 10001,
    "GBPUSD": 10002,
    "USDJPY": 10003,
    "XAUUSD": 10004,
    "BTCUSD": 10005,
}


def _flush_queue():
    """Read .trade_queue.jsonl, convert to CSV lines, clear the file."""
    if not os.path.exists(QUEUE_FILE):
        return
    with _lock:
        try:
            with open(QUEUE_FILE, "r") as f:
                lines = f.readlines()
            # Clear immediately so signals aren't re-served
            open(QUEUE_FILE, "w").close()
        except Exception:
            return

    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            sig    = json.loads(line)
            symbol = sig["symbol"]
            magic  = MAGIC_MAP.get(symbol, 99999)
            csv    = f"{symbol},{sig['direction']},{sig['sl']},{sig['tp']},{magic},{sig.get('source','')},{int(sig.get('ts', time.time()))}"
            with _lock:
                _pending.append(csv)
        except Exception:
            pass


class SignalHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass   # suppress access logs to keep GCP terminal clean

    def do_GET(self):
        if self.path not in ("/signal", "/signal.csv", "/"):
            self.send_response(404); self.end_headers(); return

        _flush_queue()

        with _lock:
            body = "\n".join(_pending) + "\n" if _pending else ""
            _pending.clear()

        encoded = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


def main():
    server = HTTPServer(("0.0.0.0", PORT), SignalHandler)
    print(f"Signal server listening on port {PORT}")
    print(f"Mac sync script should poll: http://<GCP_IP>:{PORT}/signal")
    server.serve_forever()


if __name__ == "__main__":
    main()
