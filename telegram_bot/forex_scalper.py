"""
Forex + Gold 15-Minute Scalper Bot
Strategy : EMA(9/21) crossover + RSI(14) on 15-minute bars
Symbols  : EURUSD, GBPUSD, USDJPY, XAUUSD
Data     : TradingView via tvdatafeed (no API key, no rate limits)
Signals  : Entry, SL, TP (ATR-based 1:2 RR) via Telegram
Report   : Daily summary at 10:00 PM IST
"""

import os
import time
import logging
from datetime import datetime

import pandas as pd
from tvdatafeed import TvDatafeed, Interval
import requests
from dotenv import load_dotenv
from whatsapp import wapp_send
from emailer import email_send

try:
    from trade_executor import queue_trade
except ImportError:
    def queue_trade(*args, **kwargs): pass

load_dotenv()

# ── TradingView data source ────────────────────────────────────────────────────

tv = TvDatafeed()

_TV_MAP = {
    "EURUSD": ("EURUSD", "FX_IDC"),
    "GBPUSD": ("GBPUSD", "FX_IDC"),
    "USDJPY": ("USDJPY", "FX_IDC"),
    "XAUUSD": ("XAUUSD", "OANDA"),
}

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
ATR_TP_MULT    = 2.0
COOLDOWN_SECS  = 7200
SCAN_INTERVAL  = 60

SYMBOLS = ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD"]

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    format="%(asctime)s | SCALPER  | %(levelname)s | %(message)s",
    level=logging.INFO,
)
log = logging.getLogger(__name__)

# ── State ─────────────────────────────────────────────────────────────────────

_last_signal      = {}
_seen_bars        = {}
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

def fetch_data(name):
    sym, exch = _TV_MAP[name]
    try:
        df = tv.get_hist(sym, exch, interval=Interval.in_15_minute, n_bars=100)
        if df is None or df.empty or len(df) < SLOW_EMA + 5:
            return None
        df.columns = [c.lower() for c in df.columns]
        return df
    except Exception as exc:
        log.debug("Fetch error %s: %s", name, exc)
        return None

def get_1h_trend(name) -> int:
    sym, exch = _TV_MAP[name]
    try:
        df = tv.get_hist(sym, exch, interval=Interval.in_1_hour, n_bars=60)
        if df is None or df.empty or len(df) < 52:
            return 0
        df.columns = [c.lower() for c in df.columns]
        close = df["close"]
        ema50 = close.ewm(span=50, adjust=False).mean()
        return 1 if float(close.iloc[-1]) > float(ema50.iloc[-1]) else -1
    except Exception:
        return 0

# ── Signal check ──────────────────────────────────────────────────────────────

def check_symbol(name):
    df = fetch_data(name)
    if df is None:
        return

    now_ts = time.time()
    if now_ts - _last_signal.get(name, 0) < COOLDOWN_SECS:
        return

    close = df["close"]
    high  = df["high"]
    low   = df["low"]

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

    _atr_min = {"EURUSD": 0.00100, "GBPUSD": 0.00120, "USDJPY": 0.12, "XAUUSD": 2.0}
    atr_val = max(atr_val, _atr_min.get(name, atr_val))

    _seen_bars.setdefault(name, set()).add(bar_ts)
    _save_seen(name, bar_ts)

    is_gold = name == "XAUUSD"
    dec     = 2 if (is_gold or "JPY" in name) else 5
    pfx     = "$" if is_gold else ""
    rr      = round(ATR_TP_MULT / ATR_SL_MULT, 1)

    if bull_cross and rsi_val < RSI_BUY_MAX:
        if get_1h_trend(name) == -1:
            log.info("SKIP BUY  %s — 1H trend bearish", name)
            return
        entry = round(price, dec)
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
        if get_1h_trend(name) == 1:
            log.info("SKIP SELL %s — 1H trend bullish", name)
            return
        entry = round(price, dec)
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
        f"📊 EMA({FAST_EMA}/{SLOW_EMA}) + RSI({RSI_PERIOD}) | 15min  [TradingView data]\n"
        f"💱 EURUSD  •  GBPUSD  •  USDJPY  •  XAUUSD\n"
        f"⚖️ SL = 1x ATR  |  TP = 2x ATR\n"
        f"🕙 Daily report at 10:00 PM IST"
    )

    while True:
        try:
            maybe_send_daily_report()
            for name in SYMBOLS:
                try:
                    check_symbol(name)
                except Exception as exc:
                    log.debug("Error on %s: %s", name, exc)
                time.sleep(2)
        except Exception as exc:
            log.error("Unexpected error: %s", exc)
        time.sleep(SCAN_INTERVAL)

if __name__ == "__main__":
    main()
