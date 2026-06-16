"""
Nifty / BankNifty Intraday Scalper
Strategy : Supertrend(7,2.0) flip on 15-minute candles (closed bars only)
Session  : 9:15 AM – 3:15 PM IST (auto square-off before 3:30)
Signals  : Telegram → trade manually in Upstox Scalper (MIS)
Daily P&L report at 10:00 PM IST
"""

import requests
import pandas as pd
import time
import os
import json
import yfinance as yf
from datetime import datetime, date
from dotenv import load_dotenv

load_dotenv()

# ─────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────

UPSTOX_TOKEN   = os.getenv("UPSTOX_TOKEN", "")
TELEGRAM_TOKEN = os.getenv("STOCX_BOT_TOKEN", "8649245457:AAFpe95Us_eiVTuewD1f7TJG2gRwUMX0zuA")
CHAT_ID        = os.getenv("SIGNAL_CHAT_ID", "1994067941")

HEADERS = {
    "Accept": "application/json",
    "Authorization": f"Bearer {UPSTOX_TOKEN}"
}

INSTRUMENTS = {
    "NIFTY":     {"upstox": "NSE_INDEX|Nifty 50",  "yf": "^NSEI"},
    "BANKNIFTY": {"upstox": "NSE_INDEX|Nifty Bank", "yf": "^NSEBANK"},
}

ST_PERIOD     = 7              # was 10 — faster Supertrend for intraday
ST_MULTIPLIER = 2.0            # was 3.0 — tighter bands, more signal flips
SL_PCT        = 0.4
TP_PCT        = 0.8
MARKET_OPEN   = (9, 15)
MARKET_CLOSE  = (15, 15)
SCAN_INTERVAL = 60
COOLDOWN      = 1800            # was 900 — 15min was letting VWAP wiggles re-fire too fast

# ─────────────────────────────────────────────
# STATE
# ─────────────────────────────────────────────

_last_signal       = {}
_daily_signals     = []
_report_sent_date  = None

STATE_FILE = os.path.join(os.path.dirname(__file__), ".state_nifty_scalper.json")

def _load_state():
    """Restore cooldown across restarts — without this, a process restart
    (crash or watchdog) wipes the in-memory cooldown and lets the same
    symbol fire again immediately, which looked like a signal every ~15min
    despite COOLDOWN being set to 30 minutes."""
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
    # Send at exactly 10:00 PM IST (22:00)
    if now.hour == 22 and now.minute < 2 and _report_sent_date != today:
        _report_sent_date = today
        send_daily_report()
    # Clear yesterday's log at midnight
    if now.hour == 0 and now.minute < 2:
        if _daily_signals and _daily_signals[0]["time"] != datetime.now().strftime("%I:%M %p"):
            _daily_signals.clear()

# ─────────────────────────────────────────────
# DATA FETCHING
# ─────────────────────────────────────────────

def get_live_price_upstox(symbol: str, ikey: str):
    """Try Upstox market-quote API (requires valid daily trading token)."""
    if not UPSTOX_TOKEN:
        return None
    try:
        headers = {"Accept": "application/json", "Authorization": f"Bearer {os.getenv('UPSTOX_TOKEN', '')}"}
        r = requests.get("https://api.upstox.com/v2/market-quote/quotes",
                         headers=headers,
                         params={"instrument_key": ikey},
                         timeout=5)
        if r.status_code == 200:
            data = r.json().get("data", {})
            val  = data.get(ikey.replace("|", ":"), {}).get("last_price", 0)
            if val:
                return float(val)
        return None
    except Exception:
        return None


def get_live_price_yf(yf_ticker: str):
    """Fallback: yfinance fast_info — no API key needed, ~1-min freshness."""
    try:
        info = yf.Ticker(yf_ticker).fast_info
        price = info.get("lastPrice") or info.get("last_price")
        return float(price) if price and float(price) > 0 else None
    except Exception:
        return None


def fetch_15min_candles(symbol: str, yf_ticker: str, ikey: str) -> pd.DataFrame:
    try:
        df = yf.download(yf_ticker, period="5d", interval="15m",
                         auto_adjust=True, progress=False)
        if df is None or df.empty:
            print(f"  {symbol}: yfinance returned no data")
            return pd.DataFrame()

        if isinstance(df.columns, pd.MultiIndex):
            df.columns = [col[0].lower() for col in df.columns]
        else:
            df.columns = [str(c).lower() for c in df.columns]

        df = df[["open", "high", "low", "close", "volume"]].copy()
        df.index = pd.to_datetime(df.index)
        df = df.between_time("03:45", "10:00")
        df.dropna(inplace=True)
        df.reset_index(inplace=True)
        df.rename(columns={"index": "time", "datetime": "time", "date": "time"},
                  errors="ignore", inplace=True)
        if "time" not in df.columns:
            df.rename(columns={df.columns[0]: "time"}, inplace=True)

        if len(df) < 10:
            print(f"  {symbol}: only {len(df)} 15-min candles")
            return pd.DataFrame()

        # Priority: Upstox live (daily token) → yfinance fast_info → bar close
        live = get_live_price_upstox(symbol, ikey)
        src  = "Upstox"
        if not live:
            live = get_live_price_yf(yf_ticker)
            src  = "yfinance"
        if live:
            df.at[df.index[-1], "close"] = live
            print(f"  {symbol}: {len(df)} candles | Live ₹{live:.2f} ({src})")
        else:
            print(f"  {symbol}: {len(df)} candles | ₹{float(df['close'].iloc[-1]):.2f} (bar close)")
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

    # Direction comes from the last fully CLOSED candle only. The most recent
    # row is still forming and its close is overwritten with a live tick every
    # scan (see fetch_15min_candles) — basing the flip check on that row meant
    # the Supertrend direction flapped with every price wiggle, re-firing the
    # same BUY every ~30min all morning with no genuine reversal. The live
    # price is still used for the entry value below.
    live_price = float(df.iloc[-1]["close"])
    curr = df.iloc[-2]
    prev = df.iloc[-3]

    st_now     = int(curr["st_direction"])
    st_prev    = int(prev["st_direction"])
    st_flipped = st_now != st_prev
    direction  = None

    if st_flipped and st_now == 1:
        direction = "BUY"
    elif st_flipped and st_now == -1:
        direction = "SELL"

    if not direction:
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
    for symbol, keys in INSTRUMENTS.items():
        ikey      = keys["upstox"]
        yf_ticker = keys["yf"]
        print(f"  {symbol:<12}", end=" ")

        last = _last_signal.get(symbol, {})
        if last and time.time() - last.get("timestamp", 0) < COOLDOWN:
            remaining = int((COOLDOWN - (time.time() - last["timestamp"])) / 60)
            print(f"cooldown ({remaining}m remaining)")
            continue

        df = fetch_15min_candles(symbol, yf_ticker, ikey)
        if df.empty:
            continue

        result = check_signal(symbol, df)
        if result:
            direction, price, sl, tp = result
            print(f"→ {direction} | Entry ₹{price} | SL ₹{sl} | TP ₹{tp}")
            send_telegram(format_signal(symbol, direction, price, sl, tp))
            record_signal(symbol, direction, price, sl, tp)
            _last_signal[symbol] = {"direction": direction, "timestamp": time.time()}
            _save_state()
        else:
            print("no signal")

def main():
    _load_state()
    print("=" * 55)
    print("  Nifty/BankNifty Intraday Scalper")
    print(f"  Supertrend({ST_PERIOD},{ST_MULTIPLIER}) | 15-min | MIS")
    print("=" * 55)
    send_telegram(
        "⚡ <b>Nifty Scalper Started</b>\n"
        f"📅 {datetime.now().strftime('%d %b %Y %I:%M %p IST')}\n"
        f"📊 Supertrend({ST_PERIOD},{ST_MULTIPLIER}) | 15min\n"
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
