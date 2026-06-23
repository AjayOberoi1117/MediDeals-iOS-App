"""
Forex + Gold 15-Minute Scalper Bot
Strategy : EMA(9/21) crossover + RSI(14) on 15-minute bars
Symbols  : EURUSD, GBPUSD, USDJPY, XAUUSD
Signals  : Entry, SL, TP (ATR-based 1:1.5 RR) via Telegram
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
from whatsapp import wapp_send
from emailer import email_send
from trade_executor import queue_trade

load_dotenv()

# Yahoo Finance calls have no built-in timeout — without this, a Yahoo
# rate-limit/throttle episode can block the single-threaded main loop
# indefinitely.
socket.setdefaulttimeout(30)

# ── Config ────────────────────────────────────────────────────────────────────

TELEGRAM_TOKEN = os.getenv("ELITE_BOT_TOKEN", "")
CHAT_ID        = os.getenv("SIGNAL_CHAT_ID", "1994067941")

TIMEFRAME      = "15m"
FAST_EMA       = 9
SLOW_EMA       = 21
RSI_PERIOD     = 14
RSI_BUY_MAX    = 60
RSI_SELL_MIN   = 40
ATR_PERIOD     = 14
ATR_SL_MULT    = 1.0
ATR_TP_MULT    = 2.0    # 1:2 RR — minimum worthwhile for scalping
COOLDOWN_SECS  = 7200   # 2-hour cooldown per symbol
SCAN_INTERVAL  = 60     # scan every 60 seconds
TWELVE_DATA_KEY = os.getenv("TWELVE_DATA_KEY", "")

_TD_MAP = {"EURUSD": "EUR/USD", "GBPUSD": "GBP/USD", "USDJPY": "USD/JPY", "XAUUSD": "XAU/USD"}

# Approximate half-spread per symbol (mid → ASK for BUY, mid → BID for SELL)
_SPREAD = {"EURUSD": 0.00010, "GBPUSD": 0.00015, "USDJPY": 0.012, "XAUUSD": 0.30}

SYMBOLS = {
    "EURUSD": "EURUSD=X",
    "GBPUSD": "GBPUSD=X",
    "USDJPY": "USDJPY=X",
    "XAUUSD": "GC=F",   # XAUUSD=X was delisted by Yahoo — use Gold Futures instead
}

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    format="%(asctime)s | SCALPER  | %(levelname)s | %(message)s",
    level=logging.INFO,
)
log = logging.getLogger(__name__)

# ── State ─────────────────────────────────────────────────────────────────────

_last_signal      = {}   # {name: timestamp}
_seen_bars        = {}   # {name: set of bar timestamps}
_daily_signals    = []
_report_sent_date = None

SEEN_FILE = os.path.join(os.path.dirname(__file__), ".seen_scalper")

def _load_seen():
    try:
        with open(SEEN_FILE) as f:
            for line in f:
                parts = line.strip().split("|")
                if len(parts) == 2:
                    name, bar = parts
                    _seen_bars.setdefault(name, set()).add(bar)
    except FileNotFoundError:
        pass

def _save_seen(name, bar_ts):
    with open(SEEN_FILE, "a") as f:
        f.write(f"{name}|{bar_ts}\n")

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
    email_send("Trading Signal: Forex Scalper", text)

# ── Daily report ──────────────────────────────────────────────────────────────

def record_signal(name, direction, price, sl, tp):
    _daily_signals.append({
        "name":      name,
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
        f"📊 <b>Daily Scalper Report — {today}</b>",
        "━━━━━━━━━━━━━━━━━━━━━━",
        f"<b>Forex + Gold Scalper</b>  |  Signals Today: <b>{n}</b>",
        "",
    ]
    if n == 0:
        lines.append("No signals were generated today.")
    else:
        for i, s in enumerate(_daily_signals, 1):
            em = "🟢" if s["direction"] == "BUY" else "🔴"
            rr = round(abs(s["tp"] - s["price"]) / max(abs(s["sl"] - s["price"]), 0.00001), 1)
            dec = 2 if s["name"] == "XAUUSD" else 5
            lines.append(
                f"{i}. {em} <b>{s['name']}</b> {s['direction']}  @  {s['time']}\n"
                f"   Entry {s['price']:.{dec}f}  •  SL {s['sl']:.{dec}f}  •  TP {s['tp']:.{dec}f}  •  RR 1:{rr}"
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

def calc_rsi(close, period):
    delta    = close.diff()
    avg_gain = delta.clip(lower=0).ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    avg_loss = (-delta.clip(upper=0)).ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    return 100 - 100 / (1 + avg_gain / avg_loss)

def calc_atr(high, low, close, period):
    prev_close = close.shift(1)
    tr = pd.concat([
        high - low,
        (high - prev_close).abs(),
        (low  - prev_close).abs(),
    ], axis=1).max(axis=1)
    return tr.ewm(span=period, adjust=False).mean()

# ── Data fetch ────────────────────────────────────────────────────────────────

def fetch_data(ticker):
    try:
        df = yf.download(ticker, period="5d", interval=TIMEFRAME,
                         progress=False, auto_adjust=True)
        if df.empty or len(df) < SLOW_EMA + 5:
            return None
        if isinstance(df.columns, pd.MultiIndex):
            df.columns = [col[0] for col in df.columns]
        df = df[["Open", "High", "Low", "Close", "Volume"]].copy()
        df.dropna(inplace=True)
        return df if len(df) >= SLOW_EMA + 5 else None
    except Exception as exc:
        log.debug("Fetch error %s: %s", ticker, exc)
        return None

# ── Live price: Twelve Data (primary, real-time) → yfinance (fallback) ───────

def fetch_live_price(name):
    # Primary: Twelve Data — real-time forex prices
    td_sym = _TD_MAP.get(name)
    if TWELVE_DATA_KEY and td_sym:
        try:
            r = requests.get("https://api.twelvedata.com/price",
                             params={"symbol": td_sym, "apikey": TWELVE_DATA_KEY},
                             timeout=5)
            val = float(r.json().get("price", 0))
            if val > 0:
                return val
        except Exception:
            pass
    # Fallback: yfinance fast_info (used only if Twelve Data is unreachable)
    ticker = SYMBOLS.get(name)
    if ticker:
        try:
            info = yf.Ticker(ticker).fast_info
            price = info.get("lastPrice") or info.get("last_price")
            if price and float(price) > 0:
                return float(price)
        except Exception:
            pass
    return None

# ── Higher-timeframe trend filter ────────────────────────────────────────────
# Only trade in the direction of the 1H trend. Prevents entering counter-trend
# scalps that are the primary cause of SL hits on EMA crossover strategies.

def get_1h_trend(yf_ticker: str) -> int:
    """Returns 1 (bullish), -1 (bearish), 0 (unknown). Uses 1H EMA(50)."""
    try:
        df = yf.download(yf_ticker, period="30d", interval="1h",
                         progress=False, auto_adjust=True)
        if df.empty or len(df) < 52:
            return 0
        if isinstance(df.columns, pd.MultiIndex):
            df.columns = [col[0] for col in df.columns]
        close = df["Close"].squeeze()
        if isinstance(close, pd.DataFrame):
            close = close.iloc[:, 0]
        ema50 = close.ewm(span=50, adjust=False).mean()
        return 1 if float(close.iloc[-1]) > float(ema50.iloc[-1]) else -1
    except Exception:
        return 0

# ── Signal check ──────────────────────────────────────────────────────────────

def check_symbol(name, ticker):
    df = fetch_data(ticker)
    if df is None:
        return

    now_ts = time.time()
    if now_ts - _last_signal.get(name, 0) < COOLDOWN_SECS:
        return

    close = df["Close"].squeeze()
    high  = df["High"].squeeze()
    low   = df["Low"].squeeze()
    if isinstance(close, pd.DataFrame): close = close.iloc[:, 0]
    if isinstance(high,  pd.DataFrame): high  = high.iloc[:,  0]
    if isinstance(low,   pd.DataFrame): low   = low.iloc[:,   0]

    fast_ema = close.ewm(span=FAST_EMA, adjust=False).mean()
    slow_ema = close.ewm(span=SLOW_EMA, adjust=False).mean()
    rsi      = calc_rsi(close, RSI_PERIOD)
    atr      = calc_atr(high, low, close, ATR_PERIOD)

    i      = -2
    bar_ts = str(df.index[i])

    if bar_ts in _seen_bars.get(name, set()):
        return

    bull_cross = (fast_ema.iloc[i]   > slow_ema.iloc[i]  ) and \
                 (fast_ema.iloc[i-1] <= slow_ema.iloc[i-1])
    bear_cross = (fast_ema.iloc[i]   < slow_ema.iloc[i]  ) and \
                 (fast_ema.iloc[i-1] >= slow_ema.iloc[i-1])

    rsi_val = float(rsi.iloc[i])
    price   = float(close.iloc[i])
    atr_val = float(atr.iloc[i])

    # Minimum ATR floor — prevents unrealistically tight SL/TP on quiet data
    _atr_min = {"EURUSD": 0.00100, "GBPUSD": 0.00120, "USDJPY": 0.12, "XAUUSD": 2.0}
    atr_val = max(atr_val, _atr_min.get(name, atr_val))

    _seen_bars.setdefault(name, set()).add(bar_ts)
    _save_seen(name, bar_ts)

    is_gold = name == "XAUUSD"
    dec     = 2 if (is_gold or "JPY" in name) else 5
    pfx     = "$" if is_gold else ""
    rr      = round(ATR_TP_MULT / ATR_SL_MULT, 1)

    spread = _SPREAD.get(name, 0)
    trend  = get_1h_trend(ticker)

    if bull_cross and rsi_val < RSI_BUY_MAX:
        if trend == -1:
            log.info("SKIP BUY  %s — 1H trend bearish (EMA50 above price)", name)
            return
        mid = fetch_live_price(name) or price
        entry = round(mid + spread, dec)   # BUY fills at ASK = mid + spread
        sl = round(entry - ATR_SL_MULT * atr_val, dec)
        tp = round(entry + ATR_TP_MULT * atr_val, dec)
        log.info("BUY  %s  entry=%.*f  sl=%.*f  tp=%.*f", name, dec, entry, dec, sl, dec, tp)
        tg_send(
            f"━━━━━━━━━━━━━━━━━━━━━━\n"
            f"⚡ <b>SCALPER — {name}</b>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━\n\n"
            f"📈 <b>Signal    :</b> 🟢 BUY\n"
            f"📅 <b>Time      :</b> {datetime.now().strftime('%d %b %Y %I:%M %p IST')}\n"
            f"⏱ <b>Timeframe :</b> 15 Minutes\n\n"
            f"📍 <b>Entry     :</b> {pfx}<code>{entry:.{dec}f}</code>\n"
            f"🛑 <b>Stop Loss :</b> {pfx}<code>{sl:.{dec}f}</code>\n"
            f"🎯 <b>Target    :</b> {pfx}<code>{tp:.{dec}f}</code>\n\n"
            f"📊 <b>RSI(14)   :</b> {rsi_val:.1f}\n"
            f"📊 <b>ATR(14)   :</b> {pfx}{atr_val:.{dec}f}\n"
            f"⚖️ <b>Risk/Reward:</b> 1 : {rr}\n\n"
            f"💡 EMA({FAST_EMA}/{SLOW_EMA}) bullish cross — 15min\n"
            f"⚠️ <i>Set SL immediately after opening the trade!</i>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━"
        )
        record_signal(name, "BUY", entry, sl, tp)
        queue_trade(name, "BUY", sl, tp, source=f"{name}_15m")
        _last_signal[name] = now_ts

    elif bear_cross and rsi_val > RSI_SELL_MIN:
        if trend == 1:
            log.info("SKIP SELL %s — 1H trend bullish (EMA50 below price)", name)
            return
        mid = fetch_live_price(name) or price
        entry = round(mid - spread, dec)   # SELL fills at BID = mid - spread
        sl = round(entry + ATR_SL_MULT * atr_val, dec)
        tp = round(entry - ATR_TP_MULT * atr_val, dec)
        log.info("SELL %s  entry=%.*f  sl=%.*f  tp=%.*f", name, dec, entry, dec, sl, dec, tp)
        tg_send(
            f"━━━━━━━━━━━━━━━━━━━━━━\n"
            f"⚡ <b>SCALPER — {name}</b>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━\n\n"
            f"📉 <b>Signal    :</b> 🔴 SELL\n"
            f"📅 <b>Time      :</b> {datetime.now().strftime('%d %b %Y %I:%M %p IST')}\n"
            f"⏱ <b>Timeframe :</b> 15 Minutes\n\n"
            f"📍 <b>Entry     :</b> {pfx}<code>{entry:.{dec}f}</code>\n"
            f"🛑 <b>Stop Loss :</b> {pfx}<code>{sl:.{dec}f}</code>\n"
            f"🎯 <b>Target    :</b> {pfx}<code>{tp:.{dec}f}</code>\n\n"
            f"📊 <b>RSI(14)   :</b> {rsi_val:.1f}\n"
            f"📊 <b>ATR(14)   :</b> {pfx}{atr_val:.{dec}f}\n"
            f"⚖️ <b>Risk/Reward:</b> 1 : {rr}\n\n"
            f"💡 EMA({FAST_EMA}/{SLOW_EMA}) bearish cross — 15min\n"
            f"⚠️ <i>Set SL immediately after opening the trade!</i>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━"
        )
        record_signal(name, "SELL", entry, sl, tp)
        queue_trade(name, "SELL", sl, tp, source=f"{name}_15m")
        _last_signal[name] = now_ts

# ── Main loop ─────────────────────────────────────────────────────────────────

def main():
    if not TELEGRAM_TOKEN:
        raise SystemExit("ELITE_BOT_TOKEN not set in .env")

    _load_seen()

    log.info("Forex+Gold Scalper started | pairs=%d  tf=%s  ema=%d/%d  rsi=%d  scan=%ds",
             len(SYMBOLS), TIMEFRAME, FAST_EMA, SLOW_EMA, RSI_PERIOD, SCAN_INTERVAL)

    tg_send(
        "⚡ <b>Forex + Gold Scalper Online</b>\n"
        f"📅 {datetime.now().strftime('%d %b %Y %I:%M %p IST')}\n"
        f"📊 EMA({FAST_EMA}/{SLOW_EMA}) + RSI({RSI_PERIOD}) | 15min\n"
        f"💱 EURUSD  •  GBPUSD  •  USDJPY  •  XAUUSD\n"
        f"⚖️ SL = 1x ATR  |  TP = 1.5x ATR\n"
        f"🕙 Daily report at 10:00 PM IST"
    )

    while True:
        try:
            maybe_send_daily_report()
            for name, ticker in SYMBOLS.items():
                try:
                    check_symbol(name, ticker)
                except Exception as exc:
                    log.debug("Error on %s: %s", name, exc)
                time.sleep(2)
        except Exception as exc:
            log.error("Unexpected error: %s", exc)
        time.sleep(SCAN_INTERVAL)

if __name__ == "__main__":
    main()
