"""
signal_bot.py — Telegram Trading Signal Bot  (No MT5 required)

Monitors one forex/commodity symbol for EMA crossover + RSI signals.
Uses Yahoo Finance for free OHLCV data — no API key needed.

Each of the four bots runs as a separate terminal process watching
one symbol.  The easiest way to start all four at once:

    bash start_bots.sh

To start a single bot manually:
    SIGNAL_SYMBOL=EURUSD=X  SIGNAL_NAME=EURUSD  SIGNAL_TOKEN=<token>  python signal_bot.py

Environment variables (all can also live in .env):
    SIGNAL_SYMBOL    Yahoo Finance ticker  (default: EURUSD=X)
    SIGNAL_NAME      Human-readable name   (default: same as SIGNAL_SYMBOL)
    SIGNAL_TOKEN     Telegram bot token    (default: ELITE_BOT_TOKEN from .env)
    SIGNAL_CHAT_ID   Telegram chat ID      (default: 1994067941)
    SIGNAL_TF        Yahoo interval        (default: 1h)
    FAST_EMA         Fast EMA period       (default: 10)
    SLOW_EMA         Slow EMA period       (default: 50)
    RSI_PERIOD       RSI period            (default: 14)
    RSI_BUY_MAX      RSI upper limit buy   (default: 65)
    RSI_SELL_MIN     RSI lower limit sell  (default: 35)
    CHECK_SECS       Seconds between polls (default: 60)
"""

import os
import time
import logging

import pandas as pd
import yfinance as yf
import requests
from dotenv import load_dotenv

load_dotenv()

# ── Configuration ─────────────────────────────────────────────────────────────

SYMBOL      = os.getenv("SIGNAL_SYMBOL",   "EURUSD=X")
SYMBOL_NAME = os.getenv("SIGNAL_NAME",     SYMBOL)
BOT_TOKEN   = os.getenv("SIGNAL_TOKEN",    os.getenv("ELITE_BOT_TOKEN", ""))
CHAT_ID     = os.getenv("SIGNAL_CHAT_ID",  "1994067941")
TIMEFRAME   = os.getenv("SIGNAL_TF",       "1h")
FAST_EMA    = int(os.getenv("FAST_EMA",    "10"))
SLOW_EMA    = int(os.getenv("SLOW_EMA",    "50"))
RSI_PERIOD  = int(os.getenv("RSI_PERIOD",  "14"))
RSI_BUY_MAX = int(os.getenv("RSI_BUY_MAX", "65"))
RSI_SELL_MIN= int(os.getenv("RSI_SELL_MIN","35"))
CHECK_SECS  = int(os.getenv("CHECK_SECS",  "60"))

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    format=f"%(asctime)s | {SYMBOL_NAME:<8s} | %(levelname)s | %(message)s",
    level=logging.INFO,
)
log = logging.getLogger(__name__)

# ── State ─────────────────────────────────────────────────────────────────────

_seen_bars: set = set()   # bar timestamps already processed

# ── Telegram helper ───────────────────────────────────────────────────────────

def tg_send(text: str) -> None:
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    try:
        r = requests.post(url, data={"chat_id": CHAT_ID, "text": text}, timeout=10)
        if not r.json().get("ok"):
            log.warning("Telegram send failed: %s", r.text[:120])
    except Exception as exc:
        log.warning("Telegram error: %s", exc)

# ── Indicators ────────────────────────────────────────────────────────────────

def calc_rsi(close: pd.Series, period: int) -> pd.Series:
    """Wilder RSI — matches MetaTrader 5 calculation."""
    delta    = close.diff()
    avg_gain = delta.clip(lower=0).ewm(alpha=1 / period, min_periods=period, adjust=False).mean()
    avg_loss = (-delta.clip(upper=0)).ewm(alpha=1 / period, min_periods=period, adjust=False).mean()
    return 100 - 100 / (1 + avg_gain / avg_loss)

# ── Data fetch ────────────────────────────────────────────────────────────────

def fetch_ohlcv() -> pd.DataFrame | None:
    min_bars = SLOW_EMA + 10
    try:
        df = yf.download(SYMBOL, period="30d", interval=TIMEFRAME,
                         progress=False, auto_adjust=True)
        if df.empty:
            log.warning("Empty dataframe returned for %s", SYMBOL)
            return None
        if len(df) < min_bars:
            log.warning("Only %d bars — need at least %d. Will retry.", len(df), min_bars)
            return None
        return df
    except Exception as exc:
        log.warning("Data fetch error: %s", exc)
        return None

# ── Signal check ──────────────────────────────────────────────────────────────

def check_signal() -> None:
    df = fetch_ohlcv()
    if df is None:
        return

    close = df["Close"].squeeze()   # works whether columns are simple or MultiIndex
    if isinstance(close, pd.DataFrame):
        close = close.iloc[:, 0]
    close = close.dropna()

    fast_ema = close.ewm(span=FAST_EMA, adjust=False).mean()
    slow_ema = close.ewm(span=SLOW_EMA, adjust=False).mean()
    rsi      = calc_rsi(close, RSI_PERIOD)

    # Use last fully CLOSED bar (index -2; bar -1 is still forming)
    i      = -2
    bar_ts = str(df.index[i])

    if bar_ts in _seen_bars:
        return

    bull_cross = (fast_ema.iloc[i]   > slow_ema.iloc[i]  ) and \
                 (fast_ema.iloc[i-1] <= slow_ema.iloc[i-1])
    bear_cross = (fast_ema.iloc[i]   < slow_ema.iloc[i]  ) and \
                 (fast_ema.iloc[i-1] >= slow_ema.iloc[i-1])

    rsi_val = float(rsi.iloc[i])
    price   = float(close.iloc[i])

    _seen_bars.add(bar_ts)
    if len(_seen_bars) > 1000:
        _seen_bars.clear()

    log.info("Bar %s  price=%.5f  fast=%.5f  slow=%.5f  rsi=%.1f  bull=%s  bear=%s",
             bar_ts, price,
             float(fast_ema.iloc[i]), float(slow_ema.iloc[i]),
             rsi_val, bull_cross, bear_cross)

    if bull_cross and rsi_val < RSI_BUY_MAX:
        log.info(">>> BUY SIGNAL <<<")
        tg_send(
            f"[BUY]  {SYMBOL_NAME}\n"
            f"  Price : {price:.5f}\n"
            f"  RSI   : {rsi_val:.1f}\n"
            f"  Bar   : {bar_ts}\n"
            f"  Signal: EMA({FAST_EMA}/{SLOW_EMA}) bullish cross\n"
            f"  TF    : {TIMEFRAME}"
        )
    elif bear_cross and rsi_val > RSI_SELL_MIN:
        log.info(">>> SELL SIGNAL <<<")
        tg_send(
            f"[SELL] {SYMBOL_NAME}\n"
            f"  Price : {price:.5f}\n"
            f"  RSI   : {rsi_val:.1f}\n"
            f"  Bar   : {bar_ts}\n"
            f"  Signal: EMA({FAST_EMA}/{SLOW_EMA}) bearish cross\n"
            f"  TF    : {TIMEFRAME}"
        )

# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    if not BOT_TOKEN:
        raise SystemExit(
            "Bot token not set.\n"
            "Set SIGNAL_TOKEN as an env var, or check ELITE_BOT_TOKEN in .env"
        )

    log.info("Starting | symbol=%s  tf=%s  ema=%d/%d  rsi=%d  poll=%ds",
             SYMBOL_NAME, TIMEFRAME, FAST_EMA, SLOW_EMA, RSI_PERIOD, CHECK_SECS)

    tg_send(
        f"Signal Bot Online\n"
        f"  Symbol : {SYMBOL_NAME}  ({SYMBOL})\n"
        f"  EMA    : {FAST_EMA}/{SLOW_EMA}\n"
        f"  RSI    : {RSI_PERIOD}  (buy <{RSI_BUY_MAX}, sell >{RSI_SELL_MIN})\n"
        f"  TF     : {TIMEFRAME}\n"
        f"  Poll   : every {CHECK_SECS}s"
    )

    while True:
        try:
            check_signal()
        except Exception as exc:
            log.error("Unexpected error: %s", exc)
        time.sleep(CHECK_SECS)


if __name__ == "__main__":
    main()
