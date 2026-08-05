"""
Production Telegram configuration validation.

Provides fail-closed validation for required Telegram credentials.
All bots must call this during startup before attempting to send messages.

Supports DRY_RUN mode for testing without live Telegram API calls.
"""

import os


def is_dry_run_mode():
    return os.getenv("BOT_EXECUTION_MODE", "").lower() == "dry_run"


def validate_telegram_config(token=None, chat_id=None):
    """
    Validate required Telegram configuration is present and non-empty.

    In DRY_RUN mode: allows synthetic credentials for testing.
    In production mode: requires real credentials.

    Args:
        token: Telegram bot token (reads TELEGRAM_BOT_TOKEN if omitted)
        chat_id: Telegram chat ID (reads TELEGRAM_CHAT_ID if omitted)

    Returns:
        Tuple of (token, chat_id) if both are valid

    Raises:
        RuntimeError: if token or chat_id is missing or empty (production only)
    """
    if token is None:
        token = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
    else:
        token = str(token).strip()

    if chat_id is None:
        chat_id = os.getenv("TELEGRAM_CHAT_ID", "").strip()
    else:
        chat_id = str(chat_id).strip()

    dry_run = is_dry_run_mode()

    if not token:
        if dry_run:
            token = "synthetic_bot_token_dry_run"
        else:
            raise RuntimeError("Missing required environment variable: TELEGRAM_BOT_TOKEN")

    if not chat_id:
        if dry_run:
            chat_id = "synthetic_chat_id_dry_run"
        else:
            raise RuntimeError("Missing required environment variable: TELEGRAM_CHAT_ID")

    return token, chat_id
