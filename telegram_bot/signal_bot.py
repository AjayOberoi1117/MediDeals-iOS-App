"""
signal_bot.py — Telegram Forex Signal Bot
Strategy : EMA(10/50) crossover + RSI(14) on 1H bars
Data     : Yahoo Finance — no API key needed
Signals  : Entry, Stop Loss, Take Profit (ATR-based), Risk/Reward
Report   : Daily summary at 10:00 PM IST
"""

import os
import time
import logging
from datetime import datetime

import pandas as pd
import yfinance as yf
import requests
from dotenv import load_dotenv

load_dotenv()

# ── Configuration ─────────────────────────────────────────────────────────────

SYMBOL       = os.getenv("SIGNAL_SYMBOL",   "EURUSD=X")
SYMBOL_NAME  = os.getenv("SIGNAL_NAME",     SYMBOL)
BOT_TOKEN    = os.getenv("SIGNAL_TOKEN",    os.getenv("ELITE_BOT_TOKEN", ""))
CHAT_ID      = os.getenv("SIGNAL_CHAT_ID",  "1994067941")
TIMEFRAME    = os.getenv("SIGNAL_TF",       "1h")
FAST_EMA     = int(os.getenv("FAST_EMA",    "10"))
SLOW_EMA     = int(os.getenv("SLOW_EMA",    "50"))
RSI_PERIOD   = int(os.getenv("RSI_PERIOD",  "14"))
RSI_BUY_MAX  = int(os.getenv("RSI_BUY_MAX", "65"))
RSI_SELL_MIN = int(os.getenv("RSI_SELL_MIN","35"))
ATR_PERIOD   = 14
ATR_SL_MULT  = 1.0
ATR_TP_MULT  = 2.0
CHECK_SECS   = int(os.getenv("CHECK_SECS",  "60"))
TWELVE_DATA_KEY = os.getenv("TWELVE_DATA_KEY", "")

_TD_MAP = {"EURUSD": "EUR/USD", "GBPUSD": "GBP/USD", "USDJPY": "USD/JPY", "XAUUSD": "XAU/USD"}

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
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
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
    lines = [
        f"📊 <b>Daily Signal Report — {today}</b>",
        "━━━━━━━━━━━━━━━━━━━━━━",
        f"<b>{SYMBOL_NAME} Bot</b>  |  Signals Today: <b>{n}</b>",
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
                f"   Entry {s['price']:.5f}  •  SL {s['sl']:.5f}  •  TP {s['tp']:.5f}  •  RR 1:{rr}"
            )
    lines += [
        "",
        "━━━━━━━━━━━━━━━━━━━━━━",
        "📌 <i>Check your broker for actual P&amp;L</i>",
    ]
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

def calc_rsi(close: pd.Series, period: int) -> pd.Series:
    delta    = close.diff()
    avg_gain = delta.clip(lower=0).ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    avg_loss = (-delta.clip(upper=0)).ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    return 100 - 100 / (1 + avg_gain / avg_loss)

def calc_atr(high: pd.Series, low: pd.Series, close: pd.Series, period: int) -> pd.Series:
    prev_close = close.shift(1)
    tr = pd.concat([
        high - low,
        (high - prev_close).abs(),
        (low  - prev_close).abs(),
    ], axis=1).max(axis=1)
    return tr.ewm(span=period, adjust=False).mean()

# ── Data fetch ────────────────────────────────────────────────────────────────

def fetch_ohlcv():
    try:
        df = yf.download(SYMBOL, period="30d", interval=TIMEFRAME,
                         progress=False, auto_adjust=True)
        if df.empty or len(df) < SLOW_EMA + 10:
            log.warning("Not enough bars (%d). Will retry.", len(df))
            return None
        return df
    except Exception as exc:
        log.warning("Data fetch error: %s", exc)
        return None

# ── Live price (Twelve Data) ──────────────────────────────────────────────────

def fetch_live_price():
    td_sym = _TD_MAP.get(SYMBOL_NAME)
    if not TWELVE_DATA_KEY or not td_sym:
        return None
    try:
        r = requests.get("https://api.twelvedata.com/price",
                         params={"symbol": td_sym, "apikey": TWELVE_DATA_KEY},
                         timeout=5)
        val = float(r.json().get("price", 0))
        return val if val > 0 else None
    except Exception:
        return None

# ── Signal check ──────────────────────────────────────────────────────────────

def check_signal() -> None:
    df = fetch_ohlcv()
    if df is None:
        return

    close = df["Close"].squeeze()
    if isinstance(close, pd.DataFrame):
        close = close.iloc[:, 0]
    high = df["High"].squeeze()
    if isinstance(high, pd.DataFrame):
        high = high.iloc[:, 0]
    low = df["Low"].squeeze()
    if isinstance(low, pd.DataFrame):
        low = low.iloc[:, 0]
    close = close.dropna()

    fast_ema = close.ewm(span=FAST_EMA, adjust=False).mean()
    slow_ema = close.ewm(span=SLOW_EMA, adjust=False).mean()
    rsi      = calc_rsi(close, RSI_PERIOD)
    atr      = calc_atr(high, low, close, ATR_PERIOD)

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
    atr_val = float(atr.iloc[i])

    _seen_bars.add(bar_ts)
    _save_seen_bar(bar_ts)
    if len(_seen_bars) > 1000:
        _seen_bars.clear()

    log.info("Bar %s  price=%.5f  fast=%.5f  slow=%.5f  rsi=%.1f  atr=%.5f  bull=%s  bear=%s",
             bar_ts, price,
             float(fast_ema.iloc[i]), float(slow_ema.iloc[i]),
             rsi_val, atr_val, bull_cross, bear_cross)

    dec = 3 if "JPY" in SYMBOL_NAME else 5
    rr  = round(ATR_TP_MULT / ATR_SL_MULT, 1)

    if bull_cross and rsi_val < RSI_BUY_MAX:
        entry = fetch_live_price() or price
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

    elif bear_cross and rsi_val > RSI_SELL_MIN:
        entry = fetch_live_price() or price
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

# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    if not BOT_TOKEN:
        raise SystemExit("Bot token not set. Check SIGNAL_TOKEN or ELITE_BOT_TOKEN in .env")

    _load_seen_bars()
    log.info("Starting | symbol=%s  tf=%s  ema=%d/%d  rsi=%d  poll=%ds",
             SYMBOL_NAME, TIMEFRAME, FAST_EMA, SLOW_EMA, RSI_PERIOD, CHECK_SECS)

    tg_send(
        f"💱 <b>{SYMBOL_NAME} Signal Bot Online</b>\n"
        f"📅 {datetime.now().strftime('%d %b %Y %I:%M %p IST')}\n"
        f"📊 EMA({FAST_EMA}/{SLOW_EMA}) + RSI({RSI_PERIOD}) | 1H\n"
        f"⚖️ SL = 1x ATR  |  TP = 2x ATR\n"
        f"🕙 Daily report at 10:00 PM IST"
    )

    while True:
        try:
            maybe_send_daily_report()
            check_signal()
        except Exception as exc:
            log.error("Unexpected error: %s", exc)
        time.sleep(CHECK_SECS)


if __name__ == "__main__":
    main()
