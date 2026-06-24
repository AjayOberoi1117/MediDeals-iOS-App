"""
Upstox Stock Scanner Bot
Strategy : EMA(9/21) crossover + RSI(14) on 15-minute bars
Universe : Top NSE large-cap stocks (Nifty 50)
Data     : TradingView via tvdatafeed (no API key, no rate limits)
Session  : 9:15 AM – 3:30 PM IST only
Signals  : Telegram via Elite bot with Entry, SL, TP (ATR-based)
Report   : Daily summary at 10:00 PM IST
"""

import os
import time
import logging
import json
from datetime import datetime

import pandas as pd
from tvdatafeed import TvDatafeed, Interval
import requests
from dotenv import load_dotenv
from whatsapp import wapp_send
from emailer import email_send

load_dotenv()

# ── TradingView data source ────────────────────────────────────────────────────

tv = TvDatafeed()

# ── Config ────────────────────────────────────────────────────────────────────

TELEGRAM_TOKEN = os.getenv("ELITE_BOT_TOKEN", "8708193257:AAG6wpyb8popoOmDxnmjP15OaTc2R0sf9Nc")
CHAT_ID        = os.getenv("SIGNAL_CHAT_ID",  "1994067941")
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

# Nifty 50 constituents — symbol names as used on TradingView NSE
STOCKS = [
    "ADANIENT",  "ADANIPORTS", "APOLLOHOSP", "ASIANPAINT", "AXISBANK",
    "BAJAJ-AUTO","BAJFINANCE", "BAJAJFINSV", "BPCL",       "BHARTIARTL",
    "BRITANNIA", "CIPLA",      "COALINDIA",  "DRREDDY",    "EICHERMOT",
    "GRASIM",    "HCLTECH",    "HDFCBANK",   "HDFCLIFE",   "HEROMOTOCO",
    "HINDALCO",  "HINDUNILVR", "ICICIBANK",  "ITC",        "INDUSINDBK",
    "INFY",      "JSWSTEEL",   "KOTAKBANK",  "LT",         "LTIM",
    "M&M",       "MARUTI",     "NTPC",       "NESTLEIND",  "ONGC",
    "POWERGRID", "RELIANCE",   "SBILIFE",    "SHRIRAMFIN", "SBIN",
    "SUNPHARMA", "TCS",        "TATACONSUM", "TATAMOTORS", "TATASTEEL",
    "TECHM",     "TITAN",      "TRENT",      "ULTRACEMCO", "WIPRO",
]

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    format="%(asctime)s | SCANNER  | %(levelname)s | %(message)s",
    level=logging.INFO,
)
log = logging.getLogger(__name__)

# ── State ─────────────────────────────────────────────────────────────────────

_last_signal         = {}
_signal_count_today  = {}
_daily_signals       = []
_report_sent_date    = None

STATE_FILE = os.path.join(os.path.dirname(__file__), ".state_scanner.json")

def _load_state():
    global _last_signal, _signal_count_today
    try:
        with open(STATE_FILE) as f:
            data = json.load(f)
        today_str = datetime.now().strftime("%Y-%m-%d")
        for ticker, info in data.items():
            _last_signal[ticker] = info.get("last_ts", 0)
            if info.get("date") == today_str:
                _signal_count_today[ticker] = info.get("count", 0)
    except (FileNotFoundError, json.JSONDecodeError):
        pass

def _save_state():
    today_str = datetime.now().strftime("%Y-%m-%d")
    data = {
        ticker: {
            "last_ts": _last_signal.get(ticker, 0),
            "count":   _signal_count_today.get(ticker, 0),
            "date":    today_str,
        }
        for ticker in set(_last_signal) | set(_signal_count_today)
    }
    try:
        with open(STATE_FILE, "w") as f:
            json.dump(data, f)
    except Exception:
        pass

# ── Telegram ──────────────────────────────────────────────────────────────────

def tg_send(text: str) -> None:
    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
    try:
        r = requests.post(url,
                          data={"chat_id": CHAT_ID, "text": text, "parse_mode": "HTML"},
                          timeout=10)
        if not r.json().get("ok"):
            log.warning("Telegram failed: %s", r.text[:120])
    except Exception as exc:
        log.warning("Telegram error: %s", exc)
    wapp_send(text)
    email_send("Trading Signal: Stock Scanner", text)

# ── Daily report ──────────────────────────────────────────────────────────────

def record_signal(symbol, direction, price, sl, tp):
    _daily_signals.append({
        "symbol":    symbol,
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
        f"<b>Stock Scanner</b>  |  Signals Today: <b>{n}</b>",
        "",
    ]
    if n == 0:
        lines.append("No signals were generated today.")
    else:
        for i, s in enumerate(_daily_signals, 1):
            em = "🟢" if s["direction"] == "BUY" else "🔴"
            rr = round(abs(s["tp"] - s["price"]) / max(abs(s["sl"] - s["price"]), 0.01), 1)
            lines.append(
                f"{i}. {em} <b>{s['symbol']}</b> {s['direction']}  @  {s['time']}\n"
                f"   Entry ₹{s['price']:.2f}  •  SL ₹{s['sl']:.2f}  •  TP ₹{s['tp']:.2f}  •  RR 1:{rr}"
            )
    lines += [
        "",
        "━━━━━━━━━━━━━━━━━━━━━━",
        "📌 <i>Check Upstox for actual P&amp;L</i>",
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
        _signal_count_today.clear()

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

def fetch_stock(ticker: str):
    try:
        df = tv.get_hist(ticker, "NSE", interval=Interval.in_15_minute, n_bars=100)
        if df is None or df.empty or len(df) < SLOW_EMA + 5:
            return None
        df.columns = [c.lower() for c in df.columns]
        df = df[["open", "high", "low", "close", "volume"]].copy()
        df.dropna(inplace=True)
        return df if len(df) >= SLOW_EMA + 5 else None
    except Exception as exc:
        log.debug("Fetch error %s: %s", ticker, exc)
        return None

def get_daily_trend(ticker: str) -> int:
    try:
        df = tv.get_hist(ticker, "NSE", interval=Interval.in_daily, n_bars=30)
        if df is None or df.empty or len(df) < 22:
            return 0
        df.columns = [c.lower() for c in df.columns]
        close = df["close"]
        ema20 = close.ewm(span=20, adjust=False).mean()
        return 1 if float(close.iloc[-1]) > float(ema20.iloc[-1]) else -1
    except Exception:
        return 0

# ── Signal check per stock ────────────────────────────────────────────────────

def check_stock(ticker: str):
    df = fetch_stock(ticker)
    if df is None:
        return None

    close = df["close"]
    high  = df["high"]
    low   = df["low"]

    fast_ema = close.ewm(span=FAST_EMA, adjust=False).mean()
    slow_ema = close.ewm(span=SLOW_EMA, adjust=False).mean()
    rsi      = calc_rsi(close, RSI_PERIOD)
    atr      = calc_atr(high, low, close, ATR_PERIOD)

    i = -2
    bull_cross = (fast_ema.iloc[i]   > slow_ema.iloc[i]  ) and \
                 (fast_ema.iloc[i-1] <= slow_ema.iloc[i-1])
    bear_cross = (fast_ema.iloc[i]   < slow_ema.iloc[i]  ) and \
                 (fast_ema.iloc[i-1] >= slow_ema.iloc[i-1])

    rsi_val = float(rsi.iloc[i])
    price   = float(close.iloc[i])
    atr_val = float(atr.iloc[i])

    if bull_cross and rsi_val < RSI_BUY_MAX:
        if get_daily_trend(ticker) == -1:
            log.info("SKIP BUY  %s — daily trend bearish", ticker)
            return None
        sl = round(price - ATR_SL_MULT * atr_val, 2)
        tp = round(price + ATR_TP_MULT * atr_val, 2)
        return "BUY", price, sl, tp, rsi_val, atr_val
    elif bear_cross and rsi_val > RSI_SELL_MIN:
        if get_daily_trend(ticker) == 1:
            log.info("SKIP SELL %s — daily trend bullish", ticker)
            return None
        sl = round(price + ATR_SL_MULT * atr_val, 2)
        tp = round(price - ATR_TP_MULT * atr_val, 2)
        return "SELL", price, sl, tp, rsi_val, atr_val
    return None

# ── Signal formatter ──────────────────────────────────────────────────────────

def format_stock_signal(ticker, direction, price, sl, tp, rsi_val, atr_val):
    em  = "🟢 BUY" if direction == "BUY" else "🔴 SELL"
    rr  = round(abs(tp - price) / max(abs(sl - price), 0.01), 1)
    return (
        f"━━━━━━━━━━━━━━━━━━━━━━\n"
        f"🔍 <b>STOCK SCANNER — {ticker}</b>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━\n\n"
        f"📈 <b>Signal    :</b> {em}\n"
        f"📅 <b>Time      :</b> {datetime.now().strftime('%d %b %Y %I:%M %p IST')}\n"
        f"⏱ <b>Timeframe :</b> 15 Minutes\n\n"
        f"📍 <b>Entry     :</b> ₹<code>{price:.2f}</code>\n"
        f"🛑 <b>Stop Loss :</b> ₹<code>{sl:.2f}</code>\n"
        f"🎯 <b>Target    :</b> ₹<code>{tp:.2f}</code>\n\n"
        f"📊 <b>RSI(14)   :</b> {rsi_val:.1f}\n"
        f"📊 <b>ATR(14)   :</b> ₹{atr_val:.2f}\n"
        f"⚖️ <b>Risk/Reward:</b> 1 : {rr}\n\n"
        f"💡 EMA({FAST_EMA}/{SLOW_EMA}) crossover confirmed\n"
        f"🏦 <i>Place as MIS (Intraday) in Upstox</i>\n"
        f"⚠️ <i>Set SL first! Square off before 3:15 PM IST</i>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━"
    )

# ── Market hours ──────────────────────────────────────────────────────────────

def in_market_hours():
    now = datetime.now()
    return MARKET_OPEN <= (now.hour, now.minute) <= MARKET_CLOSE

# ── Main scan ─────────────────────────────────────────────────────────────────

def run_scan():
    log.info("Scanning %d stocks...", len(STOCKS))
    fired = 0
    for ticker in STOCKS:
        if fired >= MAX_SIGNALS_PER_SCAN:
            break
        last_ts = _last_signal.get(ticker, 0)
        if time.time() - last_ts < COOLDOWN_SECS:
            continue
        if _signal_count_today.get(ticker, 0) >= MAX_SIGNALS_PER_STOCK_PER_DAY:
            continue
        try:
            result = check_stock(ticker)
            if result:
                direction, price, sl, tp, rsi_val, atr_val = result
                log.info("SIGNAL %s %s | ₹%.2f → SL ₹%.2f  TP ₹%.2f",
                         ticker, direction, price, sl, tp)
                tg_send(format_stock_signal(ticker, direction, price, sl, tp, rsi_val, atr_val))
                record_signal(ticker, direction, price, sl, tp)
                _last_signal[ticker] = time.time()
                _signal_count_today[ticker] = _signal_count_today.get(ticker, 0) + 1
                _save_state()
                fired += 1
                time.sleep(1)
        except Exception as exc:
            log.debug("Error scanning %s: %s", ticker, exc)

    if fired == 0:
        log.info("No signals this scan.")

# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    _load_state()
    log.info("Stock Scanner started | stocks=%d  tf=%s  ema=%d/%d  rsi=%d  scan_every=%ds",
             len(STOCKS), TIMEFRAME, FAST_EMA, SLOW_EMA, RSI_PERIOD, SCAN_INTERVAL)

    tg_send(
        "🔍 <b>Stock Scanner Online</b>\n"
        f"📅 {datetime.now().strftime('%d %b %Y %I:%M %p IST')}\n"
        f"📊 EMA({FAST_EMA}/{SLOW_EMA}) + RSI({RSI_PERIOD}) | 15min  [TradingView data]\n"
        f"📋 Watching {len(STOCKS)} NSE stocks\n"
        f"🕙 Daily report at 10:00 PM IST\n"
        "<i>Active during market hours only (9:15–3:30 IST)</i>"
    )

    while True:
        try:
            maybe_send_daily_report()
            if in_market_hours():
                run_scan()
            else:
                log.info("Outside market hours. Waiting...")
        except Exception as exc:
            log.error("Main loop error: %s", exc)
        time.sleep(SCAN_INTERVAL)

if __name__ == "__main__":
    main()
