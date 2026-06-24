"""
Nifty / BankNifty Intraday Scalper
Strategy : Supertrend(7,2.0) flip on 15-minute candles (closed bars only)
Session  : 9:15 AM – 3:15 PM IST (auto square-off before 3:30)
Data     : TradingView via tvdatafeed (no API key, no rate limits)
Signals  : Telegram → trade manually in Upstox Scalper (MIS)
Daily P&L report at 10:00 PM IST
"""

import requests
import pandas as pd
import time
import os
import json
from datetime import datetime
from dotenv import load_dotenv
from tvdatafeed import TvDatafeed, Interval
from whatsapp import wapp_send
from emailer import email_send

load_dotenv()

# ── TradingView data source ────────────────────────────────────────────────────

tv = TvDatafeed()

# ─────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────

TELEGRAM_TOKEN = os.getenv("STOCX_BOT_TOKEN", "8649245457:AAFpe95Us_eiVTuewD1f7TJG2gRwUMX0zuA")
CHAT_ID        = os.getenv("SIGNAL_CHAT_ID", "1994067941")

INSTRUMENTS = {
    "NIFTY":     "NSE",
    "BANKNIFTY": "NSE",
}

ST_PERIOD     = 7
ST_MULTIPLIER = 2.0
SL_PCT        = 0.4
TP_PCT        = 0.8
MARKET_OPEN   = (9, 15)
MARKET_CLOSE  = (15, 15)
SCAN_INTERVAL = 60
COOLDOWN      = 1800

# ─────────────────────────────────────────────
# STATE
# ─────────────────────────────────────────────

_last_signal       = {}
_seen_bars         = {}
_daily_signals     = []
_report_sent_date  = None

STATE_FILE  = os.path.join(os.path.dirname(__file__), ".state_nifty_scalper.json")
SEEN_FILE   = os.path.join(os.path.dirname(__file__), ".seen_nifty")

def _load_state():
    global _last_signal
    try:
        with open(STATE_FILE) as f:
            _last_signal = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        pass

def _save_state():
    try:
        with open(STATE_FILE, "w") as f:
            json.dump(_last_signal, f)
    except Exception:
        pass

def _load_seen():
    try:
        with open(SEEN_FILE) as f:
            for line in f:
                parts = line.strip().split("|")
                if len(parts) == 2:
                    sym, bar = parts
                    _seen_bars.setdefault(sym, set()).add(bar)
    except FileNotFoundError:
        pass

def _save_seen(symbol, bar_ts):
    with open(SEEN_FILE, "a") as f:
        f.write(f"{symbol}|{bar_ts}\n")

# ─────────────────────────────────────────────
# TELEGRAM
# ─────────────────────────────────────────────

def send_telegram(msg: str):
    url  = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
    data = {"chat_id": CHAT_ID, "text": msg, "parse_mode": "HTML"}
    try:
        r = requests.post(url, data=data, timeout=10)
        if r.status_code != 200:
            print(f"Telegram error: {r.status_code}")
    except Exception as e:
        print(f"Telegram exception: {e}")
    wapp_send(msg)
    email_send("Trading Signal: Nifty Scalper", msg)

# ─────────────────────────────────────────────
# DAILY P&L REPORT
# ─────────────────────────────────────────────

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
        f"<b>Nifty Scalper</b>  |  Signals Today: <b>{n}</b>",
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
                f"   Entry ₹{s['price']}  •  SL ₹{s['sl']}  •  TP ₹{s['tp']}  •  RR 1:{rr}"
            )
    lines += [
        "",
        "━━━━━━━━━━━━━━━━━━━━━━",
        "📌 <i>Check Upstox app for actual P&amp;L</i>",
    ]
    send_telegram("\n".join(lines))

def maybe_send_daily_report():
    global _report_sent_date, _daily_signals
    now   = datetime.now()
    today = now.date()
    if now.hour == 22 and now.minute < 2 and _report_sent_date != today:
        _report_sent_date = today
        send_daily_report()
    if now.hour == 0 and now.minute < 2:
        if _daily_signals and _daily_signals[0]["time"] != datetime.now().strftime("%I:%M %p"):
            _daily_signals.clear()

# ─────────────────────────────────────────────
# DATA FETCHING
# ─────────────────────────────────────────────

def fetch_15min_candles(symbol: str, exchange: str) -> pd.DataFrame:
    try:
        df = tv.get_hist(symbol, exchange, interval=Interval.in_15_minute, n_bars=100)
        if df is None or df.empty:
            print(f"  {symbol}: tvdatafeed returned no data")
            return pd.DataFrame()

        df.columns = [c.lower() for c in df.columns]
        df = df[["open", "high", "low", "close", "volume"]].copy()
        df.dropna(inplace=True)

        if len(df) < 10:
            print(f"  {symbol}: only {len(df)} 15-min candles")
            return pd.DataFrame()

        print(f"  {symbol}: {len(df)} candles | ₹{float(df['close'].iloc[-1]):.2f}")
        return df
    except Exception as e:
        print(f"  {symbol}: fetch error — {e}")
        return pd.DataFrame()

# ─────────────────────────────────────────────
# INDICATORS
# ─────────────────────────────────────────────

def calculate_supertrend(df: pd.DataFrame, period: int = 10, multiplier: float = 3.0):
    hl2        = (df["high"] + df["low"]) / 2
    prev_close = df["close"].shift(1)
    tr = pd.concat([
        df["high"] - df["low"],
        (df["high"] - prev_close).abs(),
        (df["low"]  - prev_close).abs(),
    ], axis=1).max(axis=1)
    atr        = tr.ewm(span=period, adjust=False).mean()
    upper_band = hl2 + multiplier * atr
    lower_band = hl2 - multiplier * atr
    supertrend = pd.Series(index=df.index, dtype=float)
    direction  = pd.Series(index=df.index, dtype=int)

    for i in range(1, len(df)):
        if upper_band.iloc[i] < upper_band.iloc[i-1] or df["close"].iloc[i-1] > upper_band.iloc[i-1]:
            upper_band.iloc[i] = upper_band.iloc[i]
        else:
            upper_band.iloc[i] = upper_band.iloc[i-1]

        if lower_band.iloc[i] > lower_band.iloc[i-1] or df["close"].iloc[i-1] < lower_band.iloc[i-1]:
            lower_band.iloc[i] = lower_band.iloc[i]
        else:
            lower_band.iloc[i] = lower_band.iloc[i-1]

        if i == 1:
            direction.iloc[i] = 1
        elif supertrend.iloc[i-1] == upper_band.iloc[i-1]:
            direction.iloc[i] = -1 if df["close"].iloc[i] > upper_band.iloc[i] else 1
        else:
            direction.iloc[i] = 1 if df["close"].iloc[i] < lower_band.iloc[i] else -1

        supertrend.iloc[i] = lower_band.iloc[i] if direction.iloc[i] == 1 else upper_band.iloc[i]

    df = df.copy()
    df["supertrend"]   = supertrend
    df["st_direction"] = direction
    df["upper_band"]   = upper_band
    df["lower_band"]   = lower_band
    return df

# ─────────────────────────────────────────────
# SIGNAL CHECK
# ─────────────────────────────────────────────

def check_signal(symbol: str, df: pd.DataFrame):
    df = calculate_supertrend(df, ST_PERIOD, ST_MULTIPLIER)
    if len(df) < 4:
        return None

    live_price = float(df.iloc[-1]["close"])
    curr = df.iloc[-2]
    prev = df.iloc[-3]

    bar_ts = str(df.index[-2])
    if bar_ts in _seen_bars.get(symbol, set()):
        return None

    st_now     = int(curr["st_direction"])
    st_prev    = int(prev["st_direction"])
    st_flipped = st_now != st_prev
    direction  = None

    if st_flipped and st_now == 1:
        direction = "BUY"
    elif st_flipped and st_now == -1:
        direction = "SELL"

    if not direction:
        _seen_bars.setdefault(symbol, set()).add(bar_ts)
        return None

    price = live_price
    if direction == "BUY":
        sl = round(price * (1 - SL_PCT / 100), 2)
        tp = round(price * (1 + TP_PCT / 100), 2)
    else:
        sl = round(price * (1 + SL_PCT / 100), 2)
        tp = round(price * (1 - TP_PCT / 100), 2)

    return direction, price, sl, tp

# ─────────────────────────────────────────────
# SIGNAL FORMATTER
# ─────────────────────────────────────────────

def format_signal(symbol, direction, price, sl, tp):
    emoji   = "🟢 BUY" if direction == "BUY" else "🔴 SELL"
    now_ist = datetime.now().strftime("%d %b %Y %I:%M %p IST")
    rr      = round(abs(tp - price) / max(abs(sl - price), 0.01), 1)
    return (
        f"━━━━━━━━━━━━━━━━━━━━━━\n"
        f"⚡ <b>NIFTY SCALPER — {symbol}</b>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━\n\n"
        f"📈 <b>Signal    :</b> {emoji}\n"
        f"📅 <b>Time      :</b> {now_ist}\n"
        f"⏱ <b>Timeframe :</b> 15 Minutes\n\n"
        f"📍 <b>Entry     :</b> ₹<code>{price:.2f}</code>\n"
        f"🛑 <b>Stop Loss :</b> ₹<code>{sl:.2f}</code>\n"
        f"🎯 <b>Target    :</b> ₹<code>{tp:.2f}</code>\n\n"
        f"⚖️ <b>Risk/Reward:</b> 1 : {rr}\n\n"
        f"💡 🔄 Supertrend flipped — fresh trend reversal\n\n"
        f"🏦 <i>Place as MIS (Intraday) in Upstox Scalper</i>\n"
        f"⚠️ <i>Set SL first! Square off before 3:15 PM IST</i>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━"
    )

# ─────────────────────────────────────────────
# MARKET HOURS
# ─────────────────────────────────────────────

def in_market_hours():
    now = datetime.now()
    return MARKET_OPEN <= (now.hour, now.minute) <= MARKET_CLOSE

# ─────────────────────────────────────────────
# MAIN LOOP
# ─────────────────────────────────────────────

def run_scan():
    print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Scanning Nifty + BankNifty...")
    for symbol, exchange in INSTRUMENTS.items():
        print(f"  {symbol:<12}", end=" ")

        last = _last_signal.get(symbol, {})
        if last and time.time() - last.get("timestamp", 0) < COOLDOWN:
            remaining = int((COOLDOWN - (time.time() - last["timestamp"])) / 60)
            print(f"cooldown ({remaining}m remaining)")
            continue

        df = fetch_15min_candles(symbol, exchange)
        if df.empty:
            continue

        result = check_signal(symbol, df)
        if result:
            direction, price, sl, tp = result
            bar_ts = str(df.index[-2])
            _seen_bars.setdefault(symbol, set()).add(bar_ts)
            _save_seen(symbol, bar_ts)
            print(f"→ {direction} | Entry ₹{price} | SL ₹{sl} | TP ₹{tp}")
            send_telegram(format_signal(symbol, direction, price, sl, tp))
            record_signal(symbol, direction, price, sl, tp)
            _last_signal[symbol] = {"direction": direction, "timestamp": time.time()}
            _save_state()
        else:
            print("no signal")

def main():
    _load_state()
    _load_seen()
    print("=" * 55)
    print("  Nifty/BankNifty Intraday Scalper")
    print(f"  Supertrend({ST_PERIOD},{ST_MULTIPLIER}) | 15-min | MIS")
    print("  Data: TradingView (tvdatafeed)")
    print("=" * 55)
    send_telegram(
        "⚡ <b>Nifty Scalper Started</b>\n"
        f"📅 {datetime.now().strftime('%d %b %Y %I:%M %p IST')}\n"
        f"📊 Supertrend({ST_PERIOD},{ST_MULTIPLIER}) | 15min  [TradingView data]\n"
        "🎯 NIFTY + BANKNIFTY\n"
        "🕙 Daily report at 10:00 PM IST\n"
        "<i>Signals for Upstox MIS (Intraday)</i>"
    )
    while True:
        try:
            maybe_send_daily_report()
            if in_market_hours():
                run_scan()
            else:
                print(f"[{datetime.now().strftime('%H:%M')}] Outside market hours. Waiting...")
        except Exception as exc:
            print(f"[{datetime.now().strftime('%H:%M')}] Main loop error: {exc}")
        time.sleep(SCAN_INTERVAL)

if __name__ == "__main__":
    main()
