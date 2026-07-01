"""
India Nifty 50 Scalper Bot
Strategy : EMA(9/21) crossover + RSI(14) on 30-minute bars (1-bar confirmation)
Symbols  : All 50 Nifty 50 stocks (NSE)
Data     : Upstox Historical Candle API (30m, native) with Yahoo Finance fallback
Execution: Upstox v2 API — market order, MIS intraday
Signals  : Telegram
Hours    : 9:15 AM – 3:30 PM IST only (weekdays)
Report   : Daily summary at 3:35 PM IST
"""

import os
import io
import gzip
import time
import socket
import logging
from datetime import datetime
import pytz

import pandas as pd
import yfinance as yf
import requests
from dotenv import load_dotenv
from whatsapp import wapp_send
from emailer import email_send

load_dotenv()
socket.setdefaulttimeout(30)

TELEGRAM_TOKEN    = os.getenv("STOCX_BOT_TOKEN", "")
CHAT_ID           = os.getenv("SIGNAL_CHAT_ID", "7093601171")
UPSTOX_TOKEN      = os.getenv("UPSTOX_TOKEN", "")
UPSTOX_DATA_TOKEN = os.getenv("UPSTOX_DATA_TOKEN", "")

FAST_EMA      = 9
SLOW_EMA      = 21
RSI_PERIOD    = 14
RSI_BUY_MAX   = 60
RSI_SELL_MIN  = 40
ATR_PERIOD    = 14
ATR_SL_MULT   = 1.0
ATR_TP_MULT   = 2.0
COOLDOWN_SECS = 1800
SCAN_INTERVAL = 60
CACHE_TTL     = 600     # 10-min cache (30m bars change every 30 min)
QTY           = 1       # shares per trade — increase as needed
UPSTOX_INTERVAL = "30minute"

IST = pytz.timezone("Asia/Kolkata")

NIFTY50 = [
    "ADANIENT",   "ADANIPORTS", "APOLLOHOSP", "ASIANPAINT", "AXISBANK",
    "BAJAJ-AUTO", "BAJAJFINSV", "BAJFINANCE", "BEL",        "BHARTIARTL",
    "BPCL",       "BRITANNIA",  "CIPLA",      "COALINDIA",  "DRREDDY",
    "EICHERMOT",  "ETERNAL",    "GRASIM",     "HCLTECH",    "HDFCBANK",
    "HDFCLIFE",   "HEROMOTOCO", "HINDALCO",   "HINDUNILVR", "ICICIBANK",
    "INDUSINDBK", "INFY",       "ITC",        "JIOFIN",     "JSWSTEEL",
    "KOTAKBANK",  "LT",         "M&M",        "MARUTI",     "NESTLEIND",
    "NTPC",       "ONGC",       "POWERGRID",  "RELIANCE",   "SBILIFE",
    "SHRIRAMFIN", "SBIN",       "SUNPHARMA",  "TATACONSUM", "TATAMOTORS",
    "TATASTEEL",  "TCS",        "TECHM",      "TITAN",      "ULTRACEMCO",
]

logging.basicConfig(
    format="%(asctime)s | INDIA    | %(levelname)s | %(message)s",
    level=logging.INFO,
)
log = logging.getLogger(__name__)

_last_signal      = {}
_seen_bars        = {}
_daily_signals    = []
_report_sent_date = None
_cache            = {}
_instrument_keys  = {}   # NSE symbol → Upstox instrument_key

SEEN_FILE = os.path.join(os.path.dirname(__file__), ".seen_india_scalper")


# ── persistence ──────────────────────────────────────────────────────────────

def _load_seen():
    try:
        with open(SEEN_FILE) as f:
            for line in f:
                parts = line.strip().split("|")
                if len(parts) == 2:
                    _seen_bars.setdefault(parts[0], set()).add(parts[1])
    except FileNotFoundError:
        pass

def _save_seen(name, bar_ts):
    with open(SEEN_FILE, "a") as f:
        f.write(f"{name}|{bar_ts}\n")


# ── Telegram ──────────────────────────────────────────────────────────────────

def tg_send(text):
    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
    try:
        r = requests.post(
            url,
            data={"chat_id": CHAT_ID, "text": text, "parse_mode": "HTML"},
            timeout=10,
        )
        if not r.json().get("ok"):
            log.warning("Telegram failed: %s", r.text[:120])
    except Exception as exc:
        log.warning("Telegram error: %s", exc)
    try:
        wapp_send(text)
        email_send("Trading Signal: India Scalper", text)
    except Exception:
        pass


# ── market hours ─────────────────────────────────────────────────────────────

def is_market_open():
    now = datetime.now(IST)
    if now.weekday() >= 5:
        return False
    open_  = now.replace(hour=9,  minute=15, second=0, microsecond=0)
    close_ = now.replace(hour=15, minute=30, second=0, microsecond=0)
    return open_ <= now <= close_


# ── Upstox ───────────────────────────────────────────────────────────────────

def load_instrument_keys():
    try:
        url = "https://assets.upstox.com/market-quote/instruments/exchange/NSE.csv.gz"
        r = requests.get(url, timeout=30)
        df = pd.read_csv(io.BytesIO(gzip.decompress(r.content)))
        log.debug("Upstox CSV columns: %s", list(df.columns))
        # Detect segment / exchange column flexibly
        seg_col = next((c for c in df.columns if c.lower() in ("segment", "exchange_segment", "exchange")), None)
        if seg_col:
            df = df[df[seg_col].astype(str).str.contains("NSE_EQ|NSE", na=False)]
        sym_col = next((c for c in df.columns if c.lower() in ("tradingsymbol", "trading_symbol", "symbol")), None)
        key_col = next((c for c in df.columns if "instrument_key" in c.lower()), None)
        if not sym_col or not key_col:
            log.warning("Upstox CSV format unexpected — columns: %s", list(df.columns))
            return
        _instrument_keys.update(dict(zip(df[sym_col], df[key_col])))
        log.info("Loaded %d NSE instrument keys from Upstox (sym=%s key=%s)", len(_instrument_keys), sym_col, key_col)
    except Exception as exc:
        log.warning("Could not load Upstox instrument keys: %s — orders will be skipped", exc)

def upstox_place_order(symbol, transaction_type):
    if not UPSTOX_TOKEN:
        log.warning("UPSTOX_TOKEN not set — skipping order for %s", symbol)
        return
    instrument_key = _instrument_keys.get(symbol)
    if not instrument_key:
        log.warning("No Upstox instrument key for %s — skipping order", symbol)
        return
    headers = {
        "Authorization": f"Bearer {UPSTOX_TOKEN}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    payload = {
        "quantity": QTY,
        "product": "I",           # MIS intraday
        "validity": "DAY",
        "price": 0,
        "tag": f"scalper_{symbol}",
        "instrument_key": instrument_key,
        "order_type": "MARKET",
        "transaction_type": transaction_type,
        "disclosed_quantity": 0,
        "trigger_price": 0,
        "is_amo": False,
    }
    try:
        r = requests.post(
            "https://api.upstox.com/v2/order/place",
            json=payload, headers=headers, timeout=10,
        )
        data = r.json()
        if r.status_code == 200 and data.get("status") == "success":
            oid = data.get("data", {}).get("order_id", "?")
            log.info("Upstox %s %s placed — order_id=%s", transaction_type, symbol, oid)
        else:
            log.warning("Upstox order failed %s: %s", symbol, data)
    except Exception as exc:
        log.warning("Upstox API error %s: %s", symbol, exc)


# ── daily report ─────────────────────────────────────────────────────────────

def record_signal(name, direction, price, sl, tp):
    _daily_signals.append({
        "name": name, "direction": direction,
        "price": price, "sl": sl, "tp": tp,
        "time": datetime.now(IST).strftime("%I:%M %p"),
    })

def send_daily_report():
    global _report_sent_date, _daily_signals
    today = datetime.now(IST).strftime("%d %b %Y")
    n = len(_daily_signals)
    lines = [
        f"📊 <b>Daily India Scalper Report — {today}</b>",
        "━━━━━━━━━━━━━━━━━━━━━━",
        f"<b>Nifty 50 Scalper</b>  |  Signals Today: <b>{n}</b>", "",
    ]
    if n == 0:
        lines.append("No signals were generated today.")
    else:
        for i, s in enumerate(_daily_signals, 1):
            em = "🟢" if s["direction"] == "BUY" else "🔴"
            rr = round(abs(s["tp"] - s["price"]) / max(abs(s["sl"] - s["price"]), 0.01), 1)
            lines.append(
                f"{i}. {em} <b>{s['name']}</b> {s['direction']}  @  {s['time']}\n"
                f"   Entry ₹{s['price']:.2f}  •  SL ₹{s['sl']:.2f}  "
                f"•  TP ₹{s['tp']:.2f}  •  RR 1:{rr}"
            )
    lines += ["", "━━━━━━━━━━━━━━━━━━━━━━", "📌 <i>Check Upstox for actual P&amp;L</i>"]
    tg_send("\n".join(lines))
    log.info("Daily report sent — %d signals", n)

def maybe_send_daily_report():
    global _report_sent_date, _daily_signals
    now = datetime.now(IST); today = now.date()
    if now.hour == 15 and now.minute in (35, 36) and _report_sent_date != today:
        _report_sent_date = today; send_daily_report()
    if now.hour == 0 and now.minute < 2 and _daily_signals:
        _daily_signals.clear()


# ── indicators ────────────────────────────────────────────────────────────────

def calc_rsi(close, period):
    delta = close.diff()
    ag = delta.clip(lower=0).ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    al = (-delta.clip(upper=0)).ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    return 100 - 100 / (1 + ag / al)

def calc_atr(high, low, close, period):
    pc = close.shift(1)
    tr = pd.concat([high-low, (high-pc).abs(), (low-pc).abs()], axis=1).max(axis=1)
    return tr.ewm(span=period, adjust=False).mean()


# ── data ──────────────────────────────────────────────────────────────────────

def _upstox_candles(instrument_key, interval, days=10):
    """Fetch OHLCV from Upstox Historical Candle API. Returns DataFrame or None."""
    if not UPSTOX_DATA_TOKEN:
        return None
    from_date = (datetime.now(IST) - pd.Timedelta(days=days)).strftime("%Y-%m-%d")
    to_date   = datetime.now(IST).strftime("%Y-%m-%d")
    url = f"https://api.upstox.com/v2/historical-candle/{instrument_key}/{interval}/{to_date}/{from_date}"
    try:
        r = requests.get(url, headers={"Authorization": f"Bearer {UPSTOX_DATA_TOKEN}",
                                        "Accept": "application/json"}, timeout=15)
        data = r.json()
        if data.get("status") != "success":
            return None
        candles = data["data"]["candles"]
        if not candles:
            return None
        df = pd.DataFrame(candles, columns=["Datetime", "Open", "High", "Low", "Close", "Volume", "OI"])
        df["Datetime"] = pd.to_datetime(df["Datetime"])
        df = df.sort_values("Datetime").set_index("Datetime")
        df = df[["Open", "High", "Low", "Close", "Volume"]].astype(float)
        return df
    except Exception as exc:
        log.debug("Upstox candle error for %s: %s", instrument_key, exc)
        return None

def _yf_candles(name, interval, period):
    ticker = f"{name}.NS"
    for attempt in range(3):
        try:
            df = yf.download(ticker, period=period, interval=interval, progress=False, auto_adjust=True)
            if df is not None and not df.empty:
                if isinstance(df.columns, pd.MultiIndex):
                    df.columns = [col[0] for col in df.columns]
                return df
        except Exception as exc:
            log.debug("yfinance attempt %d for %s: %s", attempt+1, name, exc)
        if attempt < 2:
            time.sleep(5 * (2 ** attempt))
    return None

def fetch_data(name):
    cache_key = f"{name}_30m"
    now = time.time()
    cached = _cache.get(cache_key)
    if cached and now - cached[0] < CACHE_TTL:
        return cached[1]
    df = None
    ikey = _instrument_keys.get(name)
    if ikey:
        df = _upstox_candles(ikey, UPSTOX_INTERVAL, days=10)
    if df is None or len(df) < SLOW_EMA + 5:
        log.debug("%s: Upstox data unavailable, falling back to Yahoo Finance", name)
        df = _yf_candles(name, "30m", "10d")
    if df is None or len(df) < SLOW_EMA + 5:
        return None
    _cache[cache_key] = (now, df)
    return df

def get_1h_trend(name):
    cache_key = f"{name}_1h_trend"
    now = time.time()
    cached = _cache.get(cache_key)
    if cached and now - cached[0] < 3600:
        return cached[1]
    df = None
    ikey = _instrument_keys.get(name)
    if ikey:
        df = _upstox_candles(ikey, "1hour", days=30)
    if df is None:
        df = _yf_candles(name, "1h", "30d")
    if df is None or len(df) < 52:
        return 0
    close = df["Close"].squeeze()
    ema50 = close.ewm(span=50, adjust=False).mean()
    trend = 1 if float(close.iloc[-1]) > float(ema50.iloc[-1]) else -1
    _cache[cache_key] = (now, trend)
    return trend


# ── signal logic ──────────────────────────────────────────────────────────────

def check_symbol(name):
    df = fetch_data(name)
    if df is None or len(df) < SLOW_EMA + 5:
        return
    now_ts = time.time()
    if now_ts - _last_signal.get(name, 0) < COOLDOWN_SECS:
        return
    close = df["Close"].squeeze(); high = df["High"].squeeze(); low = df["Low"].squeeze()
    if isinstance(close, pd.DataFrame): close = close.iloc[:, 0]
    if isinstance(high,  pd.DataFrame): high  = high.iloc[:,  0]
    if isinstance(low,   pd.DataFrame): low   = low.iloc[:,   0]
    fast_ema = close.ewm(span=FAST_EMA, adjust=False).mean()
    slow_ema = close.ewm(span=SLOW_EMA, adjust=False).mean()
    rsi = calc_rsi(close, RSI_PERIOD)
    atr = calc_atr(high, low, close, ATR_PERIOD)
    i = -2
    bar_ts = str(df.index[i])
    if bar_ts in _seen_bars.get(name, set()):
        return
    # 1-bar confirmation: cross on bar[-3], fast EMA holds same side on bar[-2]
    bull_cross = (fast_ema.iloc[i-1] > slow_ema.iloc[i-1]) and (fast_ema.iloc[i-2] <= slow_ema.iloc[i-2]) and (fast_ema.iloc[i] > slow_ema.iloc[i])
    bear_cross = (fast_ema.iloc[i-1] < slow_ema.iloc[i-1]) and (fast_ema.iloc[i-2] >= slow_ema.iloc[i-2]) and (fast_ema.iloc[i] < slow_ema.iloc[i])
    rsi_val = float(rsi.iloc[i])
    price   = float(close.iloc[i])
    atr_val = float(atr.iloc[i])
    atr_val = max(atr_val, price * 0.002)   # floor at 0.2% of price
    _seen_bars.setdefault(name, set()).add(bar_ts)
    _save_seen(name, bar_ts)
    rr      = round(ATR_TP_MULT / ATR_SL_MULT, 1)
    now_ist = datetime.now(IST).strftime("%d %b %Y %I:%M %p IST")

    if bull_cross and rsi_val < RSI_BUY_MAX:
        if get_1h_trend(name) == -1:
            log.info("SKIP BUY  %s — 1H trend bearish", name); return
        entry = round(price, 2)
        sl    = round(entry - ATR_SL_MULT * atr_val, 2)
        tp    = round(entry + ATR_TP_MULT * atr_val, 2)
        log.info("BUY  %s  entry=%.2f  sl=%.2f  tp=%.2f", name, entry, sl, tp)
        tg_send(
            f"━━━━━━━━━━━━━━━━━━━━━━\n⚡ <b>INDIA SCALPER — {name}</b>\n━━━━━━━━━━━━━━━━━━━━━━\n\n"
            f"📈 <b>Signal    :</b> 🟢 BUY\n📅 <b>Time      :</b> {now_ist}\n"
            f"⏱ <b>Timeframe :</b> 30 Minutes\n\n"
            f"📍 <b>Entry     :</b> ₹<code>{entry:.2f}</code>\n"
            f"🛑 <b>Stop Loss :</b> ₹<code>{sl:.2f}</code>\n"
            f"🎯 <b>Target    :</b> ₹<code>{tp:.2f}</code>\n\n"
            f"📊 <b>RSI(14)   :</b> {rsi_val:.1f}\n"
            f"📊 <b>ATR(14)   :</b> ₹{atr_val:.2f}\n"
            f"⚖️ <b>Risk/Reward:</b> 1 : {rr}\n\n"
            f"💡 EMA({FAST_EMA}/{SLOW_EMA}) bullish cross — 30min\n"
            f"⚠️ <i>Set SL immediately! Square off before 3:15 PM IST</i>\n━━━━━━━━━━━━━━━━━━━━━━"
        )
        record_signal(name, "BUY", entry, sl, tp)
        upstox_place_order(name, "BUY")
        _last_signal[name] = now_ts

    elif bear_cross and rsi_val > RSI_SELL_MIN:
        if get_1h_trend(name) == 1:
            log.info("SKIP SELL %s — 1H trend bullish", name); return
        entry = round(price, 2)
        sl    = round(entry + ATR_SL_MULT * atr_val, 2)
        tp    = round(entry - ATR_TP_MULT * atr_val, 2)
        log.info("SELL %s  entry=%.2f  sl=%.2f  tp=%.2f", name, entry, sl, tp)
        tg_send(
            f"━━━━━━━━━━━━━━━━━━━━━━\n⚡ <b>INDIA SCALPER — {name}</b>\n━━━━━━━━━━━━━━━━━━━━━━\n\n"
            f"📉 <b>Signal    :</b> 🔴 SELL\n📅 <b>Time      :</b> {now_ist}\n"
            f"⏱ <b>Timeframe :</b> 30 Minutes\n\n"
            f"📍 <b>Entry     :</b> ₹<code>{entry:.2f}</code>\n"
            f"🛑 <b>Stop Loss :</b> ₹<code>{sl:.2f}</code>\n"
            f"🎯 <b>Target    :</b> ₹<code>{tp:.2f}</code>\n\n"
            f"📊 <b>RSI(14)   :</b> {rsi_val:.1f}\n"
            f"📊 <b>ATR(14)   :</b> ₹{atr_val:.2f}\n"
            f"⚖️ <b>Risk/Reward:</b> 1 : {rr}\n\n"
            f"💡 EMA({FAST_EMA}/{SLOW_EMA}) bearish cross — 30min\n"
            f"⚠️ <i>Set SL immediately! Square off before 3:15 PM IST</i>\n━━━━━━━━━━━━━━━━━━━━━━"
        )
        record_signal(name, "SELL", entry, sl, tp)
        upstox_place_order(name, "SELL")
        _last_signal[name] = now_ts


# ── main ──────────────────────────────────────────────────────────────────────

def main():
    if not TELEGRAM_TOKEN:
        raise SystemExit("STOCX_BOT_TOKEN not set in .env")
    _load_seen()
    load_instrument_keys()
    log.info("India Nifty 50 Scalper started | symbols=%d  ema=%d/%d  rsi=%d  cache=%ds",
             len(NIFTY50), FAST_EMA, SLOW_EMA, RSI_PERIOD, CACHE_TTL)
    tg_send(
        f"⚡ <b>India Nifty 50 Scalper Online</b>\n"
        f"📅 {datetime.now(IST).strftime('%d %b %Y %I:%M %p IST')}\n"
        f"📊 EMA({FAST_EMA}/{SLOW_EMA}) + RSI({RSI_PERIOD}) | 30min\n"
        f"📈 {len(NIFTY50)} Nifty 50 stocks | Upstox MIS\n"
        f"⏰ Active: 9:15 AM – 3:30 PM IST\n"
        f"⚖️ SL = 1x ATR  |  TP = 2x ATR\n"
        f"🕒 Daily report at 3:35 PM IST"
    )
    while True:
        try:
            maybe_send_daily_report()
            if is_market_open():
                for name in NIFTY50:
                    try:
                        check_symbol(name)
                    except Exception as exc:
                        log.debug("Error on %s: %s", name, exc)
                    time.sleep(2)
            else:
                log.debug("Market closed — sleeping %ds", SCAN_INTERVAL)
        except Exception as exc:
            log.error("Unexpected error: %s", exc)
        time.sleep(SCAN_INTERVAL)

if __name__ == "__main__":
    main()
