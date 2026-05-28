"""
Telegram Currency Pairs Bot — MetaTrader 5 / Vantage

Commands:
  /start        — Welcome message
  /rate EURUSD  — Live rate for a symbol (e.g. EURUSD, XAUUSD)
  /pairs        — List common forex pairs
  /info EURUSD  — Bid/Ask/Spread/High/Low for a symbol
  /help         — Show available commands

Platforms:
  Windows      — uses MetaTrader5 package directly (set MT5_WINE_MODE=false)
  macOS + Wine — uses mt5linux bridge (set MT5_WINE_MODE=true, run wine_server.py inside Wine first)
"""

import os
import sys
import logging
import requests
from dotenv import load_dotenv
from telegram import Update
from telegram.ext import (
    Application,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    filters,
)

load_dotenv()

logging.basicConfig(
    format="%(asctime)s | %(levelname)s | %(message)s",
    level=logging.INFO,
)
logger = logging.getLogger(__name__)

# ─── Config ────────────────────────────────────────────────────────────────

ACTIVE_BOT = os.getenv("ACTIVE_BOT", "ELITE").upper()
if ACTIVE_BOT == "STOCX":
    BOT_TOKEN = os.getenv("STOCX_BOT_TOKEN")
    BOT_NAME = "Stocx"
else:
    BOT_TOKEN = os.getenv("ELITE_BOT_TOKEN")
    BOT_NAME = "Elite"

MT5_LOGIN    = int(os.getenv("MT5_LOGIN", "0"))
MT5_PASSWORD = os.getenv("MT5_PASSWORD", "")
MT5_SERVER   = os.getenv("MT5_SERVER", "Vantage-Live")
MT5_WINE_MODE = os.getenv("MT5_WINE_MODE", "false").lower() == "true"
MT5_HOST     = os.getenv("MT5_HOST", "localhost")
MT5_PORT     = int(os.getenv("MT5_PORT", "18812"))
FALLBACK_API_KEY = os.getenv("FALLBACK_API_KEY", "")

COMMON_PAIRS = [
    "EURUSD", "GBPUSD", "USDJPY", "USDCHF", "AUDUSD",
    "USDCAD", "NZDUSD", "EURGBP", "EURJPY", "GBPJPY",
    "XAUUSD", "XAGUSD", "US30", "US500", "BTCUSD",
]

# ─── MT5 module loader (Wine bridge or native) ──────────────────────────────

def _load_mt5():
    """
    Returns the mt5 module or None.
    - MT5_WINE_MODE=true  → mt5linux (macOS + Wine bridge)
    - MT5_WINE_MODE=false → MetaTrader5 (Windows native)
    """
    if MT5_WINE_MODE:
        try:
            from mt5linux import MetaTrader5
            return MetaTrader5(host=MT5_HOST, port=MT5_PORT)
        except ImportError:
            logger.error("mt5linux not installed. Run: pip install mt5linux")
            return None
        except Exception as exc:
            logger.warning("mt5linux load error: %s", exc)
            return None
    else:
        try:
            import MetaTrader5 as mt5
            return mt5
        except ImportError:
            logger.warning("MetaTrader5 package not available (Windows only)")
            return None


def _init_mt5(mt5) -> bool:
    try:
        if not mt5.initialize():
            logger.warning("MT5 initialize() failed: %s", mt5.last_error())
            return False
        if MT5_LOGIN and MT5_PASSWORD:
            ok = mt5.login(MT5_LOGIN, password=MT5_PASSWORD, server=MT5_SERVER)
            if not ok:
                logger.warning("MT5 login failed: %s", mt5.last_error())
                mt5.shutdown()
                return False
        return True
    except Exception as exc:
        logger.warning("MT5 init error: %s", exc)
        return False


def get_rate_mt5(symbol: str) -> dict | None:
    mt5 = _load_mt5()
    if mt5 is None:
        return None
    try:
        if not _init_mt5(mt5):
            return None
        tick = mt5.symbol_info_tick(symbol.upper())
        info = mt5.symbol_info(symbol.upper())
        mt5.shutdown()
        if tick is None:
            return None
        digits = info.digits if info else 5
        return {
            "symbol": symbol.upper(),
            "bid":    tick.bid,
            "ask":    tick.ask,
            "spread": round((tick.ask - tick.bid) * (10 ** digits), 1),
            "high":   info.session_high if info else None,
            "low":    info.session_low  if info else None,
            "source": f"MT5 / {MT5_SERVER}" + (" (Wine)" if MT5_WINE_MODE else ""),
        }
    except Exception as exc:
        logger.warning("MT5 rate error: %s", exc)
        return None


# ─── Fallback API (open.er-api.com) ─────────────────────────────────────────

def get_rate_fallback(symbol: str) -> dict | None:
    symbol = symbol.upper()
    if len(symbol) != 6:
        return None
    base, quote = symbol[:3], symbol[3:]
    try:
        if FALLBACK_API_KEY:
            url = f"https://v6.exchangerate-api.com/v6/{FALLBACK_API_KEY}/pair/{base}/{quote}"
        else:
            url = f"https://open.er-api.com/v6/latest/{base}"
        resp = requests.get(url, timeout=8)
        data = resp.json()
        if FALLBACK_API_KEY:
            rate = data.get("conversion_rate")
        else:
            rate = data.get("rates", {}).get(quote)
        if rate is None:
            return None
        return {
            "symbol": symbol,
            "bid":    round(rate * 0.9998, 5),
            "ask":    round(rate * 1.0002, 5),
            "spread": None,
            "high":   None,
            "low":    None,
            "source": "ExchangeRate-API (fallback)",
        }
    except Exception as exc:
        logger.warning("Fallback API error: %s", exc)
        return None


def get_rate(symbol: str) -> dict | None:
    return get_rate_mt5(symbol) or get_rate_fallback(symbol)


# ─── Telegram handlers ──────────────────────────────────────────────────────

async def cmd_start(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    mode = "MT5 via Wine bridge" if MT5_WINE_MODE else "MT5 native (Windows)"
    await update.message.reply_text(
        f"*{BOT_NAME} Forex Bot*\n\n"
        f"Live currency pair rates — {mode}.\n\n"
        "Commands:\n"
        "  /rate EURUSD — mid price\n"
        "  /info EURUSD — bid/ask/spread/high/low\n"
        "  /pairs       — list common pairs\n"
        "  /help        — show this message",
        parse_mode="Markdown",
    )


async def cmd_help(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    await cmd_start(update, ctx)


async def cmd_pairs(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    lines = ["*Common Forex Pairs:*", ""] + [f"• `{p}`" for p in COMMON_PAIRS]
    lines += ["", "Use /rate SYMBOL or /info SYMBOL"]
    await update.message.reply_text("\n".join(lines), parse_mode="Markdown")


async def cmd_rate(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not ctx.args:
        await update.message.reply_text("Usage: /rate EURUSD")
        return
    symbol = ctx.args[0].upper()
    await update.message.reply_text(f"Fetching {symbol}…")
    data = get_rate(symbol)
    if not data:
        await update.message.reply_text(
            f"Could not fetch `{symbol}`.\n"
            "Check the symbol name or verify MT5/Wine is running.\n"
            "Try /pairs for common symbols.",
            parse_mode="Markdown",
        )
        return
    mid = round((data["bid"] + data["ask"]) / 2, 5)
    await update.message.reply_text(
        f"*{data['symbol']}*\n"
        f"  Price : `{mid}`\n"
        f"  Source: {data['source']}",
        parse_mode="Markdown",
    )


async def cmd_info(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not ctx.args:
        await update.message.reply_text("Usage: /info EURUSD")
        return
    symbol = ctx.args[0].upper()
    await update.message.reply_text(f"Fetching {symbol} details…")
    data = get_rate(symbol)
    if not data:
        await update.message.reply_text(
            f"Could not fetch `{symbol}`.\n"
            "Check the symbol name or verify MT5/Wine is running.",
            parse_mode="Markdown",
        )
        return
    spread_str = f"`{data['spread']} pts`" if data["spread"] is not None else "_n/a_"
    high_str   = f"`{data['high']}`"        if data["high"]   else "_n/a_"
    low_str    = f"`{data['low']}`"         if data["low"]    else "_n/a_"
    await update.message.reply_text(
        f"*{data['symbol']}* — Full Quote\n"
        f"  Bid    : `{data['bid']}`\n"
        f"  Ask    : `{data['ask']}`\n"
        f"  Spread : {spread_str}\n"
        f"  High   : {high_str}\n"
        f"  Low    : {low_str}\n"
        f"  Source : {data['source']}",
        parse_mode="Markdown",
    )


async def unknown(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text("Unknown command. Try /help")


# ─── Entry point ────────────────────────────────────────────────────────────

def main() -> None:
    if not BOT_TOKEN:
        raise ValueError("Bot token not set. Check .env → ELITE_BOT_TOKEN or STOCX_BOT_TOKEN")

    mode_label = f"Wine bridge ({MT5_HOST}:{MT5_PORT})" if MT5_WINE_MODE else "Windows native"
    logger.info("Starting %s bot | MT5 mode: %s", BOT_NAME, mode_label)

    app = Application.builder().token(BOT_TOKEN).build()
    app.add_handler(CommandHandler("start",  cmd_start))
    app.add_handler(CommandHandler("help",   cmd_help))
    app.add_handler(CommandHandler("pairs",  cmd_pairs))
    app.add_handler(CommandHandler("rate",   cmd_rate))
    app.add_handler(CommandHandler("info",   cmd_info))
    app.add_handler(MessageHandler(filters.COMMAND, unknown))

    logger.info("Bot polling…")
    app.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    main()
