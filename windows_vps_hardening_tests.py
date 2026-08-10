#!/usr/bin/env python3
"""
Hardening Test Suite for Windows VPS Signal Receiver
=====================================================

Tests validate all safety requirements before production deployment.

Usage:
  python3 windows_vps_hardening_tests.py
  python3 windows_vps_hardening_tests.py --verbose
  python3 windows_vps_hardening_tests.py --endpoint http://localhost:8888
"""

import json
import time
import uuid
from datetime import datetime, timedelta
from argparse import ArgumentParser
import requests

################################################################################
# TEST CONFIG
################################################################################

class TestConfig:
    def __init__(self, endpoint="http://localhost:8888", auth_token="test_token_123"):
        self.endpoint = endpoint.rstrip("/")
        self.auth_token = auth_token
        self.passed = 0
        self.failed = 0
        self.verbose = False

config = TestConfig()

################################################################################
# UTILITIES
################################################################################

def log(msg, level="INFO"):
    prefix = {"INFO": "ℹ", "PASS": "✓", "FAIL": "✗", "SKIP": "⊘"}[level]
    print(f"{prefix} {msg}")

def test_signal(name, payload, expected_ack):
    """Send signal and verify response."""
    try:
        headers = {
            "Authorization": f"Bearer {config.auth_token}",
            "Content-Type": "application/json"
        }

        response = requests.post(
            f"{config.endpoint}/signal",
            json=payload,
            headers=headers,
            timeout=5
        )

        ack_data = response.json()
        ack_code = ack_data.get("ack", "UNKNOWN")

        if ack_code == expected_ack:
            log(f"{name}: {ack_code} (expected)", "PASS")
            config.passed += 1
            return True
        else:
            log(f"{name}: got {ack_code}, expected {expected_ack}", "FAIL")
            config.failed += 1
            return False

    except Exception as e:
        log(f"{name}: {e}", "FAIL")
        config.failed += 1
        return False

################################################################################
# TEST CASES
################################################################################

def test_1_valid_signal():
    """Test 1: Valid signal is accepted."""
    signal = {
        "signal_id": str(uuid.uuid4()),
        "created_at_utc": datetime.utcnow().isoformat(),
        "expires_at_utc": (datetime.utcnow() + timedelta(hours=1)).isoformat(),
        "symbol": "EURUSD",
        "direction": "BUY",
        "sl": 1.08200,
        "tp": 1.09200,
        "lot_size": 0.01,
        "strategy": "test",
        "environment": "demo"
    }
    test_signal("TEST 1: Valid signal", signal, "ACCEPTED")

def test_2_duplicate_signal():
    """Test 2: Duplicate signal_id is rejected."""
    signal_id = str(uuid.uuid4())

    # Send first
    signal1 = {
        "signal_id": signal_id,
        "created_at_utc": datetime.utcnow().isoformat(),
        "expires_at_utc": (datetime.utcnow() + timedelta(hours=1)).isoformat(),
        "symbol": "GBPUSD",
        "direction": "SELL",
        "sl": 1.27500,
        "tp": 1.26500,
        "lot_size": 0.01,
        "strategy": "test",
        "environment": "demo"
    }
    test_signal("TEST 2a: First signal", signal1, "ACCEPTED")

    # Send duplicate
    time.sleep(1)
    signal2 = dict(signal1)
    test_signal("TEST 2b: Duplicate signal_id", signal2, "DUPLICATE")

def test_3_expired_signal():
    """Test 3: Expired signal is rejected."""
    signal = {
        "signal_id": str(uuid.uuid4()),
        "created_at_utc": (datetime.utcnow() - timedelta(hours=2)).isoformat(),
        "expires_at_utc": (datetime.utcnow() - timedelta(hours=1)).isoformat(),
        "symbol": "XAUUSD",
        "direction": "BUY",
        "sl": 1990,
        "tp": 2010,
        "lot_size": 0.01,
        "strategy": "test",
        "environment": "demo"
    }
    test_signal("TEST 3: Expired signal", signal, "EXPIRED")

def test_4_usdjpy_blocked():
    """Test 4: USDJPY is not approved."""
    signal = {
        "signal_id": str(uuid.uuid4()),
        "created_at_utc": datetime.utcnow().isoformat(),
        "expires_at_utc": (datetime.utcnow() + timedelta(hours=1)).isoformat(),
        "symbol": "USDJPY",
        "direction": "BUY",
        "sl": 147.00,
        "tp": 148.00,
        "lot_size": 0.01,
        "strategy": "test",
        "environment": "demo"
    }
    test_signal("TEST 4: USDJPY rejected", signal, "REJECTED_VALIDATION")

def test_5_india_symbol_blocked():
    """Test 5: India symbols are not approved."""
    signal = {
        "signal_id": str(uuid.uuid4()),
        "created_at_utc": datetime.utcnow().isoformat(),
        "expires_at_utc": (datetime.utcnow() + timedelta(hours=1)).isoformat(),
        "symbol": "NIFTY",
        "direction": "BUY",
        "sl": 20000,
        "tp": 21000,
        "lot_size": 0.01,
        "strategy": "test",
        "environment": "demo"
    }
    test_signal("TEST 5: India symbol rejected", signal, "REJECTED_VALIDATION")

def test_6_invalid_lot_size():
    """Test 6: Lot size > 0.01 is rejected."""
    signal = {
        "signal_id": str(uuid.uuid4()),
        "created_at_utc": datetime.utcnow().isoformat(),
        "expires_at_utc": (datetime.utcnow() + timedelta(hours=1)).isoformat(),
        "symbol": "EURUSD",
        "direction": "BUY",
        "sl": 1.08200,
        "tp": 1.09200,
        "lot_size": 0.05,  # Invalid: > 0.01
        "strategy": "test",
        "environment": "demo"
    }
    test_signal("TEST 6: Invalid lot size", signal, "REJECTED_VALIDATION")

def test_7_non_demo_environment():
    """Test 7: Non-demo environment is rejected."""
    signal = {
        "signal_id": str(uuid.uuid4()),
        "created_at_utc": datetime.utcnow().isoformat(),
        "expires_at_utc": (datetime.utcnow() + timedelta(hours=1)).isoformat(),
        "symbol": "GBPUSD",
        "direction": "BUY",
        "sl": 1.27000,
        "tp": 1.28000,
        "lot_size": 0.01,
        "strategy": "test",
        "environment": "live"  # Invalid: must be "demo"
    }
    test_signal("TEST 7: Non-demo environment", signal, "REJECTED_VALIDATION")

def test_8_missing_field():
    """Test 8: Missing required field is rejected."""
    signal = {
        "signal_id": str(uuid.uuid4()),
        "created_at_utc": datetime.utcnow().isoformat(),
        "expires_at_utc": (datetime.utcnow() + timedelta(hours=1)).isoformat(),
        "symbol": "EURUSD",
        # Missing: direction
        "sl": 1.08200,
        "tp": 1.09200,
        "lot_size": 0.01,
        "strategy": "test",
        "environment": "demo"
    }
    test_signal("TEST 8: Missing field", signal, "REJECTED_VALIDATION")

def test_9_invalid_json():
    """Test 9: Invalid JSON is rejected."""
    try:
        headers = {
            "Authorization": f"Bearer {config.auth_token}",
            "Content-Type": "application/json"
        }

        response = requests.post(
            f"{config.endpoint}/signal",
            data="not valid json",
            headers=headers,
            timeout=5
        )

        ack_data = response.json()
        ack_code = ack_data.get("ack", "UNKNOWN")

        if ack_code == "INVALID_JSON":
            log("TEST 9: Invalid JSON rejected", "PASS")
            config.passed += 1
        else:
            log(f"TEST 9: got {ack_code}, expected INVALID_JSON", "FAIL")
            config.failed += 1

    except Exception as e:
        log(f"TEST 9: {e}", "FAIL")
        config.failed += 1

def test_10_missing_auth():
    """Test 10: Missing authorization is rejected."""
    try:
        headers = {
            "Content-Type": "application/json"
            # Missing: Authorization
        }

        signal = {
            "signal_id": str(uuid.uuid4()),
            "created_at_utc": datetime.utcnow().isoformat(),
            "expires_at_utc": (datetime.utcnow() + timedelta(hours=1)).isoformat(),
            "symbol": "EURUSD",
            "direction": "BUY",
            "sl": 1.08200,
            "tp": 1.09200,
            "lot_size": 0.01,
            "strategy": "test",
            "environment": "demo"
        }

        response = requests.post(
            f"{config.endpoint}/signal",
            json=signal,
            headers=headers,
            timeout=5
        )

        ack_data = response.json()
        ack_code = ack_data.get("ack", "UNKNOWN")

        if ack_code == "NO_AUTH":
            log("TEST 10: Missing auth rejected", "PASS")
            config.passed += 1
        else:
            log(f"TEST 10: got {ack_code}, expected NO_AUTH", "FAIL")
            config.failed += 1

    except Exception as e:
        log(f"TEST 10: {e}", "FAIL")
        config.failed += 1

################################################################################
# MAIN
################################################################################

def main():
    parser = ArgumentParser()
    parser.add_argument("--endpoint", default="http://localhost:8888", help="Receiver endpoint")
    parser.add_argument("--token", default="test_token_123", help="Auth token")
    parser.add_argument("--verbose", action="store_true", help="Verbose output")
    args = parser.parse_args()

    config.endpoint = args.endpoint
    config.auth_token = args.token
    config.verbose = args.verbose

    print("════════════════════════════════════════════════════════════════════")
    print("Hardening Test Suite")
    print("════════════════════════════════════════════════════════════════════")
    print()
    print(f"Endpoint: {config.endpoint}")
    print(f"Auth token: {config.auth_token[:20]}...")
    print()

    # Run tests
    test_1_valid_signal()
    test_2_duplicate_signal()
    test_3_expired_signal()
    test_4_usdjpy_blocked()
    test_5_india_symbol_blocked()
    test_6_invalid_lot_size()
    test_7_non_demo_environment()
    test_8_missing_field()
    test_9_invalid_json()
    test_10_missing_auth()

    # Summary
    print()
    print("════════════════════════════════════════════════════════════════════")
    print(f"RESULTS: {config.passed} passed, {config.failed} failed")
    print("════════════════════════════════════════════════════════════════════")

    if config.failed == 0:
        print("✓ ALL TESTS PASSED")
        return 0
    else:
        print("✗ SOME TESTS FAILED")
        return 1

if __name__ == "__main__":
    exit(main())
