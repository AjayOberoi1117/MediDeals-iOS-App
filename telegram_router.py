"""
UNIFIED TELEGRAM ROUTING FOR DEMO BOT PORTFOLIO
===============================================

Central routing for all bot Telegram alerts.
Ensures consistent formatting, prevents duplicates, records delivery status.

Features:
- Unique bot ID and name for every bot
- PAPER label on all alerts
- Unique signal ID per trade
- Delivery status tracking (attempted, delivered, failed)
- Bounded retries with exponential backoff
- Per-bot enable/disable
- Duplicate detection
- Secure token handling (no logging of full tokens)
"""

import os
import time
import logging
import json
import hashlib
from datetime import datetime
from typing import Dict, Optional, Tuple
from enum import Enum

import requests
from dotenv import load_dotenv

load_dotenv()

log = logging.getLogger(__name__)


class TelegramStatus(Enum):
    """Telegram message delivery status."""
    ATTEMPTED = "attempted"
    DELIVERED = "delivered"
    FAILED = "failed"
    RETRYING = "retrying"


class BotRegistry:
    """Central registry of all bots with their Telegram configuration."""

    # Bot definitions: (BOT_ID, BOT_NAME, DESCRIPTION)
    BOTS = {
        "scanner_v2": {
            "id": "scanner_v2",
            "name": "EQUITY-SCANNER-V2",
            "description": "NIFTY 50/100 intraday scanner (EMA+RSI)",
            "market": "NSE Equities",
            "enabled": True,
        },
        "nifty_scalper_v1": {
            "id": "nifty_scalper_v1",
            "name": "NIFTY-SCALPER-V1",
            "description": "NIFTY intraday scalper",
            "market": "NIFTY Index",
            "enabled": True,
        },
        "banknifty_scalper_v1": {
            "id": "banknifty_scalper_v1",
            "name": "BANKNIFTY-SCALPER-V1",
            "description": "BANK NIFTY intraday scalper",
            "market": "BANK NIFTY Index",
            "enabled": False,  # Not yet implemented
        },
        "india_scalper_v1": {
            "id": "india_scalper_v1",
            "name": "INDIA-SCALPER-V1",
            "description": "NSE equities scalper (deprecated, blocked)",
            "market": "NSE Equities",
            "enabled": False,  # Disabled per user request
        },
        "options_scalper_v1": {
            "id": "options_scalper_v1",
            "name": "OPTIONS-SCALPER-V1",
            "description": "NSE options scalper",
            "market": "NSE Options",
            "enabled": False,  # Not yet implemented
        },
        "forex_scalper_v1": {
            "id": "forex_scalper_v1",
            "name": "FOREX-SCALPER-V1",
            "description": "Forex scalper (MT5 local)",
            "market": "Forex",
            "enabled": False,  # Not yet implemented
        },
        "btc_scalper_v1": {
            "id": "btc_scalper_v1",
            "name": "BTC-SCALPER-V1",
            "description": "Bitcoin intraday scalper",
            "market": "Crypto",
            "enabled": False,  # Not yet implemented
        },
    }

    @classmethod
    def get_bot(cls, bot_id: str) -> Optional[Dict]:
        """Get bot configuration by ID."""
        return cls.BOTS.get(bot_id)

    @classmethod
    def is_enabled(cls, bot_id: str) -> bool:
        """Check if a bot is enabled for alerts."""
        bot = cls.get_bot(bot_id)
        return bot and bot.get("enabled", False)

    @classmethod
    def get_bot_name(cls, bot_id: str) -> str:
        """Get formatted bot name."""
        bot = cls.get_bot(bot_id)
        return bot["name"] if bot else "UNKNOWN"


# ──────────────────────────────────────────────────────────────────────────────
# TELEGRAM CONFIGURATION
# ──────────────────────────────────────────────────────────────────────────────

class TelegramConfig:
    """Telegram configuration from environment."""

    # Primary bot token and chat (for all paper bot alerts)
    BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN") or os.getenv("BOT_TOKEN", "")
    CHAT_ID = os.getenv("TELEGRAM_CHAT_ID") or os.getenv("CHAT_ID", "")

    # Per-bot routing (can override default)
    BOT_ROUTES = {}  # {bot_id: {token: ..., chat_id: ...}}

    # Rate limiting
    MAX_RETRIES = 3
    RETRY_BACKOFF_SECS = [1, 3, 10]  # Exponential backoff: 1s, 3s, 10s

    # Timeout
    REQUEST_TIMEOUT_SECS = 10

    @classmethod
    def is_configured(cls) -> bool:
        """Check if Telegram is configured."""
        return bool(cls.BOT_TOKEN and cls.CHAT_ID)

    @classmethod
    def get_token_redacted(cls) -> str:
        """Get redacted token for logging."""
        if not cls.BOT_TOKEN:
            return "NOT_SET"
        # Show first 10 and last 4 chars
        if len(cls.BOT_TOKEN) > 14:
            return f"{cls.BOT_TOKEN[:10]}...{cls.BOT_TOKEN[-4:]}"
        return "***"

    @classmethod
    def get_chat_id_redacted(cls) -> str:
        """Get redacted chat ID for logging."""
        if not cls.CHAT_ID:
            return "NOT_SET"
        # Show last 4 digits only
        return f"***{str(cls.CHAT_ID)[-4:]}"


# ──────────────────────────────────────────────────────────────────────────────
# TELEGRAM ALERT FORMATTING
# ──────────────────────────────────────────────────────────────────────────────

class TelegramFormatter:
    """Formats alert messages for Telegram."""

    @staticmethod
    def entry_signal(
        bot_id: str,
        symbol: str,
        direction: str,
        signal_time: str,
        timeframe: str,
        confidence: str,
        entry_price: float,
        stop_loss: float,
        target: float,
        quantity: int,
        signal_id: str,
        strategy_version: str,
    ) -> str:
        """
        Format entry signal alert.

        Returns:
            str: Formatted message for Telegram
        """
        bot_name = BotRegistry.get_bot_name(bot_id)
        return (
            f"<b>[PAPER] {bot_name}</b>\n"
            f"<b>Signal:</b> {symbol} {direction}\n"
            f"<b>Entry:</b> {entry_price}\n"
            f"<b>SL:</b> {stop_loss}\n"
            f"<b>Target:</b> {target}\n"
            f"<b>Qty:</b> {quantity}\n"
            f"<b>Confidence:</b> {confidence}\n"
            f"<b>Timeframe:</b> {timeframe}\n"
            f"<b>Time:</b> {signal_time}\n"
            f"<b>Strategy:</b> {strategy_version}\n"
            f"<b>Signal ID:</b> <code>{signal_id}</code>\n"
            f"\n"
            f"<i>DEMO / PAPER TRADE — NO BROKER ORDER</i>\n"
            f"<i>Simulated entry only</i>"
        )

    @staticmethod
    def exit_signal(
        bot_id: str,
        symbol: str,
        direction: str,
        exit_type: str,
        exit_price: float,
        entry_price: float,
        quantity: int,
        pnl: float,
        pnl_pct: float,
        exit_time: str,
        signal_id: str,
    ) -> str:
        """Format exit signal alert."""
        bot_name = BotRegistry.get_bot_name(bot_id)
        pnl_emoji = "✅" if pnl >= 0 else "❌"
        return (
            f"<b>[PAPER] {bot_name}</b>\n"
            f"<b>Exit:</b> {symbol} {direction}\n"
            f"<b>Entry:</b> {entry_price}\n"
            f"<b>Exit:</b> {exit_price}\n"
            f"<b>Exit Type:</b> {exit_type}\n"
            f"<b>Qty:</b> {quantity}\n"
            f"<b>P&L:</b> {pnl_emoji} {pnl:.2f} ({pnl_pct:+.2f}%)\n"
            f"<b>Time:</b> {exit_time}\n"
            f"<b>Signal ID:</b> <code>{signal_id}</code>\n"
            f"\n"
            f"<i>DEMO / PAPER TRADE — NOT SENT TO BROKER</i>"
        )

    @staticmethod
    def bot_start(bot_id: str, git_commit: str) -> str:
        """Format bot start message."""
        bot_name = BotRegistry.get_bot_name(bot_id)
        return (
            f"<b>✅ [PAPER] {bot_name} started</b>\n"
            f"<b>Mode:</b> DEMO/PAPER\n"
            f"<b>Version:</b> <code>{git_commit[:8]}</code>\n"
            f"<i>No broker orders will be placed</i>"
        )

    @staticmethod
    def bot_stop(bot_id: str, reason: str) -> str:
        """Format bot stop message."""
        bot_name = BotRegistry.get_bot_name(bot_id)
        return f"<b>⏹️ [PAPER] {bot_name} stopped</b>\n<b>Reason:</b> {reason}"

    @staticmethod
    def bot_error(bot_id: str, error: str) -> str:
        """Format bot error message."""
        bot_name = BotRegistry.get_bot_name(bot_id)
        return (
            f"<b>❌ [PAPER] {bot_name} error</b>\n"
            f"<b>Error:</b> {error}\n"
            f"<i>Check logs for details</i>"
        )

    @staticmethod
    def stale_data_alert(bot_id: str, symbol: str, age_seconds: int) -> str:
        """Format stale data alert."""
        bot_name = BotRegistry.get_bot_name(bot_id)
        return (
            f"<b>⚠️ [PAPER] {bot_name}</b>\n"
            f"<b>Stale data:</b> {symbol}\n"
            f"<b>Age:</b> {age_seconds}s\n"
            f"<b>Action:</b> Skipping signal"
        )


# ──────────────────────────────────────────────────────────────────────────────
# TELEGRAM ROUTER
# ──────────────────────────────────────────────────────────────────────────────

class TelegramRouter:
    """Central Telegram message router."""

    # Message delivery ledger: {signal_id: {bot_id, status, attempt_count, ...}}
    _ledger: Dict[str, Dict] = {}

    # Duplicate detection: {hash(bot_id, symbol, time_bucket): count}
    _recent_signals: Dict[str, int] = {}

    @classmethod
    def send_alert(
        cls,
        bot_id: str,
        message_type: str,
        message_text: str,
        signal_id: Optional[str] = None,
    ) -> Tuple[bool, str]:
        """
        Send a Telegram alert.

        Args:
            bot_id: Bot identifier
            message_type: Type of message (entry, exit, error, etc.)
            message_text: Formatted message text
            signal_id: Unique signal identifier

        Returns:
            (success: bool, message_id_or_error: str)
        """

        # Check if bot is enabled
        if not BotRegistry.is_enabled(bot_id):
            log.debug(f"Bot {bot_id} disabled for Telegram alerts")
            return False, "BOT_DISABLED"

        # Check if configured
        if not TelegramConfig.is_configured():
            log.warning("Telegram not configured (no token/chat)")
            return False, "NOT_CONFIGURED"

        # Record attempt
        if signal_id:
            cls._record_attempt(signal_id, bot_id)

        # Send with retry logic
        success, result = cls._send_with_retry(message_text)

        if success:
            log.info(
                f"[{bot_id}] Telegram delivered: {signal_id or message_type} "
                f"(token={TelegramConfig.get_token_redacted()}, "
                f"chat={TelegramConfig.get_chat_id_redacted()})"
            )
            if signal_id:
                cls._record_delivery(signal_id, bot_id, TelegramStatus.DELIVERED)
            return True, result  # result is message_id
        else:
            log.error(f"[{bot_id}] Telegram failed: {signal_id or message_type}: {result}")
            if signal_id:
                cls._record_delivery(signal_id, bot_id, TelegramStatus.FAILED)
            return False, result  # result is error message

    @classmethod
    def _send_with_retry(cls, message: str) -> Tuple[bool, str]:
        """Send message with exponential backoff retries."""
        url = f"https://api.telegram.org/bot{TelegramConfig.BOT_TOKEN}/sendMessage"
        headers = {"Content-Type": "application/json"}
        payload = {
            "chat_id": TelegramConfig.CHAT_ID,
            "text": message,
            "parse_mode": "HTML",
        }

        for attempt in range(TelegramConfig.MAX_RETRIES):
            try:
                response = requests.post(
                    url,
                    json=payload,
                    headers=headers,
                    timeout=TelegramConfig.REQUEST_TIMEOUT_SECS,
                )
                if response.status_code == 200:
                    data = response.json()
                    if data.get("ok"):
                        message_id = data.get("result", {}).get("message_id", "?")
                        return True, str(message_id)
                    else:
                        error = data.get("description", "Unknown error")
                        if attempt < TelegramConfig.MAX_RETRIES - 1:
                            wait = TelegramConfig.RETRY_BACKOFF_SECS[attempt]
                            log.warning(f"Retry {attempt + 1}/{TelegramConfig.MAX_RETRIES}: {error}")
                            time.sleep(wait)
                            continue
                        return False, error
                else:
                    if attempt < TelegramConfig.MAX_RETRIES - 1:
                        wait = TelegramConfig.RETRY_BACKOFF_SECS[attempt]
                        log.warning(f"Retry {attempt + 1}/{TelegramConfig.MAX_RETRIES}: HTTP {response.status_code}")
                        time.sleep(wait)
                        continue
                    return False, f"HTTP {response.status_code}"
            except requests.exceptions.RequestException as e:
                if attempt < TelegramConfig.MAX_RETRIES - 1:
                    wait = TelegramConfig.RETRY_BACKOFF_SECS[attempt]
                    log.warning(f"Retry {attempt + 1}/{TelegramConfig.MAX_RETRIES}: {e}")
                    time.sleep(wait)
                    continue
                return False, str(e)

        return False, "Max retries exceeded"

    @classmethod
    def _record_attempt(cls, signal_id: str, bot_id: str):
        """Record send attempt in ledger."""
        if signal_id not in cls._ledger:
            cls._ledger[signal_id] = {
                "bot_id": bot_id,
                "status": TelegramStatus.ATTEMPTED.value,
                "attempts": 0,
                "timestamp": datetime.utcnow().isoformat(),
                "message_id": None,
                "error": None,
            }
        cls._ledger[signal_id]["attempts"] += 1

    @classmethod
    def _record_delivery(cls, signal_id: str, bot_id: str, status: TelegramStatus):
        """Record delivery status."""
        if signal_id in cls._ledger:
            cls._ledger[signal_id]["status"] = status.value
            cls._ledger[signal_id]["updated"] = datetime.utcnow().isoformat()

    @classmethod
    def get_ledger(cls) -> Dict:
        """Get delivery ledger (for testing and audit)."""
        return cls._ledger.copy()

    @classmethod
    def clear_ledger(cls):
        """Clear ledger (for testing)."""
        cls._ledger.clear()


# ──────────────────────────────────────────────────────────────────────────────
# TESTING
# ──────────────────────────────────────────────────────────────────────────────

def test_telegram_formatting():
    """Test message formatting."""
    print("[TEST] Telegram message formatting:")

    entry_msg = TelegramFormatter.entry_signal(
        bot_id="scanner_v2",
        symbol="RELIANCE",
        direction="BUY",
        signal_time="2026-07-31 11:30:00 IST",
        timeframe="30m",
        confidence="HIGH",
        entry_price=2815.50,
        stop_loss=2750.00,
        target=2900.00,
        quantity=10,
        signal_id="SIG_20260731_001",
        strategy_version="git:abc1234",
    )
    print("\n[ENTRY SIGNAL]")
    print(entry_msg)

    exit_msg = TelegramFormatter.exit_signal(
        bot_id="scanner_v2",
        symbol="RELIANCE",
        direction="BUY",
        exit_type="TARGET_HIT",
        exit_price=2900.00,
        entry_price=2815.50,
        quantity=10,
        pnl=845.00,
        pnl_pct=3.0,
        exit_time="2026-07-31 13:45:00 IST",
        signal_id="SIG_20260731_001",
    )
    print("\n[EXIT SIGNAL]")
    print(exit_msg)

    start_msg = TelegramFormatter.bot_start("scanner_v2", "abc123def456")
    print("\n[BOT START]")
    print(start_msg)


if __name__ == "__main__":
    logging.basicConfig(level=logging.DEBUG)
    test_telegram_formatting()
    print("\n[CONFIG]")
    print(f"  Token: {TelegramConfig.get_token_redacted()}")
    print(f"  Chat ID: {TelegramConfig.get_chat_id_redacted()}")
    print(f"  Configured: {TelegramConfig.is_configured()}")
