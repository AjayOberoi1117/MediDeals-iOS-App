#!/usr/bin/env python3
"""
Windows VPS Signal Receiver Service
====================================

Receives signals from DigitalOcean via HTTP and writes to MT5 Files folder.
TradeFromFile EA polls the CSV and executes trades.

Installation on Windows VPS:
  1. Save as: C:\MediDeals\signal_receiver.py
  2. Install Python 3.9+
  3. Create environment file: C:\MediDeals\.env
  4. Install nssm (Non-Sucking Service Manager)
  5. Run this script as Windows service

Environment (.env):
  RECEIVER_AUTH_TOKEN=your_shared_secret_token
  MT5_FILES_PATH=C:\Program Files\MetaTrader 5\MQL5\Files
  RECEIVER_PORT=8888
  RECEIVER_HOST=127.0.0.1
  LOG_FILE=C:\MediDeals\receiver.log
"""

import os
import sys
import json
import time
import logging
from pathlib import Path
from http.server import HTTPServer, BaseHTTPRequestHandler
from threading import Thread, Event
from datetime import datetime
from dotenv import load_dotenv

# Load environment
load_dotenv()

################################################################################
# CONFIG
################################################################################

AUTH_TOKEN = os.getenv("RECEIVER_AUTH_TOKEN", "change_me_immediately")
MT5_FILES_PATH = Path(os.getenv(
    "MT5_FILES_PATH",
    "C:/Program Files/MetaTrader 5/MQL5/Files"
))
RECEIVER_HOST = os.getenv("RECEIVER_HOST", "127.0.0.1")
RECEIVER_PORT = int(os.getenv("RECEIVER_PORT", "8888"))
LOG_FILE = Path(os.getenv("LOG_FILE", "C:/MediDeals/receiver.log"))
SIGNALS_FILE = MT5_FILES_PATH / "mt5_signals.csv"

# Ensure log directory exists
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)

################################################################################
# LOGGING
################################################################################

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | RECEIVER | %(levelname)s | %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
log = logging.getLogger(__name__)

################################################################################
# SIGNAL HANDLER
################################################################################

class SignalRequestHandler(BaseHTTPRequestHandler):
    """HTTP request handler for signal reception."""

    def do_POST(self):
        """Handle POST request with signal."""

        # Only accept /signal endpoint
        if self.path != "/signal":
            self.send_error(404, "Not found")
            return

        # Verify authorization
        auth_header = self.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            self.send_error(401, "Missing authorization")
            log.warning(f"Rejected: missing auth token from {self.client_address[0]}")
            return

        token = auth_header[7:]  # Remove "Bearer " prefix
        if token != AUTH_TOKEN:
            self.send_error(401, "Invalid token")
            log.warning(f"Rejected: invalid auth token from {self.client_address[0]}")
            return

        # Read request body
        try:
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode("utf-8")
        except Exception as e:
            self.send_error(400, "Cannot read body")
            log.error(f"Read error: {e}")
            return

        # Parse JSON
        try:
            signal = json.loads(body)
        except json.JSONDecodeError as e:
            self.send_error(400, "Invalid JSON")
            log.error(f"JSON parse error: {e}")
            return

        # Process signal
        if self._process_signal(signal):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            response = json.dumps({"status": "accepted", "timestamp": datetime.now().isoformat()})
            self.wfile.write(response.encode())
        else:
            self.send_error(400, "Signal rejected")

    def _process_signal(self, signal):
        """Validate and write signal to MT5 Files folder."""

        try:
            # Extract fields
            symbol = signal.get("symbol", "").upper()
            direction = signal.get("direction", "").upper()
            sl = float(signal.get("sl", 0))
            tp = float(signal.get("tp", 0))
            source = signal.get("source", "unknown")
            ts = signal.get("ts", time.time())

            # Validate symbol
            approved_symbols = ["EURUSD", "GBPUSD", "XAUUSD", "BTCUSD"]
            if symbol not in approved_symbols:
                log.warning(f"REJECT: symbol {symbol} not approved")
                return False

            # Validate direction
            if direction not in ["BUY", "SELL"]:
                log.warning(f"REJECT: direction {direction} invalid")
                return False

            # Validate prices
            if sl == 0:
                log.warning(f"REJECT: {symbol} SL is zero")
                return False

            if tp == 0:
                log.warning(f"REJECT: {symbol} TP is zero")
                return False

            if sl == tp:
                log.warning(f"REJECT: {symbol} SL equals TP")
                return False

            # Write to MT5 Files
            MT5_FILES_PATH.mkdir(parents=True, exist_ok=True)

            line = f"{symbol},{direction},{sl:.5f},{tp:.5f},10000,{source},{ts:.0f}\n"

            with open(SIGNALS_FILE, "a") as f:
                f.write(line)

            log.info(f"ACCEPTED: {direction:4s} {symbol:6s} "
                    f"sl={sl:.5g} tp={tp:.5g} src={source}")

            return True

        except ValueError as e:
            log.error(f"Value error: {e}")
            return False

        except Exception as e:
            log.error(f"Processing error: {e}")
            return False

    def log_message(self, format, *args):
        """Suppress default HTTP logging."""
        pass

################################################################################
# SERVICE
################################################################################

class SignalReceiverService:
    """Windows service wrapper."""

    def __init__(self):
        self.server = None
        self.thread = None
        self.stop_event = Event()

    def start(self):
        """Start the service."""
        log.info("════════════════════════════════════════════════════════════════════")
        log.info("Signal Receiver Service Starting")
        log.info("════════════════════════════════════════════════════════════════════")

        log.info(f"Listening: http://{RECEIVER_HOST}:{RECEIVER_PORT}")
        log.info(f"MT5 Files: {MT5_FILES_PATH}")
        log.info(f"Signals file: {SIGNALS_FILE}")
        log.info("")

        # Verify MT5 Files folder exists
        if not MT5_FILES_PATH.exists():
            log.error(f"MT5 Files folder not found: {MT5_FILES_PATH}")
            log.error("Is MT5 installed? Check path in .env")
            return False

        log.info("MT5 Files folder verified")

        # Create HTTP server
        try:
            self.server = HTTPServer((RECEIVER_HOST, RECEIVER_PORT), SignalRequestHandler)
        except OSError as e:
            log.error(f"Cannot bind to {RECEIVER_HOST}:{RECEIVER_PORT}: {e}")
            return False

        # Run server in background thread
        self.thread = Thread(target=self._run_server, daemon=True)
        self.thread.start()

        log.info("Service started successfully")
        log.info("Ready to receive signals from DigitalOcean")

        return True

    def _run_server(self):
        """Run server until stop_event is set."""
        while not self.stop_event.is_set():
            try:
                self.server.handle_request()
            except KeyboardInterrupt:
                break
            except Exception as e:
                log.error(f"Server error: {e}")

    def stop(self):
        """Stop the service."""
        log.info("Service stopping...")
        self.stop_event.set()
        if self.server:
            self.server.server_close()
        if self.thread:
            self.thread.join(timeout=5)
        log.info("Service stopped")

################################################################################
# MAIN
################################################################################

def main():
    """Main entry point."""

    service = SignalReceiverService()

    if not service.start():
        sys.exit(1)

    try:
        # Keep service running
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        service.stop()
    except Exception as e:
        log.error(f"Fatal error: {e}", exc_info=True)
        service.stop()
        sys.exit(1)

if __name__ == "__main__":
    main()
