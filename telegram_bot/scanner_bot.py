"""
Upstox Stock Scanner Bot
Strategy : EMA(10/50) crossover + RSI(14) on 15-minute bars
Universe : Top NSE large-cap stocks
Session  : 9:15 AM – 3:30 PM IST only
Signals  : Telegram via Elite bot with Entry, SL, TP (ATR-based)
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

# ── Config ────────────────────────────────────────────────────────────────────

TELEGRAM_TOKEN = os.getenv("ELITE_BOT_TOKEN", "8708193257:AAG6wpyb8popoOmDxnmjP15OaTc2R0sf9Nc")
CHAT_ID        = os.getenv("SIGNAL_CHAT_ID",  "1994067941")
TIMEFRAME      = "15m"
FAST_EMA       = 10
SLOW_EMA       = 50
RSI_PERIOD     = 14
RSI_BUY_MAX    = 70
RSI_SELL_MIN   = 30
ATR_PERIOD     = 14
ATR_SL_MULT    = 1.0
ATR_TP_MULT    = 2.0
MAX_SIGNALS_PER_SCAN = 3       # avoid Telegram spam
COOLDOWN_SECS  = 3600          # 1 hour cooldown per stock
SCAN_INTERVAL  = 300           # scan every 5 minutes
MARKET_OPEN    = (9, 15)
MARKET_CLOSE   = (15, 30)

UPSTOX_TOKEN   = os.getenv("UPSTOX_TOKEN", "")
_UPSTOX_HDR    = {"Accept": "application/json", "Authorization": f"Bearer {UPSTOX_TOKEN}"}

# NSE large-cap stocks to scan
STOCKS = [
    "RELIANCE.NS", "TCS.NS",      "HDFCBANK.NS", "INFY.NS",    "ICICIBANK.NS",
    "SBIN.NS",     "BHARTIARTL.NS","KOTAKBANK.NS","ITC.NS",     "AXISBANK.NS",
    "LT.NS",       "MARUTI.NS",   "NTPC.NS",     "WIPRO.NS",   "HCLTECH.NS",
    "BAJFINANCE.NS","TITAN.NS",   "ULTRACEMCO.NS","POWERGRID.NS","ADANIENT.NS",
]

_UPSTOX_KEYS = {
    "RELIANCE.NS":   "NSE_EQ|RELIANCE",   "TCS.NS":        "NSE_EQ|TCS",
    "HDFCBANK.NS":   "NSE_EQ|HDFCBANK",   "INFY.NS":       "NSE_EQ|INFY",
    "ICICIBANK.NS":  "NSE_EQ|ICICIBANK",  "SBIN.NS":       "NSE_EQ|SBIN",
    "BHARTIARTL.NS": "NSE_EQ|BHARTIARTL", "KOTAKBANK.NS":  "NSE_EQ|KOTAKBANK",
    "ITC.NS":        "NSE_EQ|ITC",        "AXISBANK.NS":   "NSE_EQ|AXISBANK",
    "LT.NS":         "NSE_EQ|LT",         "MARUTI.NS":     "NSE_EQ|MARUTI",
    "NTPC.NS":       "NSE_EQ|NTPC",       "WIPRO.NS":      "NSE_EQ|WIPRO",
    "HCLTECH.NS":    "NSE_EQ|HCLTECH",    "BAJFINANCE.NS": "NSE_EQ|BAJFINANCE",
    "TITAN.NS":      "NSE_EQ|TITAN",      "ULTRACEMCO.NS": "NSE_EQ|ULTRACEMCO",
    "POWERGRID.NS":  "NSE_EQ|POWERGRID",  "ADANIENT.NS":   "NSE_EQ|ADANIENT",
}

# ── Live price (Upstox — requires daily trading token) ───────────────────────

def fetch_live_price_upstox(ticker: str):
    ikey = _UPSTOX_KEYS.get(ticker)
    token = os.getenv("UPSTOX_TOKEN", "")
    if not token or not ikey:
        return None
    try:
        hdr = {"Accept": "application/json", "Authorization": f"Bearer {token}"}
        r = requests.get("https://api.upstox.com/v2/market-quote/quotes",
                         headers=hdr,
                         params={"instrument_key": ikey},
                         timeout=5)
        if r.status_code != 200:
            return None
        data = r.json().get("data", {})
        val  = data.get(ikey.replace("|", ":"), {}).get("last_price", 0)
        return float(val) if val else None
    except Exception:
        return None

# ── Live price fallback (yfinance — no token needed) ─────────────────────────

def fetch_live_price_yf(ticker: str):
    """yfinance fast_info gives ~1-min fresh price with no API key."""
    try:
        info = yf.Ticker(ticker).fast_info
        price = info.get("lastPrice") or info.get("last_price")
        return float(price) if price and float(price) > 0 else None
    except Exception:
        return None

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    format="%(asctime)s | SCANNER  | %(levelname)s | %(message)s",
    level=logging.INFO,
)
log = logging.getLogger(__name__)

# ── State ─────────────────────────────────────────────────────────────────────

_last_signal      = {}   # {symbol: timestamp}
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
            log.warning("Telegram failed: %s", r.text[:120])
    except Exception as exc:
        log.warning("Telegram error: %s", exc)

# ── Daily report ──────────────────────────────────────────────────────────────

def record_signal(symbol, direction, price, sl, tp):
    _daily_signals.append({
        "symbol":    symbol.replace(".NS", ""),
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
        df = yf.download(ticker, period="5d", interval=TIMEFRAME,
                         progress=False, auto_adjust=True)
        if df.empty or len(df) < SLOW_EMA + 5:
            return None

        if isinstance(df.columns, pd.MultiIndex):
            df.columns = [col[0] for col in df.columns]

        df = df[["Open", "High", "Low", "Close", "Volume"]].copy()
        df.index = pd.to_datetime(df.index)
        # Keep only IST market hours (UTC 03:45–10:00)
        df = df.between_time("03:45", "10:00")
        df.dropna(inplace=True)
        return df if len(df) >= SLOW_EMA + 5 else None
    except Exception as exc:
        log.debug("Fetch error %s: %s", ticker, exc)
        return None

# ── Signal check per stock ────────────────────────────────────────────────────

def check_stock(ticker: str):
    df = fetch_stock(ticker)
    if df is None:
        return None

    close    = df["Close"].squeeze()
    high     = df["High"].squeeze()
    low      = df["Low"].squeeze()

    if isinstance(close, pd.DataFrame): close = close.iloc[:, 0]
    if isinstance(high,  pd.DataFrame): high  = high.iloc[:,  0]
    if isinstance(low,   pd.DataFrame): low   = low.iloc[:,   0]

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
        sl = round(price - ATR_SL_MULT * atr_val, 2)
        tp = round(price + ATR_TP_MULT * atr_val, 2)
        return "BUY", price, sl, tp, rsi_val, atr_val
    elif bear_cross and rsi_val > RSI_SELL_MIN:
        sl = round(price + ATR_SL_MULT * atr_val, 2)
        tp = round(price - ATR_TP_MULT * atr_val, 2)
        return "SELL", price, sl, tp, rsi_val, atr_val
    return None

# ── Signal formatter ──────────────────────────────────────────────────────────

def format_stock_signal(ticker, direction, price, sl, tp, rsi_val, atr_val):
    name = ticker.replace(".NS", "")
    em   = "🟢 BUY" if direction == "BUY" else "🔴 SELL"
    rr   = round(abs(tp - price) / max(abs(sl - price), 0.01), 1)
    return (
        f"━━━━━━━━━━━━━━━━━━━━━━\n"
        f"🔍 <b>STOCK SCANNER — {name}</b>\n"
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
        try:
            result = check_stock(ticker)
            if result:
                direction, price, sl, tp, rsi_val, atr_val = result
                # Priority: Upstox (daily token) → yfinance fast_info → bar close
                live = fetch_live_price_upstox(ticker) or fetch_live_price_yf(ticker)
                if live:
                    entry = live
                    sl = round(entry - ATR_SL_MULT * atr_val, 2) if direction == "BUY" \
                         else round(entry + ATR_SL_MULT * atr_val, 2)
                    tp = round(entry + ATR_TP_MULT * atr_val, 2) if direction == "BUY" \
                         else round(entry - ATR_TP_MULT * atr_val, 2)
                else:
                    entry = price
                log.info("SIGNAL %s %s | ₹%.2f → SL ₹%.2f  TP ₹%.2f",
                         ticker, direction, entry, sl, tp)
                tg_send(format_stock_signal(ticker, direction, entry, sl, tp, rsi_val, atr_val))
                record_signal(ticker, direction, entry, sl, tp)
                _last_signal[ticker] = time.time()
                fired += 1
                time.sleep(1)   # small gap between Telegram messages
        except Exception as exc:
            log.debug("Error scanning %s: %s", ticker, exc)

    if fired == 0:
        log.info("No signals this scan.")

# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    log.info("Stock Scanner started | stocks=%d  tf=%s  ema=%d/%d  rsi=%d  scan_every=%ds",
             len(STOCKS), TIMEFRAME, FAST_EMA, SLOW_EMA, RSI_PERIOD, SCAN_INTERVAL)

    tg_send(
        "🔍 <b>Stock Scanner Online</b>\n"
        f"📅 {datetime.now().strftime('%d %b %Y %I:%M %p IST')}\n"
        f"📊 EMA({FAST_EMA}/{SLOW_EMA}) + RSI({RSI_PERIOD}) | 15min\n"
        f"📋 Watching {len(STOCKS)} NSE stocks\n"
        f"🕙 Daily report at 10:00 PM IST\n"
        "<i>Active during market hours only (9:15–3:30 IST)</i>"
    )

    while True:
        maybe_send_daily_report()
        if in_market_hours():
            run_scan()
        else:
            log.info("Outside market hours. Waiting...")
        time.sleep(SCAN_INTERVAL)

if __name__ == "__main__":
    main()
