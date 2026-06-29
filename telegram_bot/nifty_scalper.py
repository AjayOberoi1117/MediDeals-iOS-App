"""
Nifty / BankNifty Intraday Scalper
Strategy : Supertrend(7,2.0) flip on 15-minute candles (closed bars only)
Session  : 9:15 AM – 3:15 PM IST (auto square-off before 3:30)
Data     : Yahoo Finance with 4-min caching + retry (avoids rate limits)
Signals  : Telegram → trade manually in Upstox Scalper (MIS)
Daily P&L report at 10:00 PM IST
"""

import requests
import pandas as pd
import time
import os
import json
import socket
import yfinance as yf
from datetime import datetime
from dotenv import load_dotenv
from whatsapp import wapp_send
from emailer import email_send

load_dotenv()
socket.setdefaulttimeout(30)

TELEGRAM_TOKEN = os.getenv("STOCX_BOT_TOKEN", "")
CHAT_ID        = os.getenv("SIGNAL_CHAT_ID", "7093601171")

INSTRUMENTS = {
    "NIFTY":     "^NSEI",
    "BANKNIFTY": "^NSEBANK",
}

ST_PERIOD     = 7
ST_MULTIPLIER = 2.0
SL_PCT        = 0.4
TP_PCT        = 0.8
MARKET_OPEN   = (9, 15)
MARKET_CLOSE  = (15, 15)
SCAN_INTERVAL = 60
COOLDOWN      = 1800
CACHE_TTL     = 240   # 4-min cache for 15m bars

_last_signal       = {}
_seen_bars         = {}
_daily_signals     = []
_report_sent_date  = None
_cache             = {}

STATE_FILE  = os.path.join(os.path.dirname(__file__), ".state_nifty_scalper.json")
SEEN_FILE   = os.path.join(os.path.dirname(__file__), ".seen_nifty")

def _load_state():
    global _last_signal
    try:
        with open(STATE_FILE) as f: _last_signal = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError): pass

def _save_state():
    try:
        with open(STATE_FILE, "w") as f: json.dump(_last_signal, f)
    except Exception: pass

def _load_seen():
    try:
        with open(SEEN_FILE) as f:
            for line in f:
                parts = line.strip().split("|")
                if len(parts) == 2:
                    sym, bar = parts
                    _seen_bars.setdefault(sym, set()).add(bar)
    except FileNotFoundError: pass

def _save_seen(symbol, bar_ts):
    with open(SEEN_FILE, "a") as f: f.write(f"{symbol}|{bar_ts}\n")

def send_telegram(msg):
    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
    try:
        r = requests.post(url, data={"chat_id": CHAT_ID, "text": msg, "parse_mode": "HTML"}, timeout=10)
        if r.status_code != 200: print(f"Telegram error: {r.status_code}")
    except Exception as e: print(f"Telegram exception: {e}")
    wapp_send(msg)
    email_send("Trading Signal: Nifty Scalper", msg)

def record_signal(symbol, direction, price, sl, tp):
    _daily_signals.append({"symbol": symbol, "direction": direction, "price": price,
                            "sl": sl, "tp": tp, "time": datetime.now().strftime("%I:%M %p")})

def send_daily_report():
    today = datetime.now().strftime("%d %b %Y"); n = len(_daily_signals)
    lines = [f"📊 <b>Daily Signal Report — {today}</b>", "━━━━━━━━━━━━━━━━━━━━━━",
             f"<b>Nifty Scalper</b>  |  Signals Today: <b>{n}</b>", ""]
    if n == 0: lines.append("No signals were generated today.")
    else:
        for i, s in enumerate(_daily_signals, 1):
            em = "🟢" if s["direction"] == "BUY" else "🔴"
            rr = round(abs(s["tp"] - s["price"]) / max(abs(s["sl"] - s["price"]), 0.01), 1)
            lines.append(f"{i}. {em} <b>{s['symbol']}</b> {s['direction']}  @  {s['time']}\n"
                         f"   Entry ₹{s['price']}  •  SL ₹{s['sl']}  •  TP ₹{s['tp']}  •  RR 1:{rr}")
    lines += ["", "━━━━━━━━━━━━━━━━━━━━━━", "📌 <i>Check Upstox app for actual P&amp;L</i>"]
    send_telegram("\n".join(lines))

def maybe_send_daily_report():
    global _report_sent_date, _daily_signals
    now = datetime.now(); today = now.date()
    if now.hour == 22 and now.minute < 2 and _report_sent_date != today:
        _report_sent_date = today; send_daily_report()
    if now.hour == 0 and now.minute < 2:
        if _daily_signals and _daily_signals[0]["time"] != datetime.now().strftime("%I:%M %p"):
            _daily_signals.clear()

def _yf_download(ticker, period, interval):
    for attempt in range(3):
        try:
            df = yf.download(ticker, period=period, interval=interval, progress=False, auto_adjust=True)
            if df is not None and not df.empty: return df
        except Exception as exc:
            print(f"  yfinance attempt {attempt+1} failed: {exc}")
        if attempt < 2: time.sleep(5 * (2 ** attempt))
    return None

def fetch_15min_candles(symbol, yf_ticker):
    cache_key = f"{yf_ticker}_15m"
    now = time.time()
    cached = _cache.get(cache_key)
    if cached and now - cached[0] < CACHE_TTL: return cached[1]
    try:
        df = _yf_download(yf_ticker, "5d", "15m")
        if df is None or df.empty:
            print(f"  {symbol}: yfinance returned no data"); return pd.DataFrame()
        if isinstance(df.columns, pd.MultiIndex): df.columns = [col[0].lower() for col in df.columns]
        else: df.columns = [str(c).lower() for c in df.columns]
        df = df[["open", "high", "low", "close", "volume"]].copy()
        df.index = pd.to_datetime(df.index)
        df = df.between_time("03:45", "10:00")
        df.dropna(inplace=True)
        df.reset_index(inplace=True)
        df.rename(columns={"index": "time", "datetime": "time", "date": "time"}, errors="ignore", inplace=True)
        if "time" not in df.columns: df.rename(columns={df.columns[0]: "time"}, inplace=True)
        if len(df) < 10:
            print(f"  {symbol}: only {len(df)} 15-min candles"); return pd.DataFrame()
        _cache[cache_key] = (now, df)
        print(f"  {symbol}: {len(df)} candles | ₹{float(df['close'].iloc[-1]):.2f}")
        return df
    except Exception as e:
        print(f"  {symbol}: fetch error — {e}"); return pd.DataFrame()

def calculate_supertrend(df, period=10, multiplier=3.0):
    hl2 = (df["high"] + df["low"]) / 2
    prev_close = df["close"].shift(1)
    tr = pd.concat([df["high"]-df["low"], (df["high"]-prev_close).abs(), (df["low"]-prev_close).abs()], axis=1).max(axis=1)
    atr = tr.ewm(span=period, adjust=False).mean()
    upper_band = hl2 + multiplier * atr
    lower_band = hl2 - multiplier * atr
    supertrend = pd.Series(index=df.index, dtype=float)
    direction  = pd.Series(index=df.index, dtype=int)
    for i in range(1, len(df)):
        if upper_band.iloc[i] < upper_band.iloc[i-1] or df["close"].iloc[i-1] > upper_band.iloc[i-1]:
            upper_band.iloc[i] = upper_band.iloc[i]
        else: upper_band.iloc[i] = upper_band.iloc[i-1]
        if lower_band.iloc[i] > lower_band.iloc[i-1] or df["close"].iloc[i-1] < lower_band.iloc[i-1]:
            lower_band.iloc[i] = lower_band.iloc[i]
        else: lower_band.iloc[i] = lower_band.iloc[i-1]
        if i == 1: direction.iloc[i] = 1
        elif supertrend.iloc[i-1] == upper_band.iloc[i-1]:
            direction.iloc[i] = -1 if df["close"].iloc[i] > upper_band.iloc[i] else 1
        else: direction.iloc[i] = 1 if df["close"].iloc[i] < lower_band.iloc[i] else -1
        supertrend.iloc[i] = lower_band.iloc[i] if direction.iloc[i] == 1 else upper_band.iloc[i]
    df = df.copy()
    df["supertrend"] = supertrend; df["st_direction"] = direction
    df["upper_band"] = upper_band; df["lower_band"] = lower_band
    return df

def check_signal(symbol, df):
    df = calculate_supertrend(df, ST_PERIOD, ST_MULTIPLIER)
    if len(df) < 4: return None
    live_price = float(df.iloc[-1]["close"])
    curr = df.iloc[-2]; prev = df.iloc[-3]
    bar_ts = str(curr.get("time", df.index[-2]))
    if bar_ts in _seen_bars.get(symbol, set()): return None
    st_now = int(curr["st_direction"]); st_prev = int(prev["st_direction"])
    st_flipped = st_now != st_prev; direction = None
    if st_flipped and st_now == 1: direction = "BUY"
    elif st_flipped and st_now == -1: direction = "SELL"
    if not direction:
        _seen_bars.setdefault(symbol, set()).add(bar_ts); return None
    price = live_price
    if direction == "BUY":
        sl = round(price * (1 - SL_PCT / 100), 2); tp = round(price * (1 + TP_PCT / 100), 2)
    else:
        sl = round(price * (1 + SL_PCT / 100), 2); tp = round(price * (1 - TP_PCT / 100), 2)
    return direction, price, sl, tp

def format_signal(symbol, direction, price, sl, tp):
    emoji = "🟢 BUY" if direction == "BUY" else "🔴 SELL"
    now_ist = datetime.now().strftime("%d %b %Y %I:%M %p IST")
    rr = round(abs(tp - price) / max(abs(sl - price), 0.01), 1)
    return (f"━━━━━━━━━━━━━━━━━━━━━━\n⚡ <b>NIFTY SCALPER — {symbol}</b>\n━━━━━━━━━━━━━━━━━━━━━━\n\n"
            f"📈 <b>Signal    :</b> {emoji}\n📅 <b>Time      :</b> {now_ist}\n⏱ <b>Timeframe :</b> 15 Minutes\n\n"
            f"📍 <b>Entry     :</b> ₹<code>{price:.2f}</code>\n🛑 <b>Stop Loss :</b> ₹<code>{sl:.2f}</code>\n"
            f"🎯 <b>Target    :</b> ₹<code>{tp:.2f}</code>\n\n⚖️ <b>Risk/Reward:</b> 1 : {rr}\n\n"
            f"💡 🔄 Supertrend flipped — fresh trend reversal\n\n"
            f"🏦 <i>Place as MIS (Intraday) in Upstox Scalper</i>\n"
            f"⚠️ <i>Set SL first! Square off before 3:15 PM IST</i>\n━━━━━━━━━━━━━━━━━━━━━━")

def in_market_hours():
    now = datetime.now()
    return MARKET_OPEN <= (now.hour, now.minute) <= MARKET_CLOSE

def run_scan():
    print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Scanning Nifty + BankNifty...")
    for symbol, yf_ticker in INSTRUMENTS.items():
        print(f"  {symbol:<12}", end=" ")
        last = _last_signal.get(symbol, {})
        if last and time.time() - last.get("timestamp", 0) < COOLDOWN:
            remaining = int((COOLDOWN - (time.time() - last["timestamp"])) / 60)
            print(f"cooldown ({remaining}m remaining)"); continue
        df = fetch_15min_candles(symbol, yf_ticker)
        if df.empty: continue
        result = check_signal(symbol, df)
        if result:
            direction, price, sl, tp = result
            bar_ts = str(df.iloc[-2].get("time", ""))
            _seen_bars.setdefault(symbol, set()).add(bar_ts); _save_seen(symbol, bar_ts)
            print(f"→ {direction} | Entry ₹{price} | SL ₹{sl} | TP ₹{tp}")
            send_telegram(format_signal(symbol, direction, price, sl, tp))
            record_signal(symbol, direction, price, sl, tp)
            _last_signal[symbol] = {"direction": direction, "timestamp": time.time()}
            _save_state()
        else: print("no signal")

def main():
    _load_state(); _load_seen()
    print("=" * 55)
    print("  Nifty/BankNifty Intraday Scalper")
    print(f"  Supertrend({ST_PERIOD},{ST_MULTIPLIER}) | 15-min | MIS")
    print("=" * 55)
    send_telegram(f"⚡ <b>Nifty Scalper Started</b>\n📅 {datetime.now().strftime('%d %b %Y %I:%M %p IST')}\n"
                  f"📊 Supertrend({ST_PERIOD},{ST_MULTIPLIER}) | 15min\n🎯 NIFTY + BANKNIFTY\n"
                  "🕙 Daily report at 10:00 PM IST\n<i>Signals for Upstox MIS (Intraday)</i>")
    while True:
        try:
            maybe_send_daily_report()
            if in_market_hours(): run_scan()
            else: print(f"[{datetime.now().strftime('%H:%M')}] Outside market hours. Waiting...")
        except Exception as exc: print(f"[{datetime.now().strftime('%H:%M')}] Main loop error: {exc}")
        time.sleep(SCAN_INTERVAL)

if __name__ == "__main__":
    main()
