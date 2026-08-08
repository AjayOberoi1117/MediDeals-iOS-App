#!/usr/bin/env python3
"""
Hardened Signal Sender for Windows VPS MT5
===========================================

Security features:
- Unique signal_id per signal (UUID)
- Signal expiry validation (created_at, expires_at)
- Demo-only environment tagging
- Detailed acknowledgement code handling
- Retry logic for transient failures
- Only mark delivered on ACCEPTED ack
- Comprehensive error logging

Usage:
  python3 signal_sender_windows_hardened.py

Environment variables:
  WINDOWS_VPS_URL - HTTPS URL (e.g., https://192.168.1.100)
  WINDOWS_VPS_AUTH_TOKEN - Bearer token
  POLL_INTERVAL - Seconds between checks (default: 5)
  SIGNAL_EXPIRY_SECONDS - Signal validity duration (default: 3600)
"""

import os
import sys
import json
import time
import uuid
import logging
import requests
from pathlib import Path
from datetime import datetime, timedelta
from dotenv import load_dotenv

load_dotenv()

################################################################################
# CONFIG
################################################################################

WINDOWS_VPS_URL = os.getenv("WINDOWS_VPS_URL", "").rstrip("/")
AUTH_TOKEN = os.getenv("WINDOWS_VPS_AUTH_TOKEN", "")
POLL_INTERVAL = int(os.getenv("POLL_INTERVAL", "5"))
SIGNAL_EXPIRY_SECONDS = int(os.getenv("SIGNAL_EXPIRY_SECONDS", "3600"))

QUEUE_FILE = Path(".trade_queue.jsonl")
DELIVERED_FILE = Path(".signals_delivered.jsonl")
LOG_FILE = Path("logs/signal_sender.log")

# Acknowledgement codes
ACK_CODES = {
    "ACCEPTED": "Signal accepted and queued",
    "DUPLICATE": "Signal already processed",
    "EXPIRED": "Signal beyond expiry time",
    "REJECTED_VALIDATION": "Signal validation failed",
    "REJECTED_SYMBOL": "Symbol not approved",
    "REJECTED_ACCOUNT": "Account not demo",
    "INVALID_AUTH": "Authentication failed",
    "NO_AUTH": "Missing authentication",
    "INVALID_JSON": "Malformed JSON",
    "READ_ERROR": "Cannot read request",
    "PROCESSING_ERROR": "Cannot write signal",
    "NOT_FOUND": "Endpoint not found"
}

TRANSIENT_CODES = {"PROCESSING_ERROR"}  # Retry on these
FATAL_CODES = {"DUPLICATE", "EXPIRED", "REJECTED_VALIDATION", "REJECTED_SYMBOL", "REJECTED_ACCOUNT"}

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

    if not WINDOWS_VPS_URL.startswith("https://"):
        log.warning("WINDOWS_VPS_URL should use HTTPS for security")

    log.info(f"Windows VPS URL: {WINDOWS_VPS_URL}")
    log.info(f"Auth token: configured (length={len(AUTH_TOKEN)})")
    log.info(f"Signal expiry: {SIGNAL_EXPIRY_SECONDS}s")

    return True

def load_delivered():
    """Load set of delivered signal IDs."""
    delivered = set()
    if DELIVERED_FILE.exists():
        try:
            with open(DELIVERED_FILE, "r") as f:
                for line in f:
                    try:
                        record = json.loads(line)
                        delivered.add(record["signal_id"])
                    except:
                        pass
        except Exception as e:
            log.warning(f"Could not load delivered signals: {e}")
    return delivered

def mark_delivered(signal_id):
    """Record that signal was successfully sent."""
    try:
        with open(DELIVERED_FILE, "a") as f:
            f.write(json.dumps({
                "signal_id": signal_id,
                "sent_at": datetime.utcnow().isoformat()
            }) + "\n")
    except Exception as e:
        log.warning(f"Could not record delivered signal: {e}")

################################################################################
# SIGNAL ENRICHMENT
################################################################################

def enrich_signal(raw_signal):
    """Add required fields to signal."""

    enriched = dict(raw_signal)

    # Add signal_id if missing
    if "signal_id" not in enriched:
        enriched["signal_id"] = str(uuid.uuid4())

    # Add timestamps if missing
    now = datetime.utcnow()
    if "created_at_utc" not in enriched:
        enriched["created_at_utc"] = now.isoformat()

    if "expires_at_utc" not in enriched:
        expires = now + timedelta(seconds=SIGNAL_EXPIRY_SECONDS)
        enriched["expires_at_utc"] = expires.isoformat()

    # Add environment tag
    if "environment" not in enriched:
        enriched["environment"] = "demo"

    # Add strategy if missing
    if "strategy" not in enriched:
        enriched["strategy"] = "unknown"

    # Ensure lot_size = 0.01 (demo validation phase)
    enriched["lot_size"] = 0.01

    return enriched

################################################################################
# SIGNAL SENDING
################################################################################

def send_signal(signal, max_retries=3):
    """Send signal to Windows VPS with retries."""

    signal_id = signal.get("signal_id")

    try:
        headers = {
            "Authorization": f"Bearer {AUTH_TOKEN}",
            "Content-Type": "application/json"
        }

        response = requests.post(
            f"{WINDOWS_VPS_URL}/signal",
            json=signal,
            headers=headers,
            timeout=10,
            verify=True
        )

        # Parse acknowledgement
        try:
            ack_data = response.json()
            ack_code = ack_data.get("ack", "UNKNOWN")
        except:
            ack_code = f"HTTP_{response.status_code}"

        # Handle response
        if response.status_code == 200 and ack_code == "ACCEPTED":
            log.info(f"✓ Sent: {signal['symbol']:6s} {signal['direction']:4s} "
                    f"sl={signal['sl']:.5g} tp={signal['tp']:.5g} "
                    f"id={signal_id[:8]}")
            return True, ack_code

        elif ack_code in FATAL_CODES:
            log.warning(f"✗ {ack_code}: {ACK_CODES.get(ack_code, 'Unknown')} "
                       f"({signal['symbol']} {signal['direction']})")
            return False, ack_code

        elif ack_code in TRANSIENT_CODES:
            log.warning(f"⟳ {ack_code}: Will retry "
                       f"({signal['symbol']} {signal['direction']})")
            return False, ack_code

        else:
            log.error(f"✗ {ack_code}: {ack_data.get('reason', 'Unknown error')}")
            return False, ack_code

    except requests.exceptions.ConnectionError:
        log.error(f"Cannot connect to Windows VPS: {WINDOWS_VPS_URL}")
        return False, "CONNECTION_FAILED"

    except requests.exceptions.Timeout:
        log.error("Request to Windows VPS timed out")
        return False, "TIMEOUT"

    except Exception as e:
        log.error(f"Send failed: {e}")
        return False, "EXCEPTION"

################################################################################
# QUEUE PROCESSING
################################################################################

def process_queue():
    """Poll queue, send signals to Windows VPS."""

    if not QUEUE_FILE.exists():
        return

    delivered = load_delivered()

    try:
        with open(QUEUE_FILE, "r+") as f:
            lines = f.readlines()
            f.seek(0)
            f.truncate()

        sent_count = 0
        skipped_count = 0
        failed_count = 0

        for line in lines:
            line = line.strip()
            if not line:
                continue

            try:
                raw_signal = json.loads(line)
                signal = enrich_signal(raw_signal)
                signal_id = signal.get("signal_id")

                # Check if already delivered
                if signal_id in delivered:
                    log.info(f"⟳ Already delivered: {signal_id[:8]}")
                    skipped_count += 1
                    continue

                # Send to Windows
                success, ack = send_signal(signal)

                if success:
                    mark_delivered(signal_id)
                    sent_count += 1
                elif ack in FATAL_CODES:
                    # Don't retry fatal errors
                    failed_count += 1
                else:
                    # Re-queue for retry
                    with open(QUEUE_FILE, "a") as qf:
                        qf.write(json.dumps(signal) + "\n")
                    failed_count += 1

            except json.JSONDecodeError:
                log.warning(f"Invalid JSON in queue: {line}")
                failed_count += 1

        if sent_count > 0 or skipped_count > 0 or failed_count > 0:
            log.info(f"Queue: {sent_count} sent, {skipped_count} skipped, {failed_count} failed")

    except Exception as e:
        log.error(f"Queue processing error: {e}")

################################################################################
# MAIN LOOP
################################################################################

def main():
    """Main signal sender loop."""

    log.info("════════════════════════════════════════════════════════════════════")
    log.info("Hardened Signal Sender for Windows VPS MT5")
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
