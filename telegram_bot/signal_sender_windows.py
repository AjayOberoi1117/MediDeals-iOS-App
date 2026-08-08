#!/usr/bin/env python3
"""
Signal Sender for Windows VPS MT5
==================================

Reads signals from .trade_queue.jsonl and forwards to Windows VPS.
Windows VPS runs signal receiver service that writes to MT5.

Usage:
  python3 signal_sender_windows.py

Environment variables:
  WINDOWS_VPS_URL - URL of Windows VPS signal receiver (e.g., http://192.168.1.100:8888)
  WINDOWS_VPS_AUTH_TOKEN - Authentication token (shared secret)
  POLL_INTERVAL - Seconds between queue checks (default: 5)
"""

import os
import sys
import json
import time
import logging
import requests
from pathlib import Path
from datetime import datetime
from dotenv import load_dotenv

load_dotenv()

################################################################################
# CONFIG
################################################################################

WINDOWS_VPS_URL = os.getenv("WINDOWS_VPS_URL", "").rstrip("/")
AUTH_TOKEN = os.getenv("WINDOWS_VPS_AUTH_TOKEN", "")
POLL_INTERVAL = int(os.getenv("POLL_INTERVAL", "5"))

QUEUE_FILE = Path(".trade_queue.jsonl")
HISTORY_FILE = Path(".signal_send_history.jsonl")
LOG_FILE = Path("logs/signal_sender.log")

################################################################################
# LOGGING
################################################################################

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | SENDER   | %(levelname)s | %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
log = logging.getLogger(__name__)

################################################################################
# VALIDATION
################################################################################

def validate_config():
    """Ensure Windows VPS configuration is set."""
    if not WINDOWS_VPS_URL:
        log.error("WINDOWS_VPS_URL not set in .env")
        return False

    if not AUTH_TOKEN:
        log.error("WINDOWS_VPS_AUTH_TOKEN not set in .env")
        return False

    if not WINDOWS_VPS_URL.startswith("http"):
        log.error("WINDOWS_VPS_URL must start with http:// or https://")
        return False

    log.info(f"Windows VPS URL: {WINDOWS_VPS_URL}")
    log.info(f"Auth token configured (length={len(AUTH_TOKEN)})")

    return True

################################################################################
# SIGNAL SENDING
################################################################################

def send_signal(signal):
    """Send one signal to Windows VPS."""
    try:
        headers = {
            "Authorization": f"Bearer {AUTH_TOKEN}",
            "Content-Type": "application/json"
        }

        response = requests.post(
            f"{WINDOWS_VPS_URL}/signal",
            json=signal,
            headers=headers,
            timeout=10
        )

        if response.status_code == 200:
            log.info(f"✓ Sent: {signal['symbol']:6s} {signal['direction']:4s} "
                    f"sl={signal['sl']:.5g} tp={signal['tp']:.5g}")
            _record_history(signal, "sent")
            return True

        elif response.status_code == 400:
            log.warning(f"Windows rejected (invalid): {signal['symbol']} {signal['direction']}")
            _record_history(signal, "rejected_invalid")
            return False

        elif response.status_code == 401:
            log.error(f"Windows rejected (auth): Invalid or missing auth token")
            _record_history(signal, "rejected_auth")
            return False

        else:
            log.error(f"Windows error {response.status_code}: {response.text}")
            _record_history(signal, f"error_{response.status_code}")
            return False

    except requests.exceptions.ConnectionError:
        log.error(f"Cannot connect to Windows VPS: {WINDOWS_VPS_URL}")
        log.error("  Verify Windows service is running and network is reachable")
        _record_history(signal, "connection_failed")
        return False

    except requests.exceptions.Timeout:
        log.error(f"Request to Windows VPS timed out")
        _record_history(signal, "timeout")
        return False

    except Exception as e:
        log.error(f"Send failed: {e}")
        _record_history(signal, f"error_{type(e).__name__}")
        return False

def _record_history(signal, result):
    """Record signal send attempt to history."""
    try:
        record = dict(signal)
        record["result"] = result
        record["sent_at"] = datetime.now().isoformat()

        with open(HISTORY_FILE, "a") as f:
            f.write(json.dumps(record) + "\n")
    except Exception as e:
        log.warning(f"Could not record history: {e}")

################################################################################
# QUEUE PROCESSING
################################################################################

def process_queue():
    """Poll queue, send signals to Windows VPS."""

    if not QUEUE_FILE.exists():
        return

    try:
        with open(QUEUE_FILE, "r+") as f:
            lines = f.readlines()
            f.seek(0)
            f.truncate()

        sent_count = 0
        rejected_count = 0

        for line in lines:
            line = line.strip()
            if not line:
                continue

            try:
                signal = json.loads(line)

                # Basic validation
                if not all(k in signal for k in ["symbol", "direction", "sl", "tp"]):
                    log.warning(f"Incomplete signal: {line}")
                    rejected_count += 1
                    continue

                # Send to Windows
                if send_signal(signal):
                    sent_count += 1
                else:
                    rejected_count += 1

            except json.JSONDecodeError:
                log.warning(f"Invalid JSON in queue: {line}")
                rejected_count += 1

        if sent_count > 0 or rejected_count > 0:
            log.info(f"Queue processed: {sent_count} sent, {rejected_count} rejected")

    except Exception as e:
        log.error(f"Queue processing error: {e}")

################################################################################
# MAIN LOOP
################################################################################

def main():
    """Main signal sender loop."""

    log.info("════════════════════════════════════════════════════════════════════")
    log.info("Signal Sender for Windows VPS MT5")
    log.info("════════════════════════════════════════════════════════════════════")

    if not validate_config():
        log.error("Configuration validation failed")
        sys.exit(1)

    log.info(f"Starting signal sender loop (poll every {POLL_INTERVAL}s)")
    log.info("")

    try:
        while True:
            time.sleep(POLL_INTERVAL)
            process_queue()

    except KeyboardInterrupt:
        log.info("Signal sender stopped by user")
    except Exception as e:
        log.error(f"Fatal error: {e}", exc_info=True)
        sys.exit(1)

if __name__ == "__main__":
    main()
