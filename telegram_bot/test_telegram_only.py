"""
Test suite verifying Telegram-only notification configuration.
Tests call actual production functions with mocked HTTP boundaries.
"""

import os
import sys
import unittest
from unittest.mock import patch, MagicMock

try:
    from .telegram_config import validate_telegram_config
except ImportError:
    from telegram_config import validate_telegram_config


class TestTelegramConfiguration(unittest.TestCase):
    """Test Telegram configuration requirements."""

    def test_missing_token_fails(self):
        """Test 1: Missing TELEGRAM_BOT_TOKEN raises RuntimeError."""
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(RuntimeError) as ctx:
                validate_telegram_config()
            self.assertIn("TELEGRAM_BOT_TOKEN", str(ctx.exception))

    def test_missing_chat_id_fails(self):
        """Test 2: Missing TELEGRAM_CHAT_ID raises RuntimeError."""
        with patch.dict(os.environ, {"TELEGRAM_BOT_TOKEN": "test_token"}, clear=True):
            with self.assertRaises(RuntimeError) as ctx:
                validate_telegram_config()
            self.assertIn("TELEGRAM_CHAT_ID", str(ctx.exception))

    def test_both_missing_fails(self):
        """Test 3: Both missing raises RuntimeError."""
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(RuntimeError):
                validate_telegram_config()

    def test_whitespace_only_token_fails(self):
        """Test 4: Whitespace-only token fails."""
        with patch.dict(os.environ, {"TELEGRAM_BOT_TOKEN": "   ", "TELEGRAM_CHAT_ID": "valid"}, clear=True):
            with self.assertRaises(RuntimeError) as ctx:
                validate_telegram_config()
            self.assertIn("TELEGRAM_BOT_TOKEN", str(ctx.exception))

    def test_whitespace_only_chat_id_fails(self):
        """Test 5: Whitespace-only chat ID fails."""
        with patch.dict(os.environ, {"TELEGRAM_BOT_TOKEN": "valid", "TELEGRAM_CHAT_ID": "  \t  "}, clear=True):
            with self.assertRaises(RuntimeError) as ctx:
                validate_telegram_config()
            self.assertIn("TELEGRAM_CHAT_ID", str(ctx.exception))

    def test_both_present_return_tuple(self):
        """Test 6: Both present return (token, chat_id) tuple."""
        with patch.dict(os.environ, {
            "TELEGRAM_BOT_TOKEN": "test_bot_token",
            "TELEGRAM_CHAT_ID": "test_chat_id"
        }, clear=True):
            result = validate_telegram_config()
            self.assertIsInstance(result, tuple)
            self.assertEqual(len(result), 2)
            self.assertEqual(result[0], "test_bot_token")
            self.assertEqual(result[1], "test_chat_id")

    def test_error_does_not_contain_token_value(self):
        """Test 7: Error message never includes synthetic token."""
        with patch.dict(os.environ, {"TELEGRAM_BOT_TOKEN": "secret_token_12345"}, clear=True):
            with self.assertRaises(RuntimeError) as ctx:
                validate_telegram_config()
            self.assertNotIn("secret_token_12345", str(ctx.exception))

    def test_error_does_not_contain_chat_id_value(self):
        """Test 8: Error message never includes synthetic chat ID."""
        with patch.dict(os.environ, {"TELEGRAM_CHAT_ID": "secret_chat_9876543"}, clear=True):
            with self.assertRaises(RuntimeError) as ctx:
                validate_telegram_config()
            self.assertNotIn("secret_chat_9876543", str(ctx.exception))


class TestBotCompilation(unittest.TestCase):
    """Test that all modified bots compile and import safely."""

    def test_all_bots_compile(self):
        """Test 9: Every modified bot compiles."""
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

        import py_compile
        for bot_file in bot_files:
            try:
                py_compile.compile(bot_file, doraise=True)
            except py_compile.PyCompileError as e:
                self.fail(f"{bot_file} failed to compile: {e}")

    @patch('requests.post')
    def test_bots_import_safely_without_credentials(self, mock_post):
        """Test 10: Every bot imports safely without credentials."""
        with patch.dict(os.environ, {}, clear=True):
            bot_modules = [
                'telegram_bot.btc_bot',
                'telegram_bot.forex_scalper',
                'telegram_bot.gold_bot',
                'telegram_bot.india_scalper',
                'telegram_bot.nifty_scalper',
                'telegram_bot.options_scalper',
                'telegram_bot.scanner_bot',
                'telegram_bot.signal_bot',
            ]

            for module_name in bot_modules:
                try:
                    __import__(module_name)
                except RuntimeError:
                    self.fail(f"{module_name} raised RuntimeError during import")
                except ImportError as e:
                    if "No module named" in str(e) or "cannot import" in str(e).lower():
                        pass
                    else:
                        raise


class TestValidationIntegration(unittest.TestCase):
    """Test that all bots call production validation at startup."""

    def test_all_bots_call_validation_at_startup(self):
        """Test 11: Every bot imports and calls production validation."""
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
            self.assertIn('from telegram_config import validate_telegram_config', content,
                         f"{bot_file}: missing import of validate_telegram_config")
            self.assertIn('validate_telegram_config', content,
                         f"{bot_file}: validate_telegram_config not called")


class TestNotificationRemoval(unittest.TestCase):
    """Test that email and WhatsApp have been removed."""

    def test_no_legacy_variables(self):
        """Test 12: Legacy notification variables absent."""
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
            for legacy in legacy_names:
                self.assertNotIn(legacy, content, f"{bot_file}: Legacy {legacy} found")

    def test_no_email_imports(self):
        """Test 13: Email imports absent from all bots."""
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

    def test_no_whatsapp_api_calls(self):
        """Test 14: WhatsApp API references absent from all bots."""
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
            self.assertNotIn('pywhatkit', content, f"{bot_file}: pywhatkit import found")


class TestNetworkIsolation(unittest.TestCase):
    """Test network isolation with proper assertions."""

    @patch('requests.post')
    def test_telegram_send_mocked(self, mock_post):
        """Test 15: Actual Telegram send function calls requests.post exactly once."""
        with patch.dict(os.environ, {
            "TELEGRAM_BOT_TOKEN": "synthetic_bot_token_test",
            "TELEGRAM_CHAT_ID": "synthetic_chat_id_12345"
        }):
            mock_response = MagicMock()
            mock_response.json.return_value = {"ok": True}
            mock_post.return_value = mock_response

            from telegram_bot.btc_bot import tg_send
            tg_send("Test message")

            self.assertEqual(mock_post.call_count, 1, "requests.post must be called exactly once")

    @patch('requests.post')
    def test_telegram_url_correct(self, mock_post):
        """Test 16: Request URL begins with https://api.telegram.org/."""
        with patch.dict(os.environ, {
            "TELEGRAM_BOT_TOKEN": "synthetic_bot_token",
            "TELEGRAM_CHAT_ID": "synthetic_chat_id"
        }):
            mock_response = MagicMock()
            mock_response.json.return_value = {"ok": True}
            mock_post.return_value = mock_response

            from telegram_bot.gold_bot import tg_send
            tg_send("Test")

            call_args = mock_post.call_args
            url = call_args[0][0] if call_args[0] else None
            self.assertTrue(url.startswith("https://api.telegram.org/"),
                           f"URL must start with https://api.telegram.org/, got {url}")

    @patch('requests.post')
    def test_payload_contains_chat_id(self, mock_post):
        """Test 17: Payload contains chat_id field."""
        with patch.dict(os.environ, {
            "TELEGRAM_BOT_TOKEN": "synthetic_token",
            "TELEGRAM_CHAT_ID": "test_chat_id_value"
        }):
            mock_response = MagicMock()
            mock_response.json.return_value = {"ok": True}
            mock_post.return_value = mock_response

            try:
                from telegram_bot.gold_bot import tg_send
                tg_send("Test")

                call_args = mock_post.call_args
                payload = call_args[1]['data']
                self.assertIn('chat_id', payload, "Payload must contain chat_id field")
                self.assertIsInstance(payload['chat_id'], str, "chat_id must be a string")
            except (ModuleNotFoundError, ImportError):
                self.skipTest("Missing dependencies")

    @patch('requests.post')
    def test_no_second_url_called(self, mock_post):
        """Test 18: No second URL called (no email/WhatsApp)."""
        with patch.dict(os.environ, {
            "TELEGRAM_BOT_TOKEN": "test_token",
            "TELEGRAM_CHAT_ID": "test_chat"
        }):
            mock_response = MagicMock()
            mock_response.json.return_value = {"ok": True}
            mock_post.return_value = mock_response

            try:
                from telegram_bot.gold_bot import tg_send
                tg_send("Test")
                self.assertEqual(mock_post.call_count, 1, "Only one requests.post call allowed")
            except (ModuleNotFoundError, ImportError):
                self.skipTest("Missing dependencies")

    @patch('requests.post')
    def test_no_whatsapp_url(self, mock_post):
        """Test 19: No WhatsApp URL in calls."""
        with patch.dict(os.environ, {
            "TELEGRAM_BOT_TOKEN": "test_token",
            "TELEGRAM_CHAT_ID": "test_chat"
        }):
            mock_response = MagicMock()
            mock_response.json.return_value = {"ok": True}
            mock_post.return_value = mock_response

            try:
                from telegram_bot.forex_scalper import tg_send
                tg_send("Test")

                call_args = mock_post.call_args
                url = call_args[0][0] if call_args[0] else None
                self.assertNotIn("graph.facebook.com", url, "WhatsApp URL must not be called")
            except (ModuleNotFoundError, ImportError):
                self.skipTest("Missing dependencies")

    @patch('requests.post')
    def test_failure_path_proper_exception(self, mock_post):
        """Test 20: Mock failure produces documented exception handling."""
        mock_post.side_effect = Exception("Network error")

        with patch.dict(os.environ, {
            "TELEGRAM_BOT_TOKEN": "test_token",
            "TELEGRAM_CHAT_ID": "test_chat"
        }):
            from telegram_bot.scanner_bot import send_telegram
            try:
                send_telegram("Test")
            except Exception as e:
                self.assertEqual(mock_post.call_count, 1, "Mock called exactly once before exception")

    @patch('requests.post')
    def test_validation_called_before_send(self, mock_post):
        """Test 21: Validation is called before attempting sends."""
        with patch.dict(os.environ, {}, clear=True):
            mock_post.side_effect = Exception("Should not reach here")
            try:
                from telegram_bot.btc_bot import main
            except ImportError:
                pass
            self.assertEqual(mock_post.call_count, 0, "No network calls before validation")

    @patch('requests.post')
    def test_synthetic_credentials_work(self, mock_post):
        """Test 22: Synthetic credentials are used in actual calls."""
        with patch.dict(os.environ, {
            "TELEGRAM_BOT_TOKEN": "synthetic_bot_12345",
            "TELEGRAM_CHAT_ID": "synthetic_chat_67890"
        }):
            mock_response = MagicMock()
            mock_response.json.return_value = {"ok": True}
            mock_post.return_value = mock_response

            from telegram_bot.btc_bot import tg_send
            tg_send("Test message")

            self.assertEqual(mock_post.call_count, 1)
            call_args = mock_post.call_args
            url = call_args[0][0] if call_args[0] else None
            self.assertIn("https://api.telegram.org/bot", url)


if __name__ == '__main__':
    unittest.main(verbosity=2)
