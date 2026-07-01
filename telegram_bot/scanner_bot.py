"""
Upstox Stock Scanner Bot
Strategy : EMA(9/21) crossover + RSI(14) on 15-minute bars
Universe : Top NSE large-cap stocks (Nifty 50)
Data     : Yahoo Finance with 4-min caching + retry (avoids rate limits)
Session  : 9:15 AM – 3:30 PM IST only
Signals  : Telegram via Elite bot with Entry, SL, TP (ATR-based)
Report   : Daily summary at 10:00 PM IST
"""

import os
import time
import socket
import logging
import json
from datetime import datetime
import pytz

import pandas as pd
import yfinance as yf
import requests
from dotenv import load_dotenv
from whatsapp import wapp_send
from emailer import email_send

IST = pytz.timezone("Asia/Kolkata")

load_dotenv()
socket.setdefaulttimeout(30)

TELEGRAM_TOKEN = os.getenv("STOCX_BOT_TOKEN", "")
CHAT_ID        = os.getenv("SIGNAL_CHAT_ID",  "7093601171")
TIMEFRAME      = "15m"
FAST_EMA       = 9
SLOW_EMA       = 21
RSI_PERIOD     = 14
RSI_BUY_MAX    = 75
RSI_SELL_MIN   = 25
ATR_PERIOD     = 14
ATR_SL_MULT    = 1.0
ATR_TP_MULT    = 2.0
MAX_SIGNALS_PER_SCAN = 5
MAX_SIGNALS_PER_STOCK_PER_DAY = 2
COOLDOWN_SECS  = 1800
SCAN_INTERVAL  = 300
MARKET_OPEN    = (9, 15)
MARKET_CLOSE   = (15, 30)
CACHE_TTL      = 240   # 4-min cache — reuse data across stocks in same scan

STOCKS = [
    "ADANIENT.NS",  "ADANIPORTS.NS","APOLLOHOSP.NS","ASIANPAINT.NS","AXISBANK.NS",
    "BAJAJ-AUTO.NS","BAJFINANCE.NS","BAJAJFINSV.NS","BPCL.NS",      "BHARTIARTL.NS",
    "BRITANNIA.NS", "CIPLA.NS",     "COALINDIA.NS", "DRREDDY.NS",   "EICHERMOT.NS",
    "GRASIM.NS",    "HCLTECH.NS",   "HDFCBANK.NS",  "HDFCLIFE.NS",  "HEROMOTOCO.NS",
    "HINDALCO.NS",  "HINDUNILVR.NS","ICICIBANK.NS", "ITC.NS",       "INDUSINDBK.NS",
    "INFY.NS",      "JSWSTEEL.NS",  "KOTAKBANK.NS", "LT.NS",        "LTIM.NS",
    "M&M.NS",       "MARUTI.NS",    "NTPC.NS",      "NESTLEIND.NS", "ONGC.NS",
    "POWERGRID.NS", "RELIANCE.NS",  "SBILIFE.NS",   "SHRIRAMFIN.NS","SBIN.NS",
    "SUNPHARMA.NS", "TCS.NS",       "TATACONSUM.NS","TATAMOTORS.NS","TATASTEEL.NS",
    "TECHM.NS",     "TITAN.NS",     "TRENT.NS",     "ULTRACEMCO.NS","WIPRO.NS",
]

logging.basicConfig(format="%(asctime)s | SCANNER  | %(levelname)s | %(message)s", level=logging.INFO)
log = logging.getLogger(__name__)

_last_signal         = {}
_signal_count_today  = {}
_daily_signals       = []
_report_sent_date    = None
_cache               = {}

STATE_FILE = os.path.join(os.path.dirname(__file__), ".state_scanner.json")

def _load_state():
    global _last_signal, _signal_count_today
    try:
        with open(STATE_FILE) as f: data = json.load(f)
        today_str = datetime.now(IST).strftime("%Y-%m-%d")
        for ticker, info in data.items():
            _last_signal[ticker] = info.get("last_ts", 0)
            if info.get("date") == today_str:
                _signal_count_today[ticker] = info.get("count", 0)
    except (FileNotFoundError, json.JSONDecodeError): pass

def _save_state():
    today_str = datetime.now(IST).strftime("%Y-%m-%d")
    data = {t: {"last_ts": _last_signal.get(t, 0), "count": _signal_count_today.get(t, 0), "date": today_str}
            for t in set(_last_signal) | set(_signal_count_today)}
    try:
        with open(STATE_FILE, "w") as f: json.dump(data, f)
    except Exception: pass

def tg_send(text):
    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
    try:
        r = requests.post(url, data={"chat_id": CHAT_ID, "text": text, "parse_mode": "HTML"}, timeout=10)
        if not r.json().get("ok"): log.warning("Telegram failed: %s", r.text[:120])
    except Exception as exc: log.warning("Telegram error: %s", exc)
    wapp_send(text)
    email_send("Trading Signal: Stock Scanner", text)

def record_signal(symbol, direction, price, sl, tp):
    _daily_signals.append({"symbol": symbol.replace(".NS", ""), "direction": direction,
                            "price": price, "sl": sl, "tp": tp, "time": datetime.now(IST).strftime("%I:%M %p")})

def send_daily_report():
    today = datetime.now(IST).strftime("%d %b %Y"); n = len(_daily_signals)
    lines = [f"📊 <b>Daily Signal Report — {today}</b>", "━━━━━━━━━━━━━━━━━━━━━━",
             f"<b>Stock Scanner</b>  |  Signals Today: <b>{n}</b>", ""]
    if n == 0: lines.append("No signals were generated today.")
    else:
        for i, s in enumerate(_daily_signals, 1):
            em = "🟢" if s["direction"] == "BUY" else "🔴"
            rr = round(abs(s["tp"] - s["price"]) / max(abs(s["sl"] - s["price"]), 0.01), 1)
            lines.append(f"{i}. {em} <b>{s['symbol']}</b> {s['direction']}  @  {s['time']}\n"
                         f"   Entry ₹{s['price']:.2f}  •  SL ₹{s['sl']:.2f}  •  TP ₹{s['tp']:.2f}  •  RR 1:{rr}")
    lines += ["", "━━━━━━━━━━━━━━━━━━━━━━", "📌 <i>Check Upstox for actual P&amp;L</i>"]
    tg_send("\n".join(lines)); log.info("Daily report sent — %d signals", n)

def maybe_send_daily_report():
    global _report_sent_date, _daily_signals
    now = datetime.now(IST); today = now.date()
    if now.hour == 22 and now.minute < 2 and _report_sent_date != today:
        _report_sent_date = today; send_daily_report()
    if now.hour == 0 and now.minute < 2 and _daily_signals:
        _daily_signals.clear(); _signal_count_today.clear()

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
            log.debug("yfinance attempt %d failed for %s: %s", attempt + 1, ticker, exc)
        if attempt < 2: time.sleep(5 * (2 ** attempt))
    return None

def fetch_stock(ticker):
    cache_key = f"{ticker}_15m"
    now = time.time()
    cached = _cache.get(cache_key)
    if cached and now - cached[0] < CACHE_TTL: return cached[1]
    df = _yf_download(ticker, "10d", "15m")
    if df is None or len(df) < SLOW_EMA + 5: return None
    if isinstance(df.columns, pd.MultiIndex): df.columns = [col[0] for col in df.columns]
    df = df[["Open", "High", "Low", "Close", "Volume"]].copy()
    df.index = pd.to_datetime(df.index)
    df = df.between_time("03:45", "10:00")
    df.dropna(inplace=True)
    if len(df) < SLOW_EMA + 5: return None
    _cache[cache_key] = (now, df)
    return df

def get_daily_trend(ticker):
    cache_key = f"{ticker}_1d_trend"
    now = time.time()
    cached = _cache.get(cache_key)
    if cached and now - cached[0] < 3600: return cached[1]
    df = _yf_download(ticker, "3mo", "1d")
    if df is None or len(df) < 22: return 0
    if isinstance(df.columns, pd.MultiIndex): df.columns = [col[0] for col in df.columns]
    close = df["Close"].squeeze()
    if isinstance(close, pd.DataFrame): close = close.iloc[:, 0]
    ema20 = close.ewm(span=20, adjust=False).mean()
    trend = 1 if float(close.iloc[-1]) > float(ema20.iloc[-1]) else -1
    _cache[cache_key] = (now, trend); return trend

def check_stock(ticker):
    df = fetch_stock(ticker)
    if df is None: return None
    close = df["Close"].squeeze(); high = df["High"].squeeze(); low = df["Low"].squeeze()
    if isinstance(close, pd.DataFrame): close = close.iloc[:, 0]
    if isinstance(high,  pd.DataFrame): high  = high.iloc[:,  0]
    if isinstance(low,   pd.DataFrame): low   = low.iloc[:,   0]
    fast_ema = close.ewm(span=FAST_EMA, adjust=False).mean()
    slow_ema = close.ewm(span=SLOW_EMA, adjust=False).mean()
    rsi = calc_rsi(close, RSI_PERIOD); atr = calc_atr(high, low, close, ATR_PERIOD)
    i = -2
    bull_cross = (fast_ema.iloc[i] > slow_ema.iloc[i]) and (fast_ema.iloc[i-1] <= slow_ema.iloc[i-1])
    bear_cross = (fast_ema.iloc[i] < slow_ema.iloc[i]) and (fast_ema.iloc[i-1] >= slow_ema.iloc[i-1])
    rsi_val = float(rsi.iloc[i]); price = float(close.iloc[i]); atr_val = float(atr.iloc[i])
    if bull_cross and rsi_val < RSI_BUY_MAX:
        if get_daily_trend(ticker) == -1: log.info("SKIP BUY  %s — daily trend bearish", ticker); return None
        return "BUY", price, round(price - ATR_SL_MULT*atr_val, 2), round(price + ATR_TP_MULT*atr_val, 2), rsi_val, atr_val
    # SELL signals disabled — Indian equity cannot be shorted in MIS
    return None

def format_stock_signal(ticker, direction, price, sl, tp, rsi_val, atr_val):
    name = ticker.replace(".NS", ""); em = "🟢 BUY" if direction == "BUY" else "🔴 SELL"
    rr = round(abs(tp - price) / max(abs(sl - price), 0.01), 1)
    return (f"━━━━━━━━━━━━━━━━━━━━━━\n🔍 <b>STOCK SCANNER — {name}</b>\n━━━━━━━━━━━━━━━━━━━━━━\n\n"
            f"📈 <b>Signal    :</b> {em}\n📅 <b>Time      :</b> {datetime.now(IST).strftime('%d %b %Y %I:%M %p IST')}\n"
            f"⏱ <b>Timeframe :</b> 15 Minutes\n\n📍 <b>Entry     :</b> ₹<code>{price:.2f}</code>\n"
            f"🛑 <b>Stop Loss :</b> ₹<code>{sl:.2f}</code>\n🎯 <b>Target    :</b> ₹<code>{tp:.2f}</code>\n\n"
            f"📊 <b>RSI(14)   :</b> {rsi_val:.1f}\n📊 <b>ATR(14)   :</b> ₹{atr_val:.2f}\n"
            f"⚖️ <b>Risk/Reward:</b> 1 : {rr}\n\n💡 EMA({FAST_EMA}/{SLOW_EMA}) crossover confirmed\n"
            f"🏦 <i>Place as MIS (Intraday) in Upstox</i>\n"
            f"⚠️ <i>Set SL first! Square off before 3:15 PM IST</i>\n━━━━━━━━━━━━━━━━━━━━━━")

def in_market_hours():
    now = datetime.now(IST); return MARKET_OPEN <= (now.hour, now.minute) <= MARKET_CLOSE

def run_scan():
    log.info("Scanning %d stocks...", len(STOCKS)); fired = 0
    for ticker in STOCKS:
        if fired >= MAX_SIGNALS_PER_SCAN: break
        if time.time() - _last_signal.get(ticker, 0) < COOLDOWN_SECS: continue
        if _signal_count_today.get(ticker, 0) >= MAX_SIGNALS_PER_STOCK_PER_DAY: continue
        try:
            result = check_stock(ticker)
            if result:
                direction, price, sl, tp, rsi_val, atr_val = result
                log.info("SIGNAL %s %s | ₹%.2f → SL ₹%.2f  TP ₹%.2f", ticker, direction, price, sl, tp)
                tg_send(format_stock_signal(ticker, direction, price, sl, tp, rsi_val, atr_val))
                record_signal(ticker, direction, price, sl, tp)
                _last_signal[ticker] = time.time()
                _signal_count_today[ticker] = _signal_count_today.get(ticker, 0) + 1
                _save_state(); fired += 1; time.sleep(1)
        except Exception as exc: log.debug("Error scanning %s: %s", ticker, exc)
        time.sleep(2)   # space out yfinance calls across 50 stocks
    if fired == 0: log.info("No signals this scan.")

def main():
    _load_state()
    log.info("Stock Scanner started | stocks=%d  tf=%s  ema=%d/%d  scan_every=%ds",
             len(STOCKS), TIMEFRAME, FAST_EMA, SLOW_EMA, SCAN_INTERVAL)
    tg_send(f"🔍 <b>Stock Scanner Online</b>\n📅 {datetime.now(IST).strftime('%d %b %Y %I:%M %p IST')}\n"
            f"📊 EMA({FAST_EMA}/{SLOW_EMA}) + RSI({RSI_PERIOD}) | 15min\n"
            f"📋 Watching {len(STOCKS)} NSE stocks\n🕙 Daily report at 10:00 PM IST\n"
            "<i>Active during market hours only (9:15–3:30 IST)</i>")
    while True:
        try:
            maybe_send_daily_report()
            if in_market_hours(): run_scan()
            else: log.info("Outside market hours. Waiting...")
        except Exception as exc: log.error("Main loop error: %s", exc)
        time.sleep(SCAN_INTERVAL)

if __name__ == "__main__":
    main()
