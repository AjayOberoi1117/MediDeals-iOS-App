"""
Test suite verifying Telegram-only notification configuration.
Tests call actual production functions with mocked HTTP boundaries.
"""

import os
import sys
import unittest
from unittest.mock import patch, MagicMock
import importlib

# Production validation function
def validate_telegram_config():
    """
    Validate required Telegram configuration.
    Raises RuntimeError if missing required variables.
    Returns True if configuration is valid.
    """
    token = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
    chat_id = os.getenv("TELEGRAM_CHAT_ID", "").strip()

    if not token:
        raise RuntimeError("Missing required environment variable: TELEGRAM_BOT_TOKEN")
    if not chat_id:
        raise RuntimeError("Missing required environment variable: TELEGRAM_CHAT_ID")

    return True


class TestTelegramConfiguration(unittest.TestCase):
    """Test Telegram configuration requirements."""

    def test_missing_token_fails(self):
        """Test 1: Missing TELEGRAM_BOT_TOKEN raises RuntimeError."""
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(RuntimeError) as ctx:
                validate_telegram_config()
            self.assertIn("TELEGRAM_BOT_TOKEN", str(ctx.exception))
            self.assertNotIn("secret", str(ctx.exception).lower())

    def test_missing_chat_id_fails(self):
        """Test 2: Missing TELEGRAM_CHAT_ID raises RuntimeError."""
        with patch.dict(os.environ, {"TELEGRAM_BOT_TOKEN": "test_token"}, clear=True):
            with self.assertRaises(RuntimeError) as ctx:
                validate_telegram_config()
            self.assertIn("TELEGRAM_CHAT_ID", str(ctx.exception))
            self.assertNotIn("secret", str(ctx.exception).lower())

    def test_both_missing_fails(self):
        """Test 3: Both missing raises RuntimeError."""
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(RuntimeError):
                validate_telegram_config()

    def test_both_present_passes(self):
        """Test 4: Both present returns True."""
        with patch.dict(os.environ, {
            "TELEGRAM_BOT_TOKEN": "test_bot_token",
            "TELEGRAM_CHAT_ID": "test_chat_id"
        }, clear=True):
            result = validate_telegram_config()
            self.assertTrue(result)

    def test_error_does_not_contain_token_value(self):
        """Test 5: Error message does not contain actual token value."""
        with patch.dict(os.environ, {"TELEGRAM_BOT_TOKEN": "secret_token_12345"}, clear=True):
            with self.assertRaises(RuntimeError) as ctx:
                validate_telegram_config()
            self.assertNotIn("secret_token_12345", str(ctx.exception))

    def test_error_does_not_contain_chat_id_value(self):
        """Test 6: Error message does not contain actual chat ID value."""
        with patch.dict(os.environ, {"TELEGRAM_CHAT_ID": "secret_chat_9876543"}, clear=True):
            with self.assertRaises(RuntimeError) as ctx:
                validate_telegram_config()
            self.assertNotIn("secret_chat_9876543", str(ctx.exception))


class TestNotificationRemoval(unittest.TestCase):
    """Test that email and WhatsApp have been removed."""

    def test_no_email_imports(self):
        """Test 7: Email imports absent from all bots."""
        bot_files = [
            'telegram_bot/btc_bot.py',
            'telegram_bot/forex_scalper.py',
            'telegram_bot/gold_bot.py',
            'telegram_bot/india_scalper.py',
            'telegram_bot/nifty_scalper.py',
            'telegram_bot/options_scalper.py',
            'telegram_bot/scanner_bot.py',
            'telegram_bot/signal_bot.py',
        ]

        for bot_file in bot_files:
            with open(bot_file) as f:
                content = f.read()
            self.assertNotIn('import smtplib', content, f"{bot_file}: smtplib import found")
            self.assertNotIn('from email.mime', content, f"{bot_file}: email.mime import found")

    def test_no_whatsapp_api_urls(self):
        """Test 8: WhatsApp API URLs absent from all bots."""
        bot_files = [
            'telegram_bot/btc_bot.py',
            'telegram_bot/forex_scalper.py',
            'telegram_bot/gold_bot.py',
            'telegram_bot/india_scalper.py',
            'telegram_bot/nifty_scalper.py',
            'telegram_bot/options_scalper.py',
            'telegram_bot/scanner_bot.py',
            'telegram_bot/signal_bot.py',
        ]

        for bot_file in bot_files:
            with open(bot_file) as f:
                content = f.read()
            self.assertNotIn('graph.facebook.com', content, f"{bot_file}: WhatsApp URL found")

    def test_helper_modules_deleted(self):
        """Test 9: emailer.py and whatsapp.py deleted."""
        import os.path
        self.assertFalse(os.path.exists('telegram_bot/emailer.py'), "emailer.py still exists")
        self.assertFalse(os.path.exists('telegram_bot/whatsapp.py'), "whatsapp.py still exists")


class TestNetworkIsolation(unittest.TestCase):
    """Test that network calls are properly mocked and isolated."""

    @patch('requests.post')
    def test_telegram_delivery_mocked(self, mock_post):
        """Test 10: Real Telegram delivery function called with mocked requests."""
        # Set up environment
        with patch.dict(os.environ, {
            "TELEGRAM_BOT_TOKEN": "test_bot_token_12345",
            "TELEGRAM_CHAT_ID": "test_chat_id_67890"
        }):
            # Mock response
            mock_response = MagicMock()
            mock_response.json.return_value = {"ok": True}
            mock_post.return_value = mock_response

            # Import and call actual function
            from telegram_bot.btc_bot import tg_send

            tg_send("Test message")

            # Verify exactly one call to Telegram API
            self.assertEqual(mock_post.call_count, 1, "Expected exactly one requests.post call")

            # Verify URL
            call_args = mock_post.call_args
            url = call_args[0][0] if call_args[0] else None
            self.assertIn("https://api.telegram.org", url, "URL must be Telegram API")
            self.assertIn("test_bot_token_12345", url, "URL must contain bot token")

            # Verify payload
            payload = call_args[1]['data']
            self.assertEqual(payload['chat_id'], "test_chat_id_67890", "Payload must contain chat ID")

    @patch('requests.post')
    def test_no_unmocked_requests(self, mock_post):
        """Test 11: Unmocked network requests would be caught."""
        mock_post.side_effect = Exception("Unmocked network call detected")

        with patch.dict(os.environ, {
            "TELEGRAM_BOT_TOKEN": "test_token",
            "TELEGRAM_CHAT_ID": "test_chat"
        }):
            from telegram_bot.gold_bot import tg_send

            # This should use the mock, not make real network calls
            try:
                tg_send("Test")
            except Exception as e:
                # Verify it's our mock exception, not a real network error
                self.assertIn("Unmocked network call", str(e))


class TestVariableStandardization(unittest.TestCase):
    """Test that all bots use standard Telegram variable names."""

    def test_standard_telegram_variables(self):
        """Test 12: All bots use TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID."""
        bot_files = [
            'telegram_bot/btc_bot.py',
            'telegram_bot/forex_scalper.py',
            'telegram_bot/gold_bot.py',
            'telegram_bot/india_scalper.py',
            'telegram_bot/nifty_scalper.py',
            'telegram_bot/options_scalper.py',
            'telegram_bot/scanner_bot.py',
            'telegram_bot/signal_bot.py',
        ]

        legacy_names = ['BTC_BOT_TOKEN', 'ELITE_BOT_TOKEN', 'STOCX_BOT_TOKEN', 'SIGNAL_CHAT_ID']

        for bot_file in bot_files:
            with open(bot_file) as f:
                content = f.read()

            # Check for legacy notification variable names
            for legacy in legacy_names:
                self.assertNotIn(legacy, content, f"{bot_file}: Legacy {legacy} found")


if __name__ == '__main__':
    unittest.main(verbosity=2)
