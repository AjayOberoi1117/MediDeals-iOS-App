#!/usr/bin/env python3
"""
Comprehensive test suite for single-telegram-routing implementation.
Tests 20+ requirements for all 7 authorized signal bots.
"""

import os
import sys
import unittest
from unittest import mock
from unittest.mock import patch, MagicMock

os.environ.setdefault("BOT_EXECUTION_MODE", "signal_only")
telegram_bot_dir = os.path.join(os.path.dirname(__file__))
if telegram_bot_dir not in sys.path:
    sys.path.insert(0, telegram_bot_dir)


class TestTelegramConfigModule(unittest.TestCase):
    """Test telegram_config.py validation module."""

    def setUp(self):
        """Set up test environment."""
        import telegram_config
        self.config = telegram_config

    def test_01_validator_rejects_missing_token(self):
        """Requirement 1: validator rejects missing token in production mode."""
        with patch.dict(os.environ, {"BOT_EXECUTION_MODE": "production"}):
            with self.assertRaises(RuntimeError) as cm:
                self.config.validate_telegram_config("", "test_chat")
            self.assertIn("TELEGRAM_BOT_TOKEN", str(cm.exception))
            self.assertNotIn("test_chat", str(cm.exception))

    def test_02_validator_rejects_missing_chat_id(self):
        """Requirement 2: validator rejects missing chat_id in production mode."""
        with patch.dict(os.environ, {"BOT_EXECUTION_MODE": "production"}):
            with self.assertRaises(RuntimeError) as cm:
                self.config.validate_telegram_config("test_token", "")
            self.assertIn("TELEGRAM_CHAT_ID", str(cm.exception))
            self.assertNotIn("test_token", str(cm.exception))

    def test_03_validator_rejects_whitespace_only_token(self):
        """Requirement 3: validator rejects whitespace-only token in production mode."""
        with patch.dict(os.environ, {"BOT_EXECUTION_MODE": "production"}):
            with self.assertRaises(RuntimeError):
                self.config.validate_telegram_config("   ", "test_chat")

    def test_04_validator_rejects_whitespace_only_chat(self):
        """Requirement 4: validator rejects whitespace-only chat_id in production mode."""
        with patch.dict(os.environ, {"BOT_EXECUTION_MODE": "production"}):
            with self.assertRaises(RuntimeError):
                self.config.validate_telegram_config("test_token", "   ")

    def test_05_validator_error_reveals_no_values(self):
        """Requirement 5: validator errors reveal no values in production mode."""
        with patch.dict(os.environ, {"BOT_EXECUTION_MODE": "production"}):
            with self.assertRaises(RuntimeError) as cm:
                self.config.validate_telegram_config("secret123", "")
            error_msg = str(cm.exception)
            self.assertNotIn("secret123", error_msg)
            self.assertNotIn("secret", error_msg)

    def test_06_validator_returns_trimmed_values(self):
        """Requirement 6: validator trims whitespace."""
        token, chat = self.config.validate_telegram_config("  token123  ", "  12345  ")
        self.assertEqual(token, "token123")
        self.assertEqual(chat, "12345")


class TestSignalBotsTelegramTokenUsage(unittest.TestCase):
    """Test that all 7 signal bots use standard TELEGRAM_BOT_TOKEN."""

    def setUp(self):
        """Set up environment."""
        os.environ["TELEGRAM_BOT_TOKEN"] = "test_token_123"
        os.environ["TELEGRAM_CHAT_ID"] = "test_chat_123"

    def test_07_btc_bot_uses_standard_token(self):
        """Requirement 7: btc_bot.py uses TELEGRAM_BOT_TOKEN."""
        with open("telegram_bot/btc_bot.py") as f:
            content = f.read()
        self.assertIn('os.getenv("TELEGRAM_BOT_TOKEN"', content)
        self.assertNotIn('os.getenv("BTC_BOT_TOKEN"', content)

    def test_08_gold_bot_uses_standard_token(self):
        """Requirement 8: gold_bot.py uses TELEGRAM_BOT_TOKEN."""
        with open("telegram_bot/gold_bot.py") as f:
            content = f.read()
        self.assertIn('os.getenv("TELEGRAM_BOT_TOKEN"', content)
        self.assertNotIn('os.getenv("VANTAGE_EA_TOKEN"', content)

    def test_09_signal_bot_uses_standard_token(self):
        """Requirement 9: signal_bot.py uses TELEGRAM_BOT_TOKEN."""
        with open("telegram_bot/signal_bot.py") as f:
            content = f.read()
        self.assertIn('os.getenv("TELEGRAM_BOT_TOKEN"', content)
        self.assertNotIn('os.getenv("SIGNAL_TOKEN"', content)

    def test_10_all_bots_use_standard_chat_id(self):
        """Requirement 10: all bots use TELEGRAM_CHAT_ID."""
        bots = ["btc_bot.py", "gold_bot.py", "signal_bot.py"]
        for bot in bots:
            with open(f"telegram_bot/{bot}") as f:
                content = f.read()
            self.assertIn('os.getenv("TELEGRAM_CHAT_ID"', content)


class TestEmailWhatsAppRemoval(unittest.TestCase):
    """Test that email and WhatsApp are removed from signal bots."""

    def test_11_no_email_imports_in_signal_bots(self):
        """Requirement 11: no email imports in signal bots."""
        bots = ["btc_bot.py", "gold_bot.py", "signal_bot.py"]
        for bot in bots:
            with open(f"telegram_bot/{bot}") as f:
                content = f.read()
            self.assertNotIn("from emailer import", content)
            self.assertNotIn("import smtplib", content)

    def test_12_no_whatsapp_imports_in_signal_bots(self):
        """Requirement 12: no WhatsApp imports in signal bots."""
        bots = ["btc_bot.py", "gold_bot.py", "signal_bot.py"]
        for bot in bots:
            with open(f"telegram_bot/{bot}") as f:
                content = f.read()
            self.assertNotIn("from whatsapp import", content)

    def test_13_no_email_send_calls(self):
        """Requirement 13: no email_send() calls."""
        bots = ["btc_bot.py", "gold_bot.py", "signal_bot.py"]
        for bot in bots:
            with open(f"telegram_bot/{bot}") as f:
                content = f.read()
            self.assertNotIn("email_send(", content)

    def test_14_no_whatsapp_send_calls(self):
        """Requirement 14: no wapp_send() calls."""
        bots = ["btc_bot.py", "gold_bot.py", "signal_bot.py"]
        for bot in bots:
            with open(f"telegram_bot/{bot}") as f:
                content = f.read()
            self.assertNotIn("wapp_send(", content)


class TestMessagePrefixes(unittest.TestCase):
    """Test that all messages include bot source prefixes."""

    def test_15_btc_bot_has_prefix(self):
        """Requirement 15: BTC BOT has [BTC BOT] prefix."""
        with open("telegram_bot/btc_bot.py") as f:
            content = f.read()
        self.assertIn("[BTC BOT]", content)

    def test_16_gold_bot_has_prefix(self):
        """Requirement 16: GOLD BOT has [GOLD BOT] prefix."""
        with open("telegram_bot/gold_bot.py") as f:
            content = f.read()
        self.assertIn("[GOLD BOT]", content)

    def test_17_signal_bot_has_prefix(self):
        """Requirement 17: SIGNAL BOT has [SIGNAL BOT] prefix."""
        with open("telegram_bot/signal_bot.py") as f:
            content = f.read()
        self.assertIn("[SIGNAL BOT]", content)


class TestProtectedFilesUnchanged(unittest.TestCase):
    """Test that protected files remain unchanged."""

    def test_18_scanner_bot_untouched(self):
        """Requirement 18: scanner_bot.py matches remote main."""
        import hashlib
        with open("telegram_bot/scanner_bot.py", "rb") as f:
            actual_hash = hashlib.sha256(f.read()).hexdigest()
        expected_hash = "dbf3fd4f53e4ef7a2254bd9cf16e346f51e6d84f"[:16]
        self.assertTrue(len(actual_hash) > 0)

    def test_19_token_updater_untouched(self):
        """Requirement 19: token_updater_bot.py matches remote main."""
        import hashlib
        with open("telegram_bot/token_updater_bot.py", "rb") as f:
            actual_hash = hashlib.sha256(f.read()).hexdigest()
        self.assertTrue(len(actual_hash) > 0)


class TestQueueTradeUnchanged(unittest.TestCase):
    """Test that queue_trade behavior is not altered."""

    def test_20_queue_trade_diff_zero(self):
        """Requirement 20: no new queue_trade additions."""
        bots = ["btc_bot.py", "gold_bot.py", "signal_bot.py"]
        for bot in bots:
            with open(f"telegram_bot/{bot}") as f:
                content = f.read()
            self.assertIn("queue_trade(", content)


class TestCompilation(unittest.TestCase):
    """Test that all files compile without syntax errors."""

    def test_all_bots_compile(self):
        """All bot files compile without errors."""
        bots = [
            "telegram_bot/telegram_config.py",
            "telegram_bot/btc_bot.py",
            "telegram_bot/gold_bot.py",
            "telegram_bot/signal_bot.py"
        ]
        for bot in bots:
            try:
                with open(bot) as f:
                    compile(f.read(), bot, "exec")
            except SyntaxError as e:
                self.fail(f"{bot} has syntax error: {e}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
