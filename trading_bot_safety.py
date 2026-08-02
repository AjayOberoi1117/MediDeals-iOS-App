"""
CENTRAL DEMO-MODE ENFORCEMENT LAYER
=====================================

Prevents ALL trading bots from placing real broker orders.
All bots must pass through this layer.

Safety Model:
- TRADING_MODE defaults to PAPER
- Missing config defaults to PAPER, never LIVE
- Live mode requires explicit multi-step approval (not implemented)
- All broker order methods are blocked when PAPER mode is active
- All simulated orders are clearly marked PAPER

Usage:
    from trading_bot_safety import enforce_demo_mode, TradingMode

    # At bot startup
    mode = enforce_demo_mode()  # Returns: TradingMode.PAPER or TradingMode.LIVE

    # Before any order placement
    if mode == TradingMode.PAPER:
        # Simulate the trade locally instead of sending to broker
        record_simulated_trade(...)
    else:
        raise RuntimeError("Live trading not yet approved")
"""

import os
import logging
from enum import Enum
from typing import Dict, List

log = logging.getLogger(__name__)


class TradingMode(Enum):
    """Trading mode enumeration."""
    PAPER = "PAPER"
    LIVE = "LIVE"


# ──────────────────────────────────────────────────────────────────────────────
# CORE ENFORCEMENT LOGIC
# ──────────────────────────────────────────────────────────────────────────────

def enforce_demo_mode() -> TradingMode:
    """
    Enforce demo-mode globally.

    Priority (highest to lowest):
    1. Environment variable TRADING_MODE
    2. Environment variable LIVE_TRADING_ENABLED
    3. .env file TRADING_MODE
    4. DEFAULT: PAPER (safest)

    Returns:
        TradingMode: PAPER or LIVE

    Raises:
        RuntimeError: If live mode is enabled (not yet approved)
    """

    # Check environment variable first (highest priority)
    env_mode = os.environ.get("TRADING_MODE", "").upper().strip()
    if env_mode in ("PAPER", "LIVE"):
        mode = TradingMode[env_mode]
        log.info(f"Trading mode from TRADING_MODE env var: {mode.value}")
        return _validate_mode(mode)

    # Check live trading flag
    live_enabled = os.environ.get("LIVE_TRADING_ENABLED", "false").lower().strip()
    if live_enabled in ("true", "1", "yes"):
        log.warning("LIVE_TRADING_ENABLED=true but TRADING_MODE not set, defaulting to PAPER")

    # Default to PAPER (safest)
    log.info("Trading mode: PAPER (default)")
    return TradingMode.PAPER


def _validate_mode(mode: TradingMode) -> TradingMode:
    """
    Validate trading mode. Live mode is not yet approved.

    Args:
        mode: TradingMode to validate

    Returns:
        TradingMode: Validated mode

    Raises:
        RuntimeError: If live mode is requested
    """
    if mode == TradingMode.LIVE:
        log.error(
            "LIVE TRADING REQUESTED BUT NOT APPROVED\n"
            "Live trading requires explicit multi-step approval from Ajay.\n"
            "All bots must remain in PAPER mode during evaluation phase."
        )
        raise RuntimeError(
            "Live trading is not yet authorized. Set TRADING_MODE=PAPER or leave unset."
        )
    return mode


# ──────────────────────────────────────────────────────────────────────────────
# BROKER ORDER BLOCKING
# ──────────────────────────────────────────────────────────────────────────────

def block_upstox_orders(trading_mode: TradingMode) -> bool:
    """
    Check if Upstox orders should be blocked.

    Args:
        trading_mode: Current trading mode

    Returns:
        bool: True if orders should be blocked (PAPER mode)
    """
    if trading_mode == TradingMode.PAPER:
        log.debug("Upstox orders blocked (PAPER mode)")
        return True
    log.warning("Upstox orders ENABLED (LIVE mode)")
    return False


def block_metatrader_orders(trading_mode: TradingMode) -> bool:
    """
    Check if MetaTrader orders should be blocked.

    Args:
        trading_mode: Current trading mode

    Returns:
        bool: True if orders should be blocked (PAPER mode)
    """
    if trading_mode == TradingMode.PAPER:
        log.debug("MetaTrader orders blocked (PAPER mode)")
        return True
    log.warning("MetaTrader orders ENABLED (LIVE mode)")
    return False


def block_all_broker_orders(trading_mode: TradingMode) -> bool:
    """
    Check if all broker orders should be blocked.

    Args:
        trading_mode: Current trading mode

    Returns:
        bool: True if orders should be blocked (PAPER mode)
    """
    return trading_mode == TradingMode.PAPER


# ──────────────────────────────────────────────────────────────────────────────
# PAPER-TRADING LABEL GENERATION
# ──────────────────────────────────────────────────────────────────────────────

def get_paper_trading_label(bot_name: str, trading_mode: TradingMode) -> str:
    """
    Generate paper-trading label for alerts and logs.

    Args:
        bot_name: Name of the bot
        trading_mode: Current trading mode

    Returns:
        str: Formatted label

    Example:
        "[PAPER][EQUITY-SCANNER-V2]" or "[LIVE][EQUITY-SCANNER-V2]"
    """
    mode_label = trading_mode.value
    return f"[{mode_label}][{bot_name}]"


def get_simulated_trade_marker() -> str:
    """
    Get marker for simulated trades.

    Returns:
        str: Marker to include in all Telegram alerts, logs, and ledger entries
    """
    return "PAPER TRADE — NOT SENT TO BROKER"


# ──────────────────────────────────────────────────────────────────────────────
# TESTING HELPERS
# ──────────────────────────────────────────────────────────────────────────────

def get_current_trading_mode() -> TradingMode:
    """
    Get current trading mode without validation.
    Used for testing and status checks.

    Returns:
        TradingMode: Current mode (may be LIVE if explicitly set)
    """
    env_mode = os.environ.get("TRADING_MODE", "").upper().strip()
    if env_mode == "LIVE":
        return TradingMode.LIVE
    return TradingMode.PAPER


def test_broker_order_blocking() -> Dict[str, bool]:
    """
    Test that broker order methods are properly blocked in PAPER mode.

    Returns:
        dict: {
            "upstox_blocked": bool,
            "metatrader_blocked": bool,
            "all_blocked": bool,
            "mode": str
        }
    """
    try:
        mode = enforce_demo_mode()
    except RuntimeError:
        # Live mode requested but not approved
        mode = TradingMode.PAPER

    return {
        "upstox_blocked": block_upstox_orders(mode),
        "metatrader_blocked": block_metatrader_orders(mode),
        "all_blocked": block_all_broker_orders(mode),
        "mode": mode.value,
    }


# ──────────────────────────────────────────────────────────────────────────────
# INITIALIZATION
# ──────────────────────────────────────────────────────────────────────────────

def init_demo_mode_enforcement():
    """
    Initialize demo-mode enforcement at application startup.
    Should be called before any bot starts.
    """
    log.info("=" * 80)
    log.info("DEMO-MODE ENFORCEMENT LAYER INITIALIZED")
    log.info("=" * 80)

    try:
        mode = enforce_demo_mode()
        log.info(f"Trading mode: {mode.value}")
        log.info(f"Upstox orders blocked: {block_upstox_orders(mode)}")
        log.info(f"MetaTrader orders blocked: {block_metatrader_orders(mode)}")
        log.info(f"All broker orders blocked: {block_all_broker_orders(mode)}")
        log.info("=" * 80)
        return mode
    except RuntimeError as e:
        log.error(f"Fatal: {e}")
        raise


if __name__ == "__main__":
    # Test enforcement
    logging.basicConfig(level=logging.INFO)

    print("\n[TEST] Current trading mode enforcement:")
    result = test_broker_order_blocking()
    for k, v in result.items():
        print(f"  {k}: {v}")

    print("\n[TEST] Initialization:")
    try:
        mode = init_demo_mode_enforcement()
        print(f"✓ Demo mode initialized successfully: {mode.value}")
    except RuntimeError as e:
        print(f"✗ {e}")
