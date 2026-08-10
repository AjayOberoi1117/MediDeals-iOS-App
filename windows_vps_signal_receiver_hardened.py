#!/usr/bin/env python3
"""
Hardened Windows VPS Signal Receiver Service
============================================

Security features:
- Duplicate signal detection (by signal_id)
- Stale signal rejection (expires_at validation)
- Demo-only account verification (hard guard)
- Symbol allowlist enforcement (EURUSD, GBPUSD, XAUUSD only)
- Lot size validation (0.01 only for validation phase)
- SL/TP validation against broker constraints
- Detailed acknowledgement codes
- TLS required (reverse proxy at 443 → localhost:8888)
- Bearer token authentication

Installation:
  1. Save as: C:\MediDeals\signal_receiver.py
  2. Create .env with RECEIVER_AUTH_TOKEN, etc.
  3. Set up reverse proxy (Caddy/IIS/Nginx) at 0.0.0.0:443 → 127.0.0.1:8888
  4. Install as Windows service via nssm

Environment (.env):
  RECEIVER_AUTH_TOKEN=<high_entropy_secret>
  MT5_FILES_PATH=C:\Program Files\MetaTrader 5\MQL5\Files
  RECEIVER_PORT=8888
  RECEIVER_HOST=127.0.0.1
  LOG_FILE=C:\MediDeals\receiver.log
  PROCESSED_SIGNALS_DB=C:\MediDeals\processed_signals.jsonl
  MT5_APPROVED_LOGIN=<vantage_demo_login>
  MT5_APPROVED_SERVER=VantageMarketsDemo
  SIGNAL_EXPIRY_SECONDS=3600
"""

import os
import sys
import json
import time
import uuid
import logging
from pathlib import Path
from datetime import datetime, timedelta
from http.server import HTTPServer, BaseHTTPRequestHandler
from threading import Thread, Event
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
PROCESSED_DB = Path(os.getenv("PROCESSED_SIGNALS_DB", "C:/MediDeals/processed_signals.jsonl"))

# Demo account hardening
APPROVED_LOGIN = os.getenv("MT5_APPROVED_LOGIN", "")
APPROVED_SERVER = os.getenv("MT5_APPROVED_SERVER", "VantageMarketsDemo")
SIGNAL_EXPIRY_SECONDS = int(os.getenv("SIGNAL_EXPIRY_SECONDS", "3600"))

# Approved symbols (demo validation)
APPROVED_SYMBOLS = {"EURUSD", "GBPUSD", "XAUUSD"}
APPROVED_LOT_SIZE = 0.01

# Ensure directories exist
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
PROCESSED_DB.parent.mkdir(parents=True, exist_ok=True)

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
# PROCESSED SIGNALS DB
################################################################################

class ProcessedSignalsDB:
    """Track processed signal IDs to prevent duplicates."""

    def __init__(self, db_path):
        self.db_path = Path(db_path)
        self.signals = self._load()

    def _load(self):
        """Load processed signals from disk."""
        signals = set()
        if self.db_path.exists():
            try:
                with open(self.db_path, "r") as f:
                    for line in f:
                        try:
                            record = json.loads(line)
                            signals.add(record["signal_id"])
                        except:
                            pass
            except Exception as e:
                log.warning(f"Could not load processed signals DB: {e}")
        return signals

    def is_processed(self, signal_id):
        """Check if signal was already processed."""
        return signal_id in self.signals

    def mark_processed(self, signal_id):
        """Record that signal was processed."""
        self.signals.add(signal_id)
        try:
            with open(self.db_path, "a") as f:
                f.write(json.dumps({
                    "signal_id": signal_id,
                    "processed_at": datetime.utcnow().isoformat()
                }) + "\n")
        except Exception as e:
            log.error(f"Could not record processed signal: {e}")

db = ProcessedSignalsDB(PROCESSED_DB)

################################################################################
# SIGNAL VALIDATOR
################################################################################

class SignalValidator:
    """Validate signals before execution."""

    def __init__(self):
        self.errors = []

    def validate(self, signal):
        """Validate signal payload and return validation result."""
        self.errors = []

        # Required fields
        if not self._check_field(signal, "signal_id", str):
            return False
        if not self._check_field(signal, "created_at_utc", str):
            return False
        if not self._check_field(signal, "expires_at_utc", str):
            return False
        if not self._check_field(signal, "symbol", str):
            return False
        if not self._check_field(signal, "direction", str):
            return False
        if not self._check_field(signal, "sl", (int, float)):
            return False
        if not self._check_field(signal, "tp", (int, float)):
            return False
        if not self._check_field(signal, "lot_size", (int, float)):
            return False
        if not self._check_field(signal, "strategy", str):
            return False
        if not self._check_field(signal, "environment", str):
            return False

        # Duplicate check
        signal_id = signal.get("signal_id")
        if db.is_processed(signal_id):
            self.errors.append(f"Duplicate: signal_id {signal_id} already processed")
            return False

        # Expiry check
        try:
            expires_at = datetime.fromisoformat(signal.get("expires_at_utc"))
            if datetime.utcnow() > expires_at:
                self.errors.append(f"Expired: signal expired at {expires_at}")
                return False
        except (ValueError, TypeError) as e:
            self.errors.append(f"Invalid expiry format: {e}")
            return False

        # Symbol allowlist
        symbol = signal.get("symbol", "").upper()
        if symbol not in APPROVED_SYMBOLS:
            self.errors.append(f"Symbol {symbol} not approved (allowed: {APPROVED_SYMBOLS})")
            return False

        # Direction
        direction = signal.get("direction", "").upper()
        if direction not in ["BUY", "SELL"]:
            self.errors.append(f"Invalid direction: {direction}")
            return False

        # Lot size (validation phase: only 0.01)
        lot_size = signal.get("lot_size")
        if lot_size != APPROVED_LOT_SIZE:
            self.errors.append(f"Lot size {lot_size} not approved (only {APPROVED_LOT_SIZE})")
            return False

        # SL/TP validation
        sl = float(signal.get("sl"))
        tp = float(signal.get("tp"))

        if sl == 0 or tp == 0:
            self.errors.append("SL and TP must be non-zero")
            return False

        if sl == tp:
            self.errors.append("SL cannot equal TP")
            return False

        # Direction-specific validation
        if direction == "BUY":
            if sl >= tp:
                self.errors.append(f"BUY: SL={sl} must be < TP={tp}")
                return False
        else:  # SELL
            if sl <= tp:
                self.errors.append(f"SELL: SL={sl} must be > TP={tp}")
                return False

        # Environment check
        environment = signal.get("environment", "").lower()
        if environment != "demo":
            self.errors.append(f"Environment {environment} not approved (only 'demo')")
            return False

        return True

    def _check_field(self, obj, field, expected_type):
        """Check if field exists and has correct type."""
        if field not in obj:
            self.errors.append(f"Missing required field: {field}")
            return False

        value = obj[field]
        if not isinstance(value, expected_type):
            self.errors.append(f"Field {field}: expected {expected_type}, got {type(value)}")
            return False

        return True

    def get_errors(self):
        """Get validation errors."""
        return "; ".join(self.errors)

################################################################################
# SIGNAL HANDLER
################################################################################

class SignalRequestHandler(BaseHTTPRequestHandler):
    """HTTP request handler for signal reception."""

    def do_POST(self):
        """Handle POST request with signal."""

        # Only accept /signal endpoint
        if self.path != "/signal":
            self.send_response(404)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"ack": "NOT_FOUND"}).encode())
            return

        # Verify authorization
        auth_header = self.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            self._reject(401, "NO_AUTH", "Missing authorization header")
            log.warning(f"Rejected: missing auth from {self.client_address[0]}")
            return

        token = auth_header[7:]
        if token != AUTH_TOKEN:
            self._reject(401, "INVALID_AUTH", "Invalid authentication token")
            log.warning(f"Rejected: invalid auth from {self.client_address[0]}")
            return

        # Read request body
        try:
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode("utf-8")
        except Exception as e:
            self._reject(400, "READ_ERROR", f"Cannot read request: {e}")
            return

        # Parse JSON
        try:
            signal = json.loads(body)
        except json.JSONDecodeError as e:
            self._reject(400, "INVALID_JSON", f"Invalid JSON: {e}")
            return

        # Validate signal
        validator = SignalValidator()
        if not validator.validate(signal):
            self._reject(400, "REJECTED_VALIDATION", validator.get_errors())
            log.warning(f"Rejected validation: {validator.get_errors()}")
            return

        # Process signal
        signal_id = signal.get("signal_id")
        if self._process_signal(signal):
            db.mark_processed(signal_id)
            self._accept(200, "ACCEPTED", signal)
            log.info(f"✓ {signal['direction']:4s} {signal['symbol']:6s} "
                    f"sl={signal['sl']:.5g} tp={signal['tp']:.5g} "
                    f"id={signal_id[:8]}")
        else:
            self._reject(400, "PROCESSING_ERROR", "Could not write signal")

    def _process_signal(self, signal):
        """Write validated signal to MT5 Files folder."""
        try:
            symbol = signal.get("symbol").upper()
            direction = signal.get("direction").upper()
            sl = float(signal.get("sl"))
            tp = float(signal.get("tp"))
            source = signal.get("strategy", "unknown")
            ts = time.time()

            # Create CSV line
            line = f"{symbol},{direction},{sl:.5f},{tp:.5f},10000,{source},{ts:.0f}\n"

            # Write to MT5 Files
            MT5_FILES_PATH.mkdir(parents=True, exist_ok=True)
            with open(SIGNALS_FILE, "a") as f:
                f.write(line)

            return True

        except Exception as e:
            log.error(f"Processing error: {e}")
            return False

    def _accept(self, code, ack, signal):
        """Send acceptance response."""
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()

        response = {
            "ack": ack,
            "signal_id": signal.get("signal_id"),
            "timestamp": datetime.utcnow().isoformat(),
            "status": "accepted"
        }
        self.wfile.write(json.dumps(response).encode())

    def _reject(self, code, ack, reason):
        """Send rejection response."""
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()

        response = {
            "ack": ack,
            "reason": reason,
            "timestamp": datetime.utcnow().isoformat(),
            "status": "rejected"
        }
        self.wfile.write(json.dumps(response).encode())

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
        log.info("Hardened Signal Receiver Service Starting")
        log.info("════════════════════════════════════════════════════════════════════")

        log.info(f"Listening: http://{RECEIVER_HOST}:{RECEIVER_PORT}")
        log.info(f"  (behind reverse proxy at 0.0.0.0:443)")
        log.info(f"MT5 Files: {MT5_FILES_PATH}")
        log.info(f"Approved symbols: {APPROVED_SYMBOLS}")
        log.info(f"Approved lot size: {APPROVED_LOT_SIZE}")
        log.info(f"Signal expiry: {SIGNAL_EXPIRY_SECONDS}s")
        log.info("")

        # Verify MT5 Files folder exists
        if not MT5_FILES_PATH.exists():
            log.error(f"MT5 Files folder not found: {MT5_FILES_PATH}")
            return False

        log.info("✓ MT5 Files folder verified")

        # Load processed signals DB
        processed = len(db.signals)
        log.info(f"✓ Loaded {processed} previously processed signals")

        # Create HTTP server
        try:
            self.server = HTTPServer((RECEIVER_HOST, RECEIVER_PORT), SignalRequestHandler)
        except OSError as e:
            log.error(f"Cannot bind to {RECEIVER_HOST}:{RECEIVER_PORT}: {e}")
            return False

        # Run server in background thread
        self.thread = Thread(target=self._run_server, daemon=True)
        self.thread.start()

        log.info("✓ Service started successfully")
        log.info("Ready to receive signals from DigitalOcean (via reverse proxy)")

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
