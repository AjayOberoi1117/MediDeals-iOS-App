"""
signal_bot.py — Telegram Forex Signal Bot
Strategy : EMA(9/21) crossover + RSI(14) on 1H bars
Data     : Yahoo Finance with 15-min caching + retry (avoids rate limits)
Signals  : Entry, Stop Loss, Take Profit (ATR-based), Risk/Reward
Report   : Daily summary at 10:00 PM IST
"""

import os
import time
import socket
import logging
from datetime import datetime

import pandas as pd
import yfinance as yf
import requests
from dotenv import load_dotenv
from telegram_config import validate_telegram_config, order_execution_enabled

try:
    from trade_executor import queue_trade
except ImportError:
    def queue_trade(*args, **kwargs): pass

load_dotenv()

socket.setdefaulttimeout(30)

# ── YF ticker map ──────────────────────────────────────────────────────────────

_YF_MAP = {
    "EURUSD": "EURUSD=X",
    "GBPUSD": "GBPUSD=X",
    "USDJPY": "USDJPY=X",
    "XAUUSD": "GC=F",
}

# ── Configuration ─────────────────────────────────────────────────────────────

SYMBOL_NAME    = os.getenv("SIGNAL_NAME",     "EURUSD")
TELEGRAM_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
CHAT_ID        = os.getenv("TELEGRAM_CHAT_ID", "")
FAST_EMA     = int(os.getenv("FAST_EMA",    "9"))
SLOW_EMA     = int(os.getenv("SLOW_EMA",    "21"))
RSI_PERIOD   = int(os.getenv("RSI_PERIOD",  "14"))
RSI_BUY_MAX  = int(os.getenv("RSI_BUY_MAX", "65"))
RSI_SELL_MIN = int(os.getenv("RSI_SELL_MIN","35"))
ATR_PERIOD   = 14
ATR_SL_MULT  = 1.0
ATR_TP_MULT  = 3.0
CHECK_SECS   = int(os.getenv("CHECK_SECS",  "60"))

YF_TICKER    = _YF_MAP.get(SYMBOL_NAME, SYMBOL_NAME + "=X")
CACHE_TTL    = 840   # re-fetch after 14 min — just before a new 1H bar closes

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    format=f"%(asctime)s | {SYMBOL_NAME:<8s} | %(levelname)s | %(message)s",
    level=logging.INFO,
)
log = logging.getLogger(__name__)

# ── State ─────────────────────────────────────────────────────────────────────

_seen_bars        = set()
_daily_signals    = []
_report_sent_date = None
_cache            = {}   # {ticker: (fetched_ts, dataframe)}

def _load_seen_bars():
    path = os.path.join(os.path.dirname(__file__), f".seen_{SYMBOL_NAME}")
    try:
        with open(path) as f:
            for line in f:
                _seen_bars.add(line.strip())
    except FileNotFoundError:
        pass

def _save_seen_bar(bar_ts):
    path = os.path.join(os.path.dirname(__file__), f".seen_{SYMBOL_NAME}")
    with open(path, "a") as f:
        f.write(bar_ts + "\n")

# ── Telegram ──────────────────────────────────────────────────────────────────

def tg_send(text: str) -> None:
    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
    try:
        r = requests.post(url,
                          data={"chat_id": CHAT_ID, "text": text, "parse_mode": "HTML"},
                          timeout=10)
        if not r.json().get("ok"):
            log.warning("Telegram send failed: %s", r.text[:120])
    except Exception as exc:
        log.warning("Telegram error: %s", exc)

# ── Daily report ──────────────────────────────────────────────────────────────

def record_signal(direction, price, sl, tp):
    _daily_signals.append({
        "direction": direction,
        "price":     price,
        "sl":        sl,
        "tp":        tp,
        "time":      datetime.now().strftime("%I:%M %p"),
    })

def send_daily_report():
    today = datetime.now().strftime("%d %b %Y")
    n     = len(_daily_signals)
    dec   = 3 if "JPY" in SYMBOL_NAME else 5
    lines = [
        f"[SIGNAL BOT] 📊 <b>Daily Signal Report — {today}</b>",
        "━━━━━━━━━━━━━━━━━━━━━━",
        f"<b>{SYMBOL_NAME}</b>  |  Signals Today: <b>{n}</b>",
        "",
    ]
    if n == 0:
        lines.append("No signals were generated today.")
    else:
        for i, s in enumerate(_daily_signals, 1):
            em = "🟢" if s["direction"] == "BUY" else "🔴"
            rr = round(abs(s["tp"] - s["price"]) / max(abs(s["sl"] - s["price"]), 0.0001), 1)
            lines.append(
                f"{i}. {em} <b>{SYMBOL_NAME}</b> {s['direction']}  @  {s['time']}\n"
                f"   Entry {s['price']:.{dec}f}  •  SL {s['sl']:.{dec}f}  •  TP {s['tp']:.{dec}f}  •  RR 1:{rr}"
            )
    lines += ["", "━━━━━━━━━━━━━━━━━━━━━━", "📌 <i>Check your broker for actual P&amp;L</i>"]
    tg_send("\n".join(lines))
    log.info("Daily report sent — %d signals", n)

def maybe_send_daily_report():
    global _report_sent_date, _daily_signals
    now   = datetime.now()
    today = now.date()
    if now.hour == 22 and now.minute < 2 and _report_sent_date != today:
        _report_sent_date = today
        send_daily_report()
    if now.hour == 0 and now.minute < 2 and _daily_signals:
        _daily_signals.clear()

# ── Indicators ────────────────────────────────────────────────────────────────

def calc_rsi(close, period):
    delta    = close.diff()
    avg_gain = delta.clip(lower=0).ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    avg_loss = (-delta.clip(upper=0)).ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    return 100 - 100 / (1 + avg_gain / avg_loss)

def calc_atr(high, low, close, period):
    prev_close = close.shift(1)
    tr = pd.concat([high-low, (high-prev_close).abs(), (low-prev_close).abs()], axis=1).max(axis=1)
    return tr.ewm(span=period, adjust=False).mean()

# ── Data fetch with caching + retry ──────────────────────────────────────────

def _yf_download(ticker, period, interval):
    for attempt in range(3):
        try:
            df = yf.download(ticker, period=period, interval=interval,
                             progress=False, auto_adjust=True)
            if df is not None and not df.empty:
                return df
        except Exception as exc:
            log.warning("yfinance attempt %d failed: %s", attempt + 1, exc)
        if attempt < 2:
            time.sleep(5 * (2 ** attempt))   # 5s, 10s backoff
    return None

def fetch_ohlcv():
    now = time.time()
    cached = _cache.get("1h")
    if cached and now - cached[0] < CACHE_TTL:
        return cached[1]
    df = _yf_download(YF_TICKER, "30d", "1h")
    if df is None or len(df) < SLOW_EMA + 10:
        log.warning("Not enough bars. Will retry.")
        return None
    if isinstance(df.columns, pd.MultiIndex):
        df.columns = [col[0] for col in df.columns]
    _cache["1h"] = (now, df)
    log.info("Fetched %d 1H bars for %s", len(df), SYMBOL_NAME)
    return df

def get_daily_trend() -> int:
    now = time.time()
    cached = _cache.get("1d")
    if cached and now - cached[0] < 3600:   # cache daily trend for 1 hour
        return cached[1]
    df = _yf_download(YF_TICKER, "3mo", "1d")
    if df is None or len(df) < 22:
        return 0
    if isinstance(df.columns, pd.MultiIndex):
        df.columns = [col[0] for col in df.columns]
    close = df["Close"].squeeze()
    ema20 = close.ewm(span=20, adjust=False).mean()
    trend = 1 if float(close.iloc[-1]) > float(ema20.iloc[-1]) else -1
    _cache["1d"] = (now, trend)
    return trend

# ── Signal check ──────────────────────────────────────────────────────────────

def check_signal() -> None:
    df = fetch_ohlcv()
    if df is None:
        return

    close = df["Close"].squeeze()
    if isinstance(close, pd.DataFrame): close = close.iloc[:, 0]
    high  = df["High"].squeeze()
    low   = df["Low"].squeeze()
    if isinstance(high, pd.DataFrame): high = high.iloc[:, 0]
    if isinstance(low,  pd.DataFrame): low  = low.iloc[:,  0]
    close = close.dropna()

    fast_ema = close.ewm(span=FAST_EMA, adjust=False).mean()
    slow_ema = close.ewm(span=SLOW_EMA, adjust=False).mean()
    rsi      = calc_rsi(close, RSI_PERIOD)
    atr      = calc_atr(high, low, close, ATR_PERIOD)

    i      = -2
    bar_ts = str(df.index[i])
    if bar_ts in _seen_bars:
        return

    bull_cross = (fast_ema.iloc[i] > slow_ema.iloc[i]) and (fast_ema.iloc[i-1] <= slow_ema.iloc[i-1])
    bear_cross = (fast_ema.iloc[i] < slow_ema.iloc[i]) and (fast_ema.iloc[i-1] >= slow_ema.iloc[i-1])

    rsi_val = float(rsi.iloc[i])
    price   = float(close.iloc[i])
    atr_val = float(atr.iloc[i])

    _atr_min = {"EURUSD": 0.00150, "GBPUSD": 0.00180, "USDJPY": 0.20, "XAUUSD": 3.0}
    atr_val = max(atr_val, _atr_min.get(SYMBOL_NAME, atr_val))

    _seen_bars.add(bar_ts)
    _save_seen_bar(bar_ts)
    if len(_seen_bars) > 1000:
        _seen_bars.clear()

    log.info("Bar %s  price=%.5f  fast=%.5f  slow=%.5f  rsi=%.1f  atr=%.5f  bull=%s  bear=%s",
             bar_ts, price, float(fast_ema.iloc[i]), float(slow_ema.iloc[i]),
             rsi_val, atr_val, bull_cross, bear_cross)

    dec = 3 if "JPY" in SYMBOL_NAME else 5
    rr  = round(ATR_TP_MULT / ATR_SL_MULT, 1)

    if bull_cross and rsi_val < RSI_BUY_MAX:
        if get_daily_trend() == -1:
            log.info("SKIP BUY — daily trend bearish")
            return
        entry = round(price, dec)
        sl = round(entry - ATR_SL_MULT * atr_val, dec)
        tp = round(entry + ATR_TP_MULT * atr_val, dec)
        log.info(">>> BUY SIGNAL <<<  Entry=%.*f  SL=%.*f  TP=%.*f", dec, entry, dec, sl, dec, tp)
        tg_send(
            f"━━━━━━━━━━━━━━━━━━━━━━\n"
            f"💱 <b>FOREX SIGNAL — {SYMBOL_NAME}</b>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━\n\n"
            f"📈 <b>Signal    :</b> 🟢 BUY\n"
            f"📅 <b>Time      :</b> {datetime.now().strftime('%d %b %Y %I:%M %p IST')}\n"
            f"⏱ <b>Timeframe :</b> 1 Hour\n\n"
            f"📍 <b>Entry     :</b> <code>{entry:.{dec}f}</code>\n"
            f"🛑 <b>Stop Loss :</b> <code>{sl:.{dec}f}</code>\n"
            f"🎯 <b>Target    :</b> <code>{tp:.{dec}f}</code>\n\n"
            f"📊 <b>RSI(14)   :</b> {rsi_val:.1f}\n"
            f"📊 <b>ATR(14)   :</b> {atr_val:.{dec}f}\n"
            f"⚖️ <b>Risk/Reward:</b> 1 : {rr}\n\n"
            f"💡 EMA({FAST_EMA}/{SLOW_EMA}) bullish cross confirmed\n"
            f"⚠️ <i>Set SL immediately after opening the trade!</i>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━"
        )
        record_signal("BUY", entry, sl, tp)
        if order_execution_enabled():
            queue_trade(SYMBOL_NAME, "BUY", sl, tp, source=f"{SYMBOL_NAME}_1H")

    elif bear_cross and rsi_val > RSI_SELL_MIN:
        if get_daily_trend() == 1:
            log.info("SKIP SELL — daily trend bullish")
            return
        entry = round(price, dec)
        sl = round(entry + ATR_SL_MULT * atr_val, dec)
        tp = round(entry - ATR_TP_MULT * atr_val, dec)
        log.info(">>> SELL SIGNAL <<<  Entry=%.*f  SL=%.*f  TP=%.*f", dec, entry, dec, sl, dec, tp)
        tg_send(
            f"━━━━━━━━━━━━━━━━━━━━━━\n"
            f"💱 <b>FOREX SIGNAL — {SYMBOL_NAME}</b>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━\n\n"
            f"📉 <b>Signal    :</b> 🔴 SELL\n"
            f"📅 <b>Time      :</b> {datetime.now().strftime('%d %b %Y %I:%M %p IST')}\n"
            f"⏱ <b>Timeframe :</b> 1 Hour\n\n"
            f"📍 <b>Entry     :</b> <code>{entry:.{dec}f}</code>\n"
            f"🛑 <b>Stop Loss :</b> <code>{sl:.{dec}f}</code>\n"
            f"🎯 <b>Target    :</b> <code>{tp:.{dec}f}</code>\n\n"
            f"📊 <b>RSI(14)   :</b> {rsi_val:.1f}\n"
            f"📊 <b>ATR(14)   :</b> {atr_val:.{dec}f}\n"
            f"⚖️ <b>Risk/Reward:</b> 1 : {rr}\n\n"
            f"💡 EMA({FAST_EMA}/{SLOW_EMA}) bearish cross confirmed\n"
            f"⚠️ <i>Set SL immediately after opening the trade!</i>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━"
        )
        record_signal("SELL", entry, sl, tp)
        if order_execution_enabled():
            queue_trade(SYMBOL_NAME, "SELL", sl, tp, source=f"{SYMBOL_NAME}_1H")

# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    raise SystemExit(
        "SIGNAL BOT DISABLED: ownership consolidated into dedicated market bots."
    )

if __name__ == "__main__":
    main()
