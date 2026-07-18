"""
Gold Trading Signal Bot — XAUUSD
Strategy : EMA(9/21) crossover + RSI(14) on 1-hour bars
Data     : Yahoo Finance GC=F with 14-min caching + retry (avoids rate limits)
Signals  : Telegram via VantageEA bot with Entry, SL, TP
Report   : Daily P&L summary at 10:00 PM IST
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
from whatsapp import wapp_send
from emailer import email_send

try:
    from trade_executor import queue_trade
except ImportError:
    def queue_trade(*args, **kwargs): pass

load_dotenv()
socket.setdefaulttimeout(30)

TELEGRAM_TOKEN = os.getenv("VANTAGE_EA_TOKEN", "")
CHAT_ID        = os.getenv("SIGNAL_CHAT_ID",   "7093601171")
SYMBOL         = "GC=F"
DISPLAY_NAME   = "XAUUSD"
FAST_EMA       = 9
SLOW_EMA       = 21
RSI_PERIOD     = 14
RSI_BUY_MAX    = 70
RSI_SELL_MIN   = 30
ATR_PERIOD     = 14
ATR_SL_MULT    = 1.0
ATR_TP_MULT    = 3.0
CHECK_SECS     = 60
CACHE_TTL      = 840   # 14 min — fetch fresh data once per 1H bar

logging.basicConfig(format="%(asctime)s | XAUUSD   | %(levelname)s | %(message)s", level=logging.INFO)
log = logging.getLogger(__name__)

_seen_bars        = set()
_daily_signals    = []
_report_sent_date = None
_cache            = {}

SEEN_FILE = os.path.join(os.path.dirname(__file__), ".seen_gold")

def _load_seen_bars():
    try:
        with open(SEEN_FILE) as f:
            for line in f: _seen_bars.add(line.strip())
    except FileNotFoundError:
        pass

def _save_seen_bar(bar_ts):
    with open(SEEN_FILE, "a") as f: f.write(bar_ts + "\n")

def tg_send(text):
    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
    try:
        r = requests.post(url, data={"chat_id": CHAT_ID, "text": text, "parse_mode": "HTML"}, timeout=10)
        if not r.json().get("ok"): log.warning("Telegram failed: %s", r.text[:120])
    except Exception as exc: log.warning("Telegram error: %s", exc)
    wapp_send(text)
    email_send("Trading Signal: XAUUSD Gold", text)

def record_signal(direction, price, sl, tp):
    _daily_signals.append({"direction": direction, "price": price, "sl": sl, "tp": tp,
                            "time": datetime.now().strftime("%I:%M %p")})

def send_daily_report():
    today = datetime.now().strftime("%d %b %Y")
    n = len(_daily_signals)
    lines = [f"📊 <b>Daily Signal Report — {today}</b>", "━━━━━━━━━━━━━━━━━━━━━━",
             f"<b>Gold Bot (XAUUSD)</b>  |  Signals Today: <b>{n}</b>", ""]
    if n == 0:
        lines.append("No signals were generated today.")
    else:
        for i, s in enumerate(_daily_signals, 1):
            em = "🟢" if s["direction"] == "BUY" else "🔴"
            rr = round(abs(s["tp"] - s["price"]) / max(abs(s["sl"] - s["price"]), 0.01), 1)
            lines.append(f"{i}. {em} <b>XAUUSD</b> {s['direction']}  @  {s['time']}\n"
                         f"   Entry ${s['price']:.2f}  •  SL ${s['sl']:.2f}  •  TP ${s['tp']:.2f}  •  RR 1:{rr}")
    lines += ["", "━━━━━━━━━━━━━━━━━━━━━━", "📌 <i>Check your broker for actual P&amp;L</i>"]
    tg_send("\n".join(lines))
    log.info("Daily report sent.")

def maybe_send_daily_report():
    global _report_sent_date, _daily_signals
    now = datetime.now(); today = now.date()
    if now.hour == 22 and now.minute < 2 and _report_sent_date != today:
        _report_sent_date = today; send_daily_report()
    if now.hour == 0 and now.minute < 2 and _daily_signals: _daily_signals.clear()

def calc_rsi(close, period):
    delta = close.diff()
    ag = delta.clip(lower=0).ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    al = (-delta.clip(upper=0)).ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    return 100 - 100 / (1 + ag / al)

def calc_atr(high, low, close, period):
    pc = close.shift(1)
    tr = pd.concat([high-low, (high-pc).abs(), (low-pc).abs()], axis=1).max(axis=1)
    return tr.ewm(span=period, adjust=False).mean()

def _yf_download(ticker, period, interval):
    for attempt in range(3):
        try:
            df = yf.download(ticker, period=period, interval=interval, progress=False, auto_adjust=True)
            if df is not None and not df.empty: return df
        except Exception as exc:
            log.warning("yfinance attempt %d failed: %s", attempt + 1, exc)
        if attempt < 2: time.sleep(5 * (2 ** attempt))
    return None

def fetch_ohlcv():
    now = time.time()
    cached = _cache.get("1h")
    if cached and now - cached[0] < CACHE_TTL: return cached[1]
    df = _yf_download(SYMBOL, "60d", "1h")
    if df is None or len(df) < SLOW_EMA + 10:
        log.warning("Not enough bars. Will retry."); return None
    if isinstance(df.columns, pd.MultiIndex): df.columns = [col[0] for col in df.columns]
    _cache["1h"] = (now, df)
    log.info("Fetched %d 1H bars for XAUUSD", len(df))
    return df

def get_daily_trend():
    now = time.time()
    cached = _cache.get("1d")
    if cached and now - cached[0] < 3600: return cached[1]
    df = _yf_download(SYMBOL, "3mo", "1d")
    if df is None or len(df) < 22: return 0
    if isinstance(df.columns, pd.MultiIndex): df.columns = [col[0] for col in df.columns]
    close = df["Close"].squeeze()
    ema20 = close.ewm(span=20, adjust=False).mean()
    trend = 1 if float(close.iloc[-1]) > float(ema20.iloc[-1]) else -1
    _cache["1d"] = (now, trend)
    return trend

def check_signal():
    df = fetch_ohlcv()
    if df is None: return
    close = df["Close"].squeeze()
    if isinstance(close, pd.DataFrame): close = close.iloc[:, 0]
    high = df["High"].squeeze(); low = df["Low"].squeeze()
    if isinstance(high, pd.DataFrame): high = high.iloc[:, 0]
    if isinstance(low,  pd.DataFrame): low  = low.iloc[:,  0]
    close = close.dropna()
    fast_ema = close.ewm(span=FAST_EMA, adjust=False).mean()
    slow_ema = close.ewm(span=SLOW_EMA, adjust=False).mean()
    rsi = calc_rsi(close, RSI_PERIOD)
    atr = calc_atr(high, low, close, ATR_PERIOD)
    i = -2; bar_ts = str(df.index[i])
    if bar_ts in _seen_bars: return
    bull_cross = (fast_ema.iloc[i] > slow_ema.iloc[i]) and (fast_ema.iloc[i-1] <= slow_ema.iloc[i-1])
    bear_cross = (fast_ema.iloc[i] < slow_ema.iloc[i]) and (fast_ema.iloc[i-1] >= slow_ema.iloc[i-1])
    rsi_val = float(rsi.iloc[i]); price = float(close.iloc[i])
    atr_val = max(float(atr.iloc[i]), 3.0)
    _seen_bars.add(bar_ts); _save_seen_bar(bar_ts)
    if len(_seen_bars) > 500: _seen_bars.clear()
    log.info("Bar %s  price=$%.2f  rsi=%.1f  atr=%.2f  bull=%s  bear=%s",
             bar_ts, price, rsi_val, atr_val, bull_cross, bear_cross)
    rr = round(ATR_TP_MULT / ATR_SL_MULT, 1)
    if bull_cross and rsi_val < RSI_BUY_MAX:
        if get_daily_trend() == -1: log.info("SKIP BUY XAUUSD — daily trend bearish"); return
        entry = round(price, 2); sl = round(entry - ATR_SL_MULT * atr_val, 2); tp = round(entry + ATR_TP_MULT * atr_val, 2)
        log.info(">>> BUY SIGNAL <<<  Entry=$%.2f  SL=$%.2f  TP=$%.2f", entry, sl, tp)
        tg_send(f"━━━━━━━━━━━━━━━━━━━━━━\n🥇 <b>GOLD BOT — XAUUSD</b>\n━━━━━━━━━━━━━━━━━━━━━━\n\n"
                f"📈 <b>Signal    :</b> 🟢 BUY\n📅 <b>Time      :</b> {datetime.now().strftime('%d %b %Y %I:%M %p IST')}\n"
                f"⏱ <b>Timeframe :</b> 1 Hour\n\n📍 <b>Entry     :</b> $<code>{entry:.2f}</code>\n"
                f"🛑 <b>Stop Loss :</b> $<code>{sl:.2f}</code>\n🎯 <b>Target    :</b> $<code>{tp:.2f}</code>\n\n"
                f"📊 <b>RSI(14)   :</b> {rsi_val:.1f}\n📊 <b>ATR(14)   :</b> ${atr_val:.2f}\n"
                f"⚖️ <b>Risk/Reward:</b> 1 : {rr}\n\n💡 EMA({FAST_EMA}/{SLOW_EMA}) bullish cross confirmed\n"
                f"⚠️ <i>Set SL immediately after opening the trade!</i>\n━━━━━━━━━━━━━━━━━━━━━━")
        record_signal("BUY", entry, sl, tp); queue_trade("XAUUSD", "BUY", sl, tp, source="XAUUSD_1H")
    elif bear_cross and rsi_val > RSI_SELL_MIN:
        if get_daily_trend() == 1: log.info("SKIP SELL XAUUSD — daily trend bullish"); return
        entry = round(price, 2); sl = round(entry + ATR_SL_MULT * atr_val, 2); tp = round(entry - ATR_TP_MULT * atr_val, 2)
        log.info(">>> SELL SIGNAL <<<  Entry=$%.2f  SL=$%.2f  TP=$%.2f", entry, sl, tp)
        tg_send(f"━━━━━━━━━━━━━━━━━━━━━━\n🥇 <b>GOLD BOT — XAUUSD</b>\n━━━━━━━━━━━━━━━━━━━━━━\n\n"
                f"📉 <b>Signal    :</b> 🔴 SELL\n📅 <b>Time      :</b> {datetime.now().strftime('%d %b %Y %I:%M %p IST')}\n"
                f"⏱ <b>Timeframe :</b> 1 Hour\n\n📍 <b>Entry     :</b> $<code>{entry:.2f}</code>\n"
                f"🛑 <b>Stop Loss :</b> $<code>{sl:.2f}</code>\n🎯 <b>Target    :</b> $<code>{tp:.2f}</code>\n\n"
                f"📊 <b>RSI(14)   :</b> {rsi_val:.1f}\n📊 <b>ATR(14)   :</b> ${atr_val:.2f}\n"
                f"⚖️ <b>Risk/Reward:</b> 1 : {rr}\n\n💡 EMA({FAST_EMA}/{SLOW_EMA}) bearish cross confirmed\n"
                f"⚠️ <i>Set SL immediately after opening the trade!</i>\n━━━━━━━━━━━━━━━━━━━━━━")
        record_signal("SELL", entry, sl, tp); queue_trade("XAUUSD", "SELL", sl, tp, source="XAUUSD_1H")

def main():
    if not TELEGRAM_TOKEN: raise SystemExit("VANTAGE_EA_TOKEN not set in .env")
    _load_seen_bars()
    log.info("Gold Bot started | ema=%d/%d  rsi=%d  cache=%ds  poll=%ds",
             FAST_EMA, SLOW_EMA, RSI_PERIOD, CACHE_TTL, CHECK_SECS)
    tg_send(f"🥇 <b>Gold Bot Online — XAUUSD</b>\n📅 {datetime.now().strftime('%d %b %Y %I:%M %p IST')}\n"
            f"📊 EMA({FAST_EMA}/{SLOW_EMA}) + RSI({RSI_PERIOD}) | 1H\n⚖️ SL = 1x ATR  |  TP = 3x ATR\n"
            f"🕙 Daily report at 10:00 PM IST")
    while True:
        try:
            maybe_send_daily_report(); check_signal()
        except Exception as exc: log.error("Unexpected error: %s", exc)
        time.sleep(CHECK_SECS)

if __name__ == "__main__":
    main()
