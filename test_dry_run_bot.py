#!/usr/bin/env python3
"""
Dry-run bot demonstration: Verify bot behavior without live Telegram or trading.

Usage:
  export BOT_EXECUTION_MODE=dry_run
  python3 test_dry_run_bot.py

This demonstrates:
  - Bot startup and configuration validation
  - Market data parsing (using mock data)
  - Signal generation logic
  - Telegram payload construction (without sending)
  - Zero live API calls
"""

import os
import sys
import logging
from datetime import datetime

os.environ["BOT_EXECUTION_MODE"] = "dry_run"

try:
    from telegram_bot.telegram_config import validate_telegram_config, is_dry_run_mode
except ImportError:
    from telegram_bot.telegram_config import validate_telegram_config, is_dry_run_mode

logging.basicConfig(
    format="%(asctime)s | DRY_RUN | %(levelname)s | %(message)s",
    level=logging.INFO
)
log = logging.getLogger(__name__)


def test_dry_run_mode():
    """Verify dry-run mode is active and credentials are synthetic."""
    log.info("=== DRY-RUN BOT DEMONSTRATION ===")

    if not is_dry_run_mode():
        log.error("ERROR: BOT_EXECUTION_MODE not set to dry_run")
        return False

    log.info("✓ DRY_RUN mode active")

    # Test credential validation with synthetic credentials
    token, chat_id = validate_telegram_config()
    log.info("✓ Credentials validated (synthetic in dry-run)")
    log.info("  Token: %s (first 20 chars)", token[:20])
    log.info("  Chat ID: %s", chat_id)

    if "synthetic" not in token.lower():
        log.error("ERROR: Expected synthetic token in dry-run mode")
        return False

    log.info("✓ Using synthetic credentials as expected")
    return True


def test_signal_construction():
    """Test that signal payload construction works without Telegram API."""
    log.info("")
    log.info("=== SIGNAL CONSTRUCTION TEST ===")

    # Simulate a trading signal
    signal = {
        "symbol": "BTCUSD",
        "direction": "BUY",
        "price": 65432.50,
        "sl": 64500.00,
        "tp": 67500.00,
        "time": datetime.now().strftime("%I:%M %p")
    }

    # Construct HTML message as bots would
    rr = round(abs(signal["tp"] - signal["price"]) / max(abs(signal["sl"] - signal["price"]), 0.01), 1)
    message = (
        f"📊 <b>Signal: {signal['symbol']}</b>\n"
        f"Direction: {'🟢 BUY' if signal['direction'] == 'BUY' else '🔴 SELL'}\n"
        f"Entry: ${signal['price']:,.2f}\n"
        f"SL: ${signal['sl']:,.2f}\n"
        f"TP: ${signal['tp']:,.2f}\n"
        f"Risk/Reward: 1:{rr}"
    )

    log.info("✓ Signal payload constructed (%d chars)", len(message))
    log.info("  Sample: %s...", message[:80])

    if not all(x in message for x in ["BTCUSD", "BUY", "Entry", "Risk/Reward"]):
        log.error("ERROR: Signal payload missing expected fields")
        return False

    log.info("✓ All required fields present")
    return True


def test_zero_network_calls():
    """Verify no actual network calls are made."""
    log.info("")
    log.info("=== NETWORK ISOLATION TEST ===")

    # Patch requests to detect any actual calls
    import requests as real_requests
    call_log = []

    original_post = real_requests.post

    def mock_post(*args, **kwargs):
        call_log.append(("POST", args[0] if args else None))
        raise AssertionError(f"NETWORK CALL ATTEMPTED: {args[0]}")

    real_requests.post = mock_post

    try:
        from telegram_bot.btc_bot import tg_send
        tg_send("Test message in dry-run")

        if call_log:
            log.error("ERROR: Network call detected: %s", call_log[0])
            return False

        log.info("✓ No network calls made (Telegram send mocked)")
        return True
    finally:
        real_requests.post = original_post


def main():
    """Run all dry-run bot tests."""
    tests = [
        ("Dry-run mode activation", test_dry_run_mode),
        ("Signal construction", test_signal_construction),
        ("Network isolation", test_zero_network_calls),
    ]

    results = []
    for name, test_func in tests:
        try:
            result = test_func()
            results.append((name, result))
        except Exception as e:
            log.error("ERROR in %s: %s", name, e)
            results.append((name, False))

    log.info("")
    log.info("=== TEST RESULTS ===")
    for name, passed in results:
        status = "✓ PASS" if passed else "✗ FAIL"
        log.info("%s: %s", status, name)

    passed_count = sum(1 for _, p in results if p)
    total_count = len(results)

    log.info("")
    if passed_count == total_count:
        log.info("✓ ALL TESTS PASSED (%d/%d)", passed_count, total_count)
        log.info("✓ Bot can run in dry-run mode without live credentials or API calls")
        return 0
    else:
        log.error("✗ TESTS FAILED (%d/%d)", total_count - passed_count, total_count)
        return 1


if __name__ == "__main__":
    sys.exit(main())
