"""
Telegram configuration and execution mode validation module.
Provides fail-closed validation for credentials and execution modes.
All signal bots must call this during startup before attempting to send messages.
"""

import os
import logging

log = logging.getLogger(__name__)

# ALLOWED EXECUTION MODES
ALLOWED_EXECUTION_MODES = {
    "dry_run",      # Scanning + Telegram only, NO orders
    "signal_only",  # Scanning + Telegram only, NO orders (DEFAULT/SAFE)
    "production",   # Scanning + Telegram + Orders (requires LIVE_TRADING_CONFIRMED=YES)
}

DEFAULT_EXECUTION_MODE = "signal_only"  # SAFE DEFAULT


def get_execution_mode(value=None):
    """
    Parse and validate execution mode with fail-closed semantics.

    Args:
        value: Optional explicit mode string (reads BOT_EXECUTION_MODE if omitted)

    Returns:
        Validated mode string: "dry_run", "signal_only", or "production"

    Raises:
        RuntimeError: if mode is unknown or malformed (FAIL-CLOSED)
    """
    raw = value if value is not None else os.getenv("BOT_EXECUTION_MODE", DEFAULT_EXECUTION_MODE)
    mode = str(raw).strip().lower()

    if mode not in ALLOWED_EXECUTION_MODES:
        raise RuntimeError(
            f"BOT_EXECUTION_MODE must be one of: {', '.join(sorted(ALLOWED_EXECUTION_MODES))} "
            f"(got: {repr(mode)})"
        )

    return mode


def order_execution_enabled():
    """
    Determine if order execution is allowed.

    CRITICAL SAFETY GATE:
    Production order execution requires BOTH conditions:
    1. BOT_EXECUTION_MODE=production
    2. LIVE_TRADING_CONFIRMED=YES

    Returns:
        True ONLY if both gates are satisfied
        False otherwise (default/safe)
    """
    mode = get_execution_mode()

    if mode != "production":
        return False

    # Production requires explicit secondary confirmation
    confirmation = os.getenv("LIVE_TRADING_CONFIRMED", "").strip().upper()

    if confirmation != "YES":
        return False

    return True


def is_dry_run_mode():
    """
    Deprecated: Use get_execution_mode() for explicit mode checking.
    Kept for backwards compatibility.

    Returns:
        True if mode is "dry_run", False otherwise
    """
    return get_execution_mode() == "dry_run"


def validate_telegram_config(token=None, chat_id=None):
    """
    Validate required Telegram configuration is present and non-empty.

    In DRY_RUN or SIGNAL_ONLY mode: allows synthetic credentials for testing.
    In PRODUCTION mode: requires real credentials (fail-closed).

    Args:
        token: Telegram bot token (reads TELEGRAM_BOT_TOKEN if omitted)
        chat_id: Telegram chat ID (reads TELEGRAM_CHAT_ID if omitted)

    Returns:
        Tuple of (token, chat_id) if both are valid

    Raises:
        RuntimeError: if token or chat_id is missing or empty in production mode
    """
    if token is None:
        token = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
    else:
        token = str(token).strip()

    if chat_id is None:
        chat_id = os.getenv("TELEGRAM_CHAT_ID", "").strip()
    else:
        chat_id = str(chat_id).strip()

    mode = get_execution_mode()
    is_production = (mode == "production")

    if not token:
        if is_production:
            raise RuntimeError("Missing required environment variable: TELEGRAM_BOT_TOKEN")
        else:
            token = "synthetic_bot_token_test_mode"

    if not chat_id:
        if is_production:
            raise RuntimeError("Missing required environment variable: TELEGRAM_CHAT_ID")
        else:
            chat_id = "synthetic_chat_id_test_mode"

    return token, chat_id
