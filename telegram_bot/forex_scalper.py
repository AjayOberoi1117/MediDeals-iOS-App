"""
Forex + Gold 15-Minute Scalper Bot
Strategy : EMA(9/21) crossover + RSI(14) on 15-minute bars
Symbols  : EURUSD, GBPUSD, USDJPY, XAUUSD
Signals  : Entry, SL, TP (ATR-based 1:1.5 RR) via Telegram
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
ATR_TP_MULT    = 1.5    # 1:1.5 RR — tight scalp
COOLDOWN_SECS  = 7200   # 2-hour cooldown per symbol
SCAN_INTERVAL  = 60     # scan every 60 seconds

SYMBOLS = {
    "EURUSD": "EURUSD=X",
    "GBPUSD": "GBPUSD=X",
    "USDJPY": "USDJPY=X",
    "XAUUSD": "XAUUSD=X",
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

    _seen_bars.setdefault(name, set()).add(bar_ts)
    _save_seen(name, bar_ts)

    is_gold = name == "XAUUSD"
    rr      = round(ATR_TP_MULT / ATR_SL_MULT, 1)

    if is_gold:
        sl_dist = round(ATR_SL_MULT * atr_val, 2)
        tp_dist = round(ATR_TP_MULT * atr_val, 2)
        atr_str = f"${atr_val:.2f}"
        sl_str  = f"$<code>{sl_dist}</code>"
        tp_str  = f"$<code>{tp_dist}</code>"
        unit    = "BELOW" ; unit2 = "ABOVE"
    else:
        pip     = 0.01 if "JPY" in name else 0.0001
        sl_dist = round(ATR_SL_MULT * atr_val / pip, 1)
        tp_dist = round(ATR_TP_MULT * atr_val / pip, 1)
        atr_str = f"{round(atr_val/pip, 1)} pips"
        sl_str  = f"<code>{sl_dist}</code> pips"
        tp_str  = f"<code>{tp_dist}</code> pips"
        unit    = "BELOW" ; unit2 = "ABOVE"

    if bull_cross and rsi_val < RSI_BUY_MAX:
        log.info("BUY  %s  sl_dist=%s  tp_dist=%s", name, sl_dist, tp_dist)
        tg_send(
            f"━━━━━━━━━━━━━━━━━━━━━━\n"
            f"⚡ <b>SCALPER — {name}</b>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━\n\n"
            f"📈 <b>Signal    :</b> 🟢 BUY\n"
            f"📅 <b>Time      :</b> {datetime.now().strftime('%d %b %Y %I:%M %p IST')}\n"
            f"⏱ <b>Timeframe :</b> 15 Minutes\n\n"
            f"📍 <b>Entry     :</b> Open BUY at your broker NOW\n"
            f"🛑 <b>Stop Loss :</b> {sl_str} {unit} your entry\n"
            f"🎯 <b>Target    :</b> {tp_str} {unit2} your entry\n\n"
            f"📊 <b>RSI(14)   :</b> {rsi_val:.1f}\n"
            f"📊 <b>ATR(14)   :</b> {atr_str}\n"
            f"⚖️ <b>Risk/Reward:</b> 1 : {rr}\n\n"
            f"💡 EMA({FAST_EMA}/{SLOW_EMA}) bullish cross — 15min\n"
            f"⚠️ <i>Set SL immediately after opening the trade!</i>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━"
        )
        sl = round(price - ATR_SL_MULT * atr_val, 2 if is_gold else 5)
        tp = round(price + ATR_TP_MULT * atr_val, 2 if is_gold else 5)
        record_signal(name, "BUY", price, sl, tp)
        _last_signal[name] = now_ts

    elif bear_cross and rsi_val > RSI_SELL_MIN:
        log.info("SELL %s  sl_dist=%s  tp_dist=%s", name, sl_dist, tp_dist)
        tg_send(
            f"━━━━━━━━━━━━━━━━━━━━━━\n"
            f"⚡ <b>SCALPER — {name}</b>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━\n\n"
            f"📉 <b>Signal    :</b> 🔴 SELL\n"
            f"📅 <b>Time      :</b> {datetime.now().strftime('%d %b %Y %I:%M %p IST')}\n"
            f"⏱ <b>Timeframe :</b> 15 Minutes\n\n"
            f"📍 <b>Entry     :</b> Open SELL at your broker NOW\n"
            f"🛑 <b>Stop Loss :</b> {sl_str} ABOVE your entry\n"
            f"🎯 <b>Target    :</b> {tp_str} BELOW your entry\n\n"
            f"📊 <b>RSI(14)   :</b> {rsi_val:.1f}\n"
            f"📊 <b>ATR(14)   :</b> {atr_str}\n"
            f"⚖️ <b>Risk/Reward:</b> 1 : {rr}\n\n"
            f"💡 EMA({FAST_EMA}/{SLOW_EMA}) bearish cross — 15min\n"
            f"⚠️ <i>Set SL immediately after opening the trade!</i>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━"
        )
        sl = round(price + ATR_SL_MULT * atr_val, 2 if is_gold else 5)
        tp = round(price - ATR_TP_MULT * atr_val, 2 if is_gold else 5)
        record_signal(name, "SELL", price, sl, tp)
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
