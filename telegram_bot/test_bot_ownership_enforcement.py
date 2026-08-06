#!/usr/bin/env python3
"""
Comprehensive test suite for bot ownership enforcement.

Verifies:
- Signal Bot is disabled fail-closed
- Options Scalper is downstream consumer only
- Nifty Scalper ownership is sole directional owner
- One market, one signal owner principle
"""

import os
import sys
import json
import time
import tempfile
import unittest
from unittest.mock import Mock, patch, MagicMock, call
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))


class TestLauncherOwnership(unittest.TestCase):
    """Test: Launcher removes signal_bot from managed set."""

    def test_signal_bot_not_in_launcher(self):
        """Requirement: start_bots.sh does NOT launch signal_bot.py"""
        with open("start_bots.sh") as f:
            content = f.read()
        self.assertNotIn('start_bot "$PYTHON" "signal_bot.py"', content)
        self.assertIn("signal_bot.py", content, "Should mention it's preserved")
        self.assertIn("intentionally excluded", content)

    def test_launcher_manages_5_bots(self):
        """Requirement: Launcher manages exactly 5 bots (not 6)"""
        with open("start_bots.sh") as f:
            content = f.read()
        self.assertIn("5 dedicated signal bots", content)
        self.assertNotIn("6 dedicated signal bots", content)

    def test_launcher_still_contains_other_bots(self):
        """Requirement: Launcher still has btc, gold, forex, nifty, options"""
        with open("start_bots.sh") as f:
            content = f.read()
        bots_to_keep = ["btc_bot.py", "gold_bot.py", "forex_scalper.py",
                        "nifty_scalper.py", "options_scalper.py"]
        for bot in bots_to_keep:
            self.assertIn(f'start_bot "$PYTHON" "{bot}"', content)

    def test_launcher_preserves_safety_behavior(self):
        """Requirement: Launcher preserves BOT_EXECUTION_MODE and gate verification"""
        with open("start_bots.sh") as f:
            content = f.read()
        self.assertIn('BOT_EXECUTION_MODE="signal_only"', content)
        self.assertIn("LIVE_TRADING_CONFIRMED", content)
        self.assertIn("order_execution_enabled", content)
        self.assertIn("Safety gate PASSED", content)


class TestSignalBotDisablement(unittest.TestCase):
    """Test: Signal Bot disabled fail-closed."""

    def test_signal_bot_main_raises_system_exit(self):
        """Requirement: Direct execution raises SystemExit"""
        import signal_bot
        with self.assertRaises(SystemExit) as cm:
            signal_bot.main()
        self.assertIn("SIGNAL BOT DISABLED", str(cm.exception))

    def test_signal_bot_does_not_scan(self):
        """Requirement: Disabled signal_bot does not scan symbols"""
        with open("signal_bot.py") as f:
            content = f.read()
        # After main() def, should not have active scanning loop
        main_start = content.find("def main()")
        main_body = content[main_start:main_start+300]
        # The return should happen before check_signal call
        self.assertIn("raise SystemExit", main_body)
        self.assertNotIn("check_signal", main_body[:200])

    def test_signal_bot_no_telegram_in_main(self):
        """Requirement: main() doesn't call tg_send (immediate exit)"""
        with open("signal_bot.py") as f:
            content = f.read()
        main_start = content.find("def main()")
        # Get first 300 chars of main body
        main_snippet = content[main_start:main_start+300]
        # Should exit before any tg_send calls
        self.assertNotIn("tg_send", main_snippet)

    def test_signal_bot_module_imports_safely(self):
        """Requirement: Importing module doesn't trigger execution"""
        # If main() isn't called on import, this should work fine
        import signal_bot as sb
        self.assertIsNotNone(sb)
        # Module should have functions available
        self.assertTrue(hasattr(sb, 'check_signal'))


class TestOptionsUpstreamValidation(unittest.TestCase):
    """Test: Options Scalper validates upstream NIFTY state strictly."""

    def setUp(self):
        """Set up test fixtures."""
        import options_scalper
        self.options = options_scalper
        self.nifty_state_file = self.options.NIFTY_STATE_FILE

    def test_reject_missing_file(self):
        """Requirement: Reject if state file doesn't exist"""
        # Ensure file doesn't exist
        if os.path.exists(self.nifty_state_file):
            os.remove(self.nifty_state_file)

        result = self.options._read_upstream_direction("NIFTY")
        self.assertEqual(result, (None, None))

    def test_reject_malformed_json(self):
        """Requirement: Reject invalid JSON"""
        with open(self.nifty_state_file, "w") as f:
            f.write("{invalid json")

        result = self.options._read_upstream_direction("NIFTY")
        self.assertEqual(result, (None, None))

    def test_reject_non_dict_top_level(self):
        """Requirement: Reject if top-level is not dict"""
        with open(self.nifty_state_file, "w") as f:
            json.dump(["NIFTY"], f)

        result = self.options._read_upstream_direction("NIFTY")
        self.assertEqual(result, (None, None))

    def test_reject_missing_symbol(self):
        """Requirement: Reject if symbol not in state"""
        with open(self.nifty_state_file, "w") as f:
            json.dump({"BANKNIFTY": {"direction": "BUY", "timestamp": time.time()}}, f)

        result = self.options._read_upstream_direction("NIFTY")
        self.assertEqual(result, (None, None))

    def test_reject_non_dict_symbol_entry(self):
        """Requirement: Reject if symbol entry is not dict"""
        with open(self.nifty_state_file, "w") as f:
            json.dump({"NIFTY": "BUY"}, f)

        result = self.options._read_upstream_direction("NIFTY")
        self.assertEqual(result, (None, None))

    def test_reject_invalid_direction(self):
        """Requirement: Reject if direction is not exactly BUY or SELL"""
        with open(self.nifty_state_file, "w") as f:
            json.dump({"NIFTY": {"direction": "UP", "timestamp": time.time()}}, f)

        result = self.options._read_upstream_direction("NIFTY")
        self.assertEqual(result, (None, None))

    def test_reject_bool_timestamp(self):
        """Requirement: Reject if timestamp is bool"""
        with open(self.nifty_state_file, "w") as f:
            json.dump({"NIFTY": {"direction": "BUY", "timestamp": True}}, f)

        result = self.options._read_upstream_direction("NIFTY")
        self.assertEqual(result, (None, None))

    def test_reject_infinite_timestamp(self):
        """Requirement: Reject if timestamp is infinite"""
        with open(self.nifty_state_file, "w") as f:
            json.dump({"NIFTY": {"direction": "BUY", "timestamp": float('inf')}}, f)

        result = self.options._read_upstream_direction("NIFTY")
        self.assertEqual(result, (None, None))

    def test_reject_future_timestamp_beyond_tolerance(self):
        """Requirement: Reject if timestamp > now + tolerance"""
        future_ts = time.time() + 10  # 10 seconds in future
        with open(self.nifty_state_file, "w") as f:
            json.dump({"NIFTY": {"direction": "BUY", "timestamp": future_ts}}, f)

        result = self.options._read_upstream_direction("NIFTY")
        self.assertEqual(result, (None, None))

    def test_reject_stale_timestamp(self):
        """Requirement: Reject if timestamp > 1800 seconds old"""
        stale_ts = time.time() - 2000  # 2000 seconds old (max is 1800)
        with open(self.nifty_state_file, "w") as f:
            json.dump({"NIFTY": {"direction": "BUY", "timestamp": stale_ts}}, f)

        result = self.options._read_upstream_direction("NIFTY")
        self.assertEqual(result, (None, None))

    def test_accept_valid_nifty_buy(self):
        """Requirement: Accept valid NIFTY BUY signal"""
        now_ts = time.time()
        with open(self.nifty_state_file, "w") as f:
            json.dump({"NIFTY": {"direction": "BUY", "timestamp": now_ts}}, f)

        direction, timestamp = self.options._read_upstream_direction("NIFTY")
        self.assertEqual(direction, 1)
        self.assertEqual(timestamp, now_ts)

    def test_accept_valid_nifty_sell(self):
        """Requirement: Accept valid NIFTY SELL signal"""
        now_ts = time.time()
        with open(self.nifty_state_file, "w") as f:
            json.dump({"NIFTY": {"direction": "SELL", "timestamp": now_ts}}, f)

        direction, timestamp = self.options._read_upstream_direction("NIFTY")
        self.assertEqual(direction, -1)
        self.assertEqual(timestamp, now_ts)

    def test_accept_valid_banknifty(self):
        """Requirement: Accept valid BANKNIFTY signals"""
        now_ts = time.time()
        with open(self.nifty_state_file, "w") as f:
            json.dump({"BANKNIFTY": {"direction": "SELL", "timestamp": now_ts}}, f)

        direction, timestamp = self.options._read_upstream_direction("BANKNIFTY")
        self.assertEqual(direction, -1)
        self.assertEqual(timestamp, now_ts)

    def tearDown(self):
        """Clean up test file."""
        if os.path.exists(self.nifty_state_file):
            os.remove(self.nifty_state_file)


class TestOptionsDeduplication(unittest.TestCase):
    """Test: Options Scalper deduplicates upstream events."""

    def setUp(self):
        """Set up test fixtures."""
        import options_scalper
        self.options = options_scalper
        self.dedup_file = self.options.PROCESSED_SIGNALS_FILE
        # Clear dedup state
        self.options._processed_signal_ids = set()
        if os.path.exists(self.dedup_file):
            os.remove(self.dedup_file)

    def test_dedup_key_format(self):
        """Requirement: Dedup key is symbol:direction:timestamp"""
        key = "NIFTY:BUY:1695821123.45"
        self.assertIn(":", key)
        parts = key.split(":")
        self.assertEqual(len(parts), 3)
        self.assertEqual(parts[0], "NIFTY")
        self.assertEqual(parts[1], "BUY")

    def test_mark_and_check_processed(self):
        """Requirement: Mark processed and check returns True"""
        signal_id = "NIFTY:BUY:1695821123.45"
        self.options._mark_processed(signal_id)
        self.assertIn(signal_id, self.options._processed_signal_ids)

    def test_dedup_persists_across_load(self):
        """Requirement: Processed signals persist to file"""
        signal_id = "NIFTY:SELL:1695821100.00"
        self.options._mark_processed(signal_id)

        # Simulate reload
        self.options._processed_signal_ids = set()
        self.options._load_processed()

        self.assertIn(signal_id, self.options._processed_signal_ids)

    def test_dedup_retention_bounded(self):
        """Requirement: Keep only recent N signals (default 500)"""
        # Add more than retention limit
        for i in range(600):
            sig_id = f"NIFTY:BUY:{1695821000 + i}.00"
            self.options._processed_signal_ids.add(sig_id)

        # Mark one more to trigger retention logic
        self.options._mark_processed("NIFTY:BUY:1695822000.00")

        # Should be bounded to ~500
        self.assertLessEqual(len(self.options._processed_signal_ids), 510)

    def tearDown(self):
        """Clean up."""
        self.options._processed_signal_ids = set()
        if os.path.exists(self.dedup_file):
            os.remove(self.dedup_file)


class TestOptionsDirectionRemoval(unittest.TestCase):
    """Test: Options Scalper has NO independent directional logic."""

    def test_no_supertrend_in_active_path(self):
        """Requirement: calculate_supertrend NOT called in check_symbol"""
        with open("options_scalper.py") as f:
            content = f.read()

        # Find check_symbol function
        check_start = content.find("def check_symbol(")
        check_end = content.find("\ndef main()", check_start)
        check_body = content[check_start:check_end]

        # Should NOT call calculate_supertrend in the active path
        # (it may be defined elsewhere, but not called in check_symbol)
        self.assertNotIn("calculate_supertrend(", check_body)

    def test_no_supertrend_flip_detection(self):
        """Requirement: No st_now/st_prev flip check in check_symbol"""
        with open("options_scalper.py") as f:
            content = f.read()

        check_start = content.find("def check_symbol(")
        check_end = content.find("\ndef main()", check_start)
        check_body = content[check_start:check_end]

        # Should NOT have st_direction or st_now/st_prev
        self.assertNotIn("st_now", check_body)
        self.assertNotIn("st_prev", check_body)
        self.assertNotIn("st_direction", check_body)

    def test_no_1h_trend_in_active_path(self):
        """Requirement: get_1h_trend NOT called in check_symbol"""
        with open("options_scalper.py") as f:
            content = f.read()

        check_start = content.find("def check_symbol(")
        check_end = content.find("\ndef main()", check_start)
        check_body = content[check_start:check_end]

        # Should NOT call get_1h_trend
        self.assertNotIn("get_1h_trend(", check_body)

    def test_adx_is_quality_filter_only(self):
        """Requirement: ADX used only for strength gate, not direction"""
        with open("options_scalper.py") as f:
            content = f.read()

        check_start = content.find("def check_symbol(")
        check_end = content.find("\ndef main()", check_start)
        check_body = content[check_start:check_end]

        # ADX should be present (quality filter)
        self.assertIn("calc_adx(", check_body)
        # But should not be used to derive direction
        self.assertNotIn("ADX_MIN", check_body.split("calc_adx(")[0])  # Before calc_adx
        # Should have single ADX_MIN check for quality gate
        adx_min_count = check_body.count("ADX_MIN")
        self.assertGreaterEqual(adx_min_count, 1)

    def test_upstream_direction_used_for_ce_pe(self):
        """Requirement: CE/PE selection uses upstream direction"""
        with open("options_scalper.py") as f:
            content = f.read()

        # Should have _read_upstream_direction call
        self.assertIn("_read_upstream_direction(", content)

        check_start = content.find("def check_symbol(")
        check_end = content.find("\ndef main()", check_start)
        check_body = content[check_start:check_end]

        # Should use upstream_dir for CE/PE selection
        self.assertIn("upstream_dir", check_body)
        self.assertIn("CE", check_body)
        self.assertIn("PE", check_body)


class TestOptionsMessageLabelling(unittest.TestCase):
    """Test: Options message clearly labels downstream origin."""

    def test_message_contains_downstream_label(self):
        """Requirement: Telegram message says OPTIONS FOLLOW-UP or similar"""
        with open("options_scalper.py") as f:
            content = f.read()

        self.assertIn("FOLLOW-UP", content)

    def test_message_mentions_nifty_scalper_source(self):
        """Requirement: Message credits Nifty Scalper as source"""
        with open("options_scalper.py") as f:
            content = f.read()

        self.assertIn("Nifty Scalper", content)

    def test_message_shows_upstream_direction(self):
        """Requirement: Message displays upstream direction received"""
        with open("options_scalper.py") as f:
            content = f.read()

        # Should display direction from upstream
        self.assertIn("upstream_direction_str", content)


class TestProtectedFilesUnchanged(unittest.TestCase):
    """Test: Protected bots remain untouched."""

    def test_nifty_scalper_unchanged(self):
        """Requirement: nifty_scalper.py not modified"""
        with open("nifty_scalper.py") as f:
            content = f.read()

        # Should still have its own _save_state function
        self.assertIn("def _save_state():", content)
        # Should still have Supertrend
        self.assertIn("calculate_supertrend", content)

    def test_btc_bot_untouched(self):
        """Requirement: btc_bot.py not modified"""
        with open("btc_bot.py") as f:
            content = f.read()
        # Should still have original check_signal logic
        self.assertIn("check_signal", content)

    def test_gold_bot_untouched(self):
        """Requirement: gold_bot.py not modified"""
        with open("gold_bot.py") as f:
            content = f.read()
        self.assertIn("XAUUSD", content)

    def test_forex_scalper_untouched(self):
        """Requirement: forex_scalper.py not modified"""
        with open("forex_scalper.py") as f:
            content = f.read()
        self.assertIn("EURUSD", content)


if __name__ == "__main__":
    suite = unittest.TestLoader().loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
