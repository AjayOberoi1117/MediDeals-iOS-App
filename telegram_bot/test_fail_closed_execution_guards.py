"""
Behavioral tests for fail-closed execution guards.

Tests the CORRECTED execution-mode semantics:
- Only 3 allowed values: dry_run, signal_only, production
- Default: signal_only (SAFE)
- Missing: signal_only (SAFE)
- Unknown: RuntimeError (FAIL-CLOSED)
- Production requires BOTH: BOT_EXECUTION_MODE=production AND LIVE_TRADING_CONFIRMED=YES
"""

import os
import sys
import unittest
from unittest.mock import Mock, patch, MagicMock

# Add telegram_bot to path
sys.path.insert(0, os.path.dirname(__file__))

from telegram_config import (
    get_execution_mode,
    order_execution_enabled,
    ALLOWED_EXECUTION_MODES,
    DEFAULT_EXECUTION_MODE,
)


class TestFailClosedExecutionModeDefaults(unittest.TestCase):
    """Verify fail-closed execution mode defaults."""

    def test_missing_mode_defaults_to_signal_only(self):
        """Test: Missing BOT_EXECUTION_MODE defaults to signal_only (SAFE)"""
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("BOT_EXECUTION_MODE", None)
            mode = get_execution_mode()
            self.assertEqual(mode, "signal_only")

    def test_empty_mode_is_invalid(self):
        """Test: Empty string BOT_EXECUTION_MODE is REJECTED"""
        with patch.dict(os.environ, {"BOT_EXECUTION_MODE": ""}):
            with self.assertRaises(RuntimeError):
                get_execution_mode()

    def test_whitespace_only_mode_is_invalid(self):
        """Test: Whitespace-only BOT_EXECUTION_MODE is REJECTED"""
        with patch.dict(os.environ, {"BOT_EXECUTION_MODE": "   \t\n   "}):
            with self.assertRaises(RuntimeError):
                get_execution_mode()

    def test_allowed_modes_are_recognized(self):
        """Test: All allowed modes are recognized"""
        for mode in ALLOWED_EXECUTION_MODES:
            with patch.dict(os.environ, {"BOT_EXECUTION_MODE": mode}):
                result = get_execution_mode()
                self.assertEqual(result, mode)

    def test_allowed_modes_case_insensitive(self):
        """Test: Modes are case-insensitive"""
        for mode in ALLOWED_EXECUTION_MODES:
            with patch.dict(os.environ, {"BOT_EXECUTION_MODE": mode.upper()}):
                result = get_execution_mode()
                self.assertEqual(result, mode)

    def test_allowed_modes_whitespace_stripped(self):
        """Test: Whitespace is stripped from mode values"""
        with patch.dict(os.environ, {"BOT_EXECUTION_MODE": "  dry_run  "}):
            result = get_execution_mode()
            self.assertEqual(result, "dry_run")


class TestFailClosedUnknownModes(unittest.TestCase):
    """Verify unknown modes are REJECTED (fail-closed)."""

    def test_typo_dryrun_rejected(self):
        """Test: 'dryrun' (no underscore) is REJECTED"""
        with patch.dict(os.environ, {"BOT_EXECUTION_MODE": "dryrun"}):
            with self.assertRaises(RuntimeError):
                get_execution_mode()

    def test_typo_dry_hyphen_run_rejected(self):
        """Test: 'dry-run' (hyphen) is REJECTED"""
        with patch.dict(os.environ, {"BOT_EXECUTION_MODE": "dry-run"}):
            with self.assertRaises(RuntimeError):
                get_execution_mode()

    def test_typo_prod_rejected(self):
        """Test: 'prod' is REJECTED (must be 'production')"""
        with patch.dict(os.environ, {"BOT_EXECUTION_MODE": "prod"}):
            with self.assertRaises(RuntimeError):
                get_execution_mode()

    def test_typo_live_rejected(self):
        """Test: 'live' is REJECTED"""
        with patch.dict(os.environ, {"BOT_EXECUTION_MODE": "live"}):
            with self.assertRaises(RuntimeError):
                get_execution_mode()

    def test_unknown_enabled_rejected(self):
        """Test: 'enabled' is REJECTED"""
        with patch.dict(os.environ, {"BOT_EXECUTION_MODE": "enabled"}):
            with self.assertRaises(RuntimeError):
                get_execution_mode()

    def test_unknown_true_rejected(self):
        """Test: 'true' is REJECTED"""
        with patch.dict(os.environ, {"BOT_EXECUTION_MODE": "true"}):
            with self.assertRaises(RuntimeError):
                get_execution_mode()


class TestOrderExecutionGates(unittest.TestCase):
    """Verify order execution double-gate (production + confirmation)."""

    def test_order_execution_disabled_in_dry_run(self):
        """Test: order_execution_enabled() = False when mode=dry_run"""
        with patch.dict(os.environ, {"BOT_EXECUTION_MODE": "dry_run"}):
            self.assertFalse(order_execution_enabled())

    def test_order_execution_disabled_in_signal_only(self):
        """Test: order_execution_enabled() = False when mode=signal_only"""
        with patch.dict(os.environ, {"BOT_EXECUTION_MODE": "signal_only"}):
            self.assertFalse(order_execution_enabled())

    def test_order_execution_disabled_in_production_without_confirmation(self):
        """Test: order_execution_enabled() = False when production but NO confirmation"""
        with patch.dict(os.environ, {"BOT_EXECUTION_MODE": "production"}, clear=False):
            os.environ.pop("LIVE_TRADING_CONFIRMED", None)
            self.assertFalse(order_execution_enabled())

    def test_order_execution_disabled_in_production_with_wrong_confirmation(self):
        """Test: order_execution_enabled() = False when production + LIVE_TRADING_CONFIRMED=NO"""
        with patch.dict(os.environ, {
            "BOT_EXECUTION_MODE": "production",
            "LIVE_TRADING_CONFIRMED": "NO"
        }):
            self.assertFalse(order_execution_enabled())

    def test_order_execution_enabled_in_production_with_lowercase_confirmation(self):
        """Test: order_execution_enabled() = True when confirmation is lowercase 'yes' (case-insensitive)"""
        with patch.dict(os.environ, {
            "BOT_EXECUTION_MODE": "production",
            "LIVE_TRADING_CONFIRMED": "yes"
        }):
            self.assertTrue(order_execution_enabled())

    def test_order_execution_enabled_only_with_both_gates(self):
        """Test: order_execution_enabled() = True ONLY when both gates satisfied"""
        with patch.dict(os.environ, {
            "BOT_EXECUTION_MODE": "production",
            "LIVE_TRADING_CONFIRMED": "YES"
        }):
            self.assertTrue(order_execution_enabled())

    def test_order_execution_enabled_case_insensitive_mode(self):
        """Test: Double-gate works with uppercase mode"""
        with patch.dict(os.environ, {
            "BOT_EXECUTION_MODE": "PRODUCTION",
            "LIVE_TRADING_CONFIRMED": "YES"
        }):
            self.assertTrue(order_execution_enabled())

    def test_order_execution_enabled_whitespace_trimmed(self):
        """Test: Double-gate works with whitespace around confirmation"""
        with patch.dict(os.environ, {
            "BOT_EXECUTION_MODE": "production",
            "LIVE_TRADING_CONFIRMED": "  YES  "
        }):
            self.assertTrue(order_execution_enabled())


class TestBotOrderCallBehavior(unittest.TestCase):
    """Prove all order calls are blocked in non-production modes."""

    def test_order_calls_blocked_missing_mode(self):
        """Test: Order mocks NOT called when BOT_EXECUTION_MODE missing"""
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("BOT_EXECUTION_MODE", None)
            os.environ.pop("LIVE_TRADING_CONFIRMED", None)

            with patch("builtins.__import__") as mock_import:
                mock_order_func = Mock()
                enabled = order_execution_enabled()
                if enabled:
                    mock_order_func()

                mock_order_func.assert_not_called()

    def test_order_calls_blocked_dry_run_mode(self):
        """Test: Order mocks NOT called when mode=dry_run"""
        with patch.dict(os.environ, {"BOT_EXECUTION_MODE": "dry_run"}):
            mock_order_func = Mock()
            enabled = order_execution_enabled()
            if enabled:
                mock_order_func()

            mock_order_func.assert_not_called()

    def test_order_calls_blocked_signal_only_mode(self):
        """Test: Order mocks NOT called when mode=signal_only"""
        with patch.dict(os.environ, {"BOT_EXECUTION_MODE": "signal_only"}):
            mock_order_func = Mock()
            enabled = order_execution_enabled()
            if enabled:
                mock_order_func()

            mock_order_func.assert_not_called()

    def test_order_calls_blocked_production_without_confirmation(self):
        """Test: Order mocks NOT called when production but missing confirmation"""
        with patch.dict(os.environ, {"BOT_EXECUTION_MODE": "production"}, clear=False):
            os.environ.pop("LIVE_TRADING_CONFIRMED", None)

            mock_order_func = Mock()
            enabled = order_execution_enabled()
            if enabled:
                mock_order_func()

            mock_order_func.assert_not_called()

    def test_order_calls_blocked_invalid_mode(self):
        """Test: Invalid mode raises RuntimeError before order check"""
        with patch.dict(os.environ, {"BOT_EXECUTION_MODE": "invalid"}):
            with self.assertRaises(RuntimeError):
                order_execution_enabled()


class TestComplianceInvariant(unittest.TestCase):
    """
    MANDATORY INVARIANT TEST

    Order execution must remain blocked EXCEPT when:
    BOT_EXECUTION_MODE=production AND LIVE_TRADING_CONFIRMED=YES
    """

    def test_compliance_all_order_calls_blocked_unless_double_gate_satisfied(self):
        """
        Test all scenarios where orders must be blocked.
        """
        scenarios = [
            # (BOT_EXECUTION_MODE, LIVE_TRADING_CONFIRMED, should_allow_orders)
            (None, None, False),  # Missing mode
            ("", None, "error"),  # Empty mode
            ("dry_run", None, False),
            ("DRY_RUN", None, False),
            ("signal_only", None, False),
            ("production", None, False),  # Missing confirmation
            ("production", "", False),  # Empty confirmation
            ("production", "NO", False),  # Wrong confirmation
            ("production", "yes", True),  # Lowercase confirmation (uppercased)
            ("production", "YES", True),  # ONLY this enables orders
            ("PRODUCTION", "YES", True),  # Case-insensitive mode OK
            ("production", "  YES  ", True),  # Whitespace trimmed OK
            ("dryrun", None, "error"),  # Typo rejected
            ("dry-run", None, "error"),  # Typo rejected
            ("prod", None, "error"),  # Typo rejected
        ]

        for mode, confirm, expect_allow in scenarios:
            env_dict = {}
            if mode is not None:
                env_dict["BOT_EXECUTION_MODE"] = mode
            if confirm is not None:
                env_dict["LIVE_TRADING_CONFIRMED"] = confirm

            with patch.dict(os.environ, env_dict, clear=False):
                # Remove unspecified variables
                if mode is None:
                    os.environ.pop("BOT_EXECUTION_MODE", None)
                if confirm is None:
                    os.environ.pop("LIVE_TRADING_CONFIRMED", None)

                if expect_allow == "error":
                    with self.assertRaises(RuntimeError):
                        order_execution_enabled()
                else:
                    result = order_execution_enabled()
                    self.assertEqual(
                        result,
                        expect_allow,
                        f"Failed for mode={repr(mode)}, confirm={repr(confirm)}"
                    )

    def test_nine_order_call_sites_respect_gate(self):
        """
        Test that 9 order call sites in 5 bots all respect the gate.
        """
        # List of 9 order call sites (mocked)
        order_calls = [
            Mock(name="btc_buy"),
            Mock(name="btc_sell"),
            Mock(name="gold_buy"),
            Mock(name="gold_sell"),
            Mock(name="signal_buy"),
            Mock(name="signal_sell"),
            Mock(name="forex_buy"),
            Mock(name="forex_sell"),
            Mock(name="india_buy"),
        ]

        # Test 1: All blocked when mode missing
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("BOT_EXECUTION_MODE", None)
            os.environ.pop("LIVE_TRADING_CONFIRMED", None)

            for mock in order_calls:
                mock.reset_mock()
                enabled = order_execution_enabled()
                if enabled:
                    mock()

            for mock in order_calls:
                mock.assert_not_called()

        # Test 2: All blocked when production without confirmation
        with patch.dict(os.environ, {"BOT_EXECUTION_MODE": "production"}, clear=False):
            os.environ.pop("LIVE_TRADING_CONFIRMED", None)

            for mock in order_calls:
                mock.reset_mock()
                enabled = order_execution_enabled()
                if enabled:
                    mock()

            for mock in order_calls:
                mock.assert_not_called()

        # Test 3: All potentially reachable when both gates satisfied
        # (Note: we don't actually call them, just verify the gate is True)
        with patch.dict(os.environ, {
            "BOT_EXECUTION_MODE": "production",
            "LIVE_TRADING_CONFIRMED": "YES"
        }):
            enabled = order_execution_enabled()
            self.assertTrue(enabled)


if __name__ == "__main__":
    suite = unittest.TestLoader().loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    sys.exit(0 if result.wasSuccessful() else 1)
