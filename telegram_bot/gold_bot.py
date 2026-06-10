"""
Gold Trading Signal Bot — XAUUSD
Strategy : EMA(10/50) crossover + RSI(14) on 1-hour bars
Data     : Yahoo Finance  GC=F  (Gold Futures — no API key needed)
Signals  : Telegram via VantageEA bot with Entry, SL, TP
Report   : Daily P&L summary at 10:00 PM IST
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

# ── Config ────────────────────────────────────────────────────────────────────

TELEGRAM_TOKEN = os.getenv("VANTAGE_EA_TOKEN", "8034731398:AAHHAKJaYEn_u0M_TzwSJr8e7tNtQIwN5BM")
CHAT_ID        = os.getenv("SIGNAL_CHAT_ID",   "1994067941")
SYMBOL         = "XAUUSD=X"    # Yahoo Finance: Spot Gold (matches broker)
DISPLAY_NAME   = "XAUUSD"
TIMEFRAME      = "1h"
FAST_EMA       = 10
SLOW_EMA       = 50
RSI_PERIOD     = 14
RSI_BUY_MAX    = 65
RSI_SELL_MIN   = 35
ATR_PERIOD     = 14
ATR_SL_MULT    = 1.0    # SL = 1x ATR
ATR_TP_MULT    = 2.0    # TP = 2x ATR  (1:2 risk-reward)
CHECK_SECS     = 60

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    format="%(asctime)s | XAUUSD   | %(levelname)s | %(message)s",
    level=logging.INFO,
)
log = logging.getLogger(__name__)

# ── State ─────────────────────────────────────────────────────────────────────

_seen_bars        = set()
_daily_signals    = []
_report_sent_date = None

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
    lines = [
        f"📊 <b>Daily Signal Report — {today}</b>",
        "━━━━━━━━━━━━━━━━━━━━━━",
        f"<b>Gold Bot (XAUUSD)</b>  |  Signals Today: <b>{n}</b>",
        "",
    ]
    if n == 0:
        lines.append("No signals were generated today.")
    else:
        for i, s in enumerate(_daily_signals, 1):
            em = "🟢" if s["direction"] == "BUY" else "🔴"
            rr = round(abs(s["tp"] - s["price"]) / max(abs(s["sl"] - s["price"]), 0.01), 1)
            lines.append(
                f"{i}. {em} <b>XAUUSD</b> {s['direction']}  @  {s['time']}\n"
                f"   Entry ${s['price']:.2f}  •  SL ${s['sl']:.2f}  •  TP ${s['tp']:.2f}  •  RR 1:{rr}"
            )
    lines += [
        "",
        "━━━━━━━━━━━━━━━━━━━━━━",
        "📌 <i>Check your broker for actual P&amp;L</i>",
    ]
    tg_send("\n".join(lines))
    log.info("Daily report sent.")

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
        df = yf.download(SYMBOL, period="60d", interval=TIMEFRAME,
                         progress=False, auto_adjust=True)
        if df.empty or len(df) < SLOW_EMA + 10:
            log.warning("Not enough bars (%d). Will retry.", len(df))
            return None
        if isinstance(df.columns, pd.MultiIndex):
            df.columns = [col[0] for col in df.columns]
        return df
    except Exception as exc:
        log.warning("Data fetch error: %s", exc)
        return None

# ── Signal check ──────────────────────────────────────────────────────────────

def check_signal() -> None:
    df = fetch_ohlcv()
    if df is None:
        return

    close = df["Close"].squeeze()
    if isinstance(close, pd.DataFrame):
        close = close.iloc[:, 0]
    high  = df["High"].squeeze()
    low   = df["Low"].squeeze()
    if isinstance(high, pd.DataFrame):
        high = high.iloc[:, 0]
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
    if len(_seen_bars) > 500:
        _seen_bars.clear()

    log.info("Bar %s  price=$%.2f  fast=%.2f  slow=%.2f  rsi=%.1f  atr=%.2f  bull=%s  bear=%s",
             bar_ts, price,
             float(fast_ema.iloc[i]), float(slow_ema.iloc[i]),
             rsi_val, atr_val, bull_cross, bear_cross)

    sl_d = round(ATR_SL_MULT * atr_val, 2)
    tp_d = round(ATR_TP_MULT * atr_val, 2)
    rr   = round(ATR_TP_MULT / ATR_SL_MULT, 1)

    if bull_cross and rsi_val < RSI_BUY_MAX:
        log.info(">>> BUY SIGNAL <<<  Bar=$%.2f  SL=$%.2f  TP=$%.2f", price, sl_d, tp_d)
        tg_send(
            f"━━━━━━━━━━━━━━━━━━━━━━\n"
            f"🥇 <b>GOLD BOT — XAUUSD</b>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━\n\n"
            f"📈 <b>Signal    :</b> 🟢 BUY\n"
            f"📅 <b>Time      :</b> {datetime.now().strftime('%d %b %Y %I:%M %p IST')}\n"
            f"⏱ <b>Timeframe :</b> 1 Hour\n\n"
            f"📍 <b>Entry     :</b> Open BUY at your broker NOW\n"
            f"🛑 <b>Stop Loss :</b> $<code>{sl_d}</code> BELOW your entry\n"
            f"🎯 <b>Target    :</b> $<code>{tp_d}</code> ABOVE your entry\n\n"
            f"📊 <b>RSI(14)   :</b> {rsi_val:.1f}\n"
            f"📊 <b>ATR(14)   :</b> ${atr_val:.2f}\n"
            f"⚖️ <b>Risk/Reward:</b> 1 : {rr}\n\n"
            f"💡 EMA({FAST_EMA}/{SLOW_EMA}) bullish cross confirmed\n"
            f"⚠️ <i>Set SL immediately after opening the trade!</i>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━"
        )
        record_signal("BUY", price, round(price - sl_d, 2), round(price + tp_d, 2))

    elif bear_cross and rsi_val > RSI_SELL_MIN:
        log.info(">>> SELL SIGNAL <<<  Bar=$%.2f  SL=$%.2f  TP=$%.2f", price, sl_d, tp_d)
        tg_send(
            f"━━━━━━━━━━━━━━━━━━━━━━\n"
            f"🥇 <b>GOLD BOT — XAUUSD</b>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━\n\n"
            f"📉 <b>Signal    :</b> 🔴 SELL\n"
            f"📅 <b>Time      :</b> {datetime.now().strftime('%d %b %Y %I:%M %p IST')}\n"
            f"⏱ <b>Timeframe :</b> 1 Hour\n\n"
            f"📍 <b>Entry     :</b> Open SELL at your broker NOW\n"
            f"🛑 <b>Stop Loss :</b> $<code>{sl_d}</code> ABOVE your entry\n"
            f"🎯 <b>Target    :</b> $<code>{tp_d}</code> BELOW your entry\n\n"
            f"📊 <b>RSI(14)   :</b> {rsi_val:.1f}\n"
            f"📊 <b>ATR(14)   :</b> ${atr_val:.2f}\n"
            f"⚖️ <b>Risk/Reward:</b> 1 : {rr}\n\n"
            f"💡 EMA({FAST_EMA}/{SLOW_EMA}) bearish cross confirmed\n"
            f"⚠️ <i>Set SL immediately after opening the trade!</i>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━"
        )
        record_signal("SELL", price, round(price + sl_d, 2), round(price - tp_d, 2))

# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    if not TELEGRAM_TOKEN:
        raise SystemExit("VANTAGE_EA_TOKEN not set in .env")

    log.info("Gold Bot started | ema=%d/%d  rsi=%d  atr_sl=%.1fx  atr_tp=%.1fx  poll=%ds",
             FAST_EMA, SLOW_EMA, RSI_PERIOD, ATR_SL_MULT, ATR_TP_MULT, CHECK_SECS)

    tg_send(
        "🥇 <b>Gold Bot Online — XAUUSD</b>\n"
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
