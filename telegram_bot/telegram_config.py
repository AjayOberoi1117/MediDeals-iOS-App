"""
Production Telegram configuration validation.

Provides fail-closed validation for required Telegram credentials.
All bots must call this during startup before attempting to send messages.
"""

import os


def validate_telegram_config(token=None, chat_id=None):
    """
    Validate required Telegram configuration is present and non-empty.

    Args:
        token: Telegram bot token (reads TELEGRAM_BOT_TOKEN if omitted)
        chat_id: Telegram chat ID (reads TELEGRAM_CHAT_ID if omitted)

    Returns:
        Tuple of (token, chat_id) if both are valid

    Raises:
        RuntimeError: if token or chat_id is missing or empty
    """
    if token is None:
        token = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
    else:
        token = str(token).strip()

    if chat_id is None:
        chat_id = os.getenv("TELEGRAM_CHAT_ID", "").strip()
    else:
        chat_id = str(chat_id).strip()

    if not token:
        raise RuntimeError("Missing required environment variable: TELEGRAM_BOT_TOKEN")

    if not chat_id:
        raise RuntimeError("Missing required environment variable: TELEGRAM_CHAT_ID")

    return token, chat_id
