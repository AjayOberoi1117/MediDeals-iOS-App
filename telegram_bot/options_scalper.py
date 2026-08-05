"""
Options Scalper — Nifty & BankNifty directional option-BUYING signals.

Strategy : Supertrend(7,2.0) flip on 15-min bars, gated by a higher-timeframe
           trend filter (1H EMA50) + ADX(14) strength filter. Only strong,
           trend-aligned flips fire — this is the quality gate that separates
           it from the raw (near coin-flip) Supertrend scalper.

Mapping  : Confirmed bullish flip  -> BUY ATM Call  (CE)
           Confirmed bearish flip  -> BUY ATM Put   (PE)

Contract : At-the-money strike (NIFTY 50-pt, BANKNIFTY 100-pt), nearest weekly
           expiry. Strike is computed from spot; ALWAYS confirm the exact
           nearest available strike/expiry in your broker before buying.

Risk     : Option BUYING = max loss capped at premium paid. Manage on premium:
           exit ~30% down, book ~60% up (1:2). Underlying invalidation = index
           closing back beyond the Supertrend level.

Session  : 9:15 AM – 3:10 PM IST (stop new entries early; square off by 3:20).
Signals  : Telegram only — trade manually. Weekend + NSE-holiday aware.
"""

import os
import time
import socket
import logging
import calendar
from datetime import datetime, timedelta

import requests
import pandas as pd
import yfinance as yf
import pytz
from dotenv import load_dotenv

try:
    from .telegram_config import validate_telegram_config
except ImportError:
    from telegram_config import validate_telegram_config
from nse_holidays import is_nse_holiday

load_dotenv()
socket.setdefaulttimeout(30)

TELEGRAM_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
CHAT_ID        = os.getenv("TELEGRAM_CHAT_ID", "")

IST = pytz.timezone("Asia/Kolkata")

INSTRUMENTS = {
    "NIFTY":     {"yf": "^NSEI",     "strike_step": 50},
    "BANKNIFTY": {"yf": "^NSEBANK",  "strike_step": 100},
}

ST_PERIOD      = 7
ST_MULTIPLIER  = 2.0
ADX_PERIOD     = 14
ADX_MIN        = 20        # trend-strength gate — below this, market is choppy
TREND_EMA      = 50        # 1H trend filter
SL_PREMIUM_PCT = 30        # exit if option premium falls ~30% from entry
TP_PREMIUM_PCT = 60        # book ~60% gain (1:2 on premium)
MARKET_OPEN    = (9, 15)
MARKET_CLOSE   = (15, 10)  # stop new entries by 3:10, square off by 3:20
SCAN_INTERVAL  = 60
COOLDOWN       = 1800      # 30 min per symbol
CACHE_TTL      = 240

logging.basicConfig(format="%(asctime)s | OPTIONS  | %(levelname)s | %(message)s", level=logging.INFO)
log = logging.getLogger(__name__)

_last_signal = {}
_seen_bars   = {}
_cache       = {}

SEEN_FILE = os.path.join(os.path.dirname(__file__), ".seen_options")


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
        r = requests.post(url, data={"chat_id": CHAT_ID, "text": text, "parse_mode": "HTML"}, timeout=10)
        if not r.json().get("ok"):
            log.warning("Telegram failed: %s", r.text[:120])
    except Exception as exc:
        log.warning("Telegram error: %s", exc)


# ── market hours ─────────────────────────────────────────────────────────────

def in_market_hours():
    now = datetime.now(IST)
    if now.weekday() >= 5:
        return False
    if is_nse_holiday(now):
        return False
    return MARKET_OPEN <= (now.hour, now.minute) <= MARKET_CLOSE


# ── indicators ────────────────────────────────────────────────────────────────

def calc_atr(high, low, close, period):
    pc = close.shift(1)
    tr = pd.concat([high-low, (high-pc).abs(), (low-pc).abs()], axis=1).max(axis=1)
    return tr.ewm(span=period, adjust=False).mean()

def calc_adx(high, low, close, period):
    up_move = high.diff()
    down_move = -low.diff()
    plus_dm = up_move.where((up_move > down_move) & (up_move > 0), 0.0)
    minus_dm = down_move.where((down_move > up_move) & (down_move > 0), 0.0)
    pc = close.shift(1)
    tr = pd.concat([high-low, (high-pc).abs(), (low-pc).abs()], axis=1).max(axis=1)
    atr = tr.ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    plus_di = 100 * (plus_dm.ewm(alpha=1/period, min_periods=period, adjust=False).mean() / atr)
    minus_di = 100 * (minus_dm.ewm(alpha=1/period, min_periods=period, adjust=False).mean() / atr)
    dx = 100 * (plus_di - minus_di).abs() / (plus_di + minus_di)
    return dx.ewm(alpha=1/period, min_periods=period, adjust=False).mean()

def calculate_supertrend(df, period, multiplier):
    hl2 = (df["high"] + df["low"]) / 2
    prev_close = df["close"].shift(1)
    tr = pd.concat([df["high"]-df["low"], (df["high"]-prev_close).abs(),
                    (df["low"]-prev_close).abs()], axis=1).max(axis=1)
    atr = tr.ewm(span=period, adjust=False).mean()
    upper_band = hl2 + multiplier * atr
    lower_band = hl2 - multiplier * atr
    supertrend = pd.Series(index=df.index, dtype=float)
    direction  = pd.Series(index=df.index, dtype=int)
    for i in range(1, len(df)):
        if not (upper_band.iloc[i] < upper_band.iloc[i-1] or df["close"].iloc[i-1] > upper_band.iloc[i-1]):
            upper_band.iloc[i] = upper_band.iloc[i-1]
        if not (lower_band.iloc[i] > lower_band.iloc[i-1] or df["close"].iloc[i-1] < lower_band.iloc[i-1]):
            lower_band.iloc[i] = lower_band.iloc[i-1]
        if i == 1:
            direction.iloc[i] = 1
        elif supertrend.iloc[i-1] == upper_band.iloc[i-1]:
            direction.iloc[i] = -1 if df["close"].iloc[i] > upper_band.iloc[i] else 1
        else:
            direction.iloc[i] = 1 if df["close"].iloc[i] < lower_band.iloc[i] else -1
        supertrend.iloc[i] = lower_band.iloc[i] if direction.iloc[i] == 1 else upper_band.iloc[i]
    df = df.copy()
    df["supertrend"] = supertrend
    df["st_direction"] = direction
    return df


# ── data ──────────────────────────────────────────────────────────────────────

def _yf(ticker, period, interval):
    for attempt in range(3):
        try:
            df = yf.download(ticker, period=period, interval=interval, progress=False, auto_adjust=True)
            if df is not None and not df.empty:
                if isinstance(df.columns, pd.MultiIndex):
                    df.columns = [c[0] for c in df.columns]
                df.columns = [str(c).lower() for c in df.columns]
                return df
        except Exception as exc:
            log.debug("yfinance attempt %d for %s: %s", attempt+1, ticker, exc)
        if attempt < 2:
            time.sleep(5 * (2 ** attempt))
    return None

def fetch_15m(name, ticker):
    key = f"{ticker}_15m"; now = time.time()
    c = _cache.get(key)
    if c and now - c[0] < CACHE_TTL:
        return c[1]
    df = _yf(ticker, "10d", "15m")
    if df is None or len(df) < ST_PERIOD + 10:
        return None
    df = df[["open", "high", "low", "close"]].dropna()
    _cache[key] = (now, df)
    return df

def get_1h_trend(ticker):
    key = f"{ticker}_1h_trend"; now = time.time()
    c = _cache.get(key)
    if c and now - c[0] < 3600:
        return c[1]
    df = _yf(ticker, "60d", "1h")
    if df is None or len(df) < TREND_EMA + 2:
        return 0
    close = df["close"].squeeze()
    if isinstance(close, pd.DataFrame):
        close = close.iloc[:, 0]
    ema = close.ewm(span=TREND_EMA, adjust=False).mean()
    trend = 1 if float(close.iloc[-1]) > float(ema.iloc[-1]) else -1
    _cache[key] = (now, trend)
    return trend


# ── options helpers ───────────────────────────────────────────────────────────

def atm_strike(spot, step):
    return int(round(spot / step) * step)

def nearest_weekly_expiry(name):
    """Best-effort nearest weekly (NIFTY) / monthly (BANKNIFTY) expiry.
    NSE has changed expiry rules repeatedly — ALWAYS confirm in your broker."""
    today = datetime.now(IST).date()
    if name == "BANKNIFTY":
        # BANKNIFTY weekly options were discontinued (Nov 2024) — monthly only.
        # Last Thursday of the current month; roll to next month if already past.
        exp = _last_thursday(today.year, today.month)
        if exp < today:
            ny, nm = (today.year + 1, 1) if today.month == 12 else (today.year, today.month + 1)
            exp = _last_thursday(ny, nm)
        return exp, "monthly"
    # NIFTY weekly — nearest Thursday (roll to next week if today is past Thu)
    days_ahead = (3 - today.weekday()) % 7   # Thursday == weekday 3
    exp = today + timedelta(days=days_ahead)
    return exp, "weekly"

def _last_thursday(year, month):
    last_day = calendar.monthrange(year, month)[1]
    d = datetime(year, month, last_day).date()
    while d.weekday() != 3:   # Thursday
        d -= timedelta(days=1)
    return d


# ── signal logic ──────────────────────────────────────────────────────────────

def check_symbol(name, cfg):
    ticker = cfg["yf"]; step = cfg["strike_step"]
    df = fetch_15m(name, ticker)
    if df is None:
        return
    now_ts = time.time()
    if now_ts - _last_signal.get(name, 0) < COOLDOWN:
        return

    high = df["high"].squeeze(); low = df["low"].squeeze(); close = df["close"].squeeze()
    adx = calc_adx(high, low, close, ADX_PERIOD)
    df = calculate_supertrend(df, ST_PERIOD, ST_MULTIPLIER)
    if len(df) < 4:
        return

    # signal on last CLOSED bar (-2), confirmed against (-3); spot ~ current price (-1)
    bar_ts = str(df.index[-2])
    if bar_ts in _seen_bars.get(name, set()):
        return
    st_now  = int(df["st_direction"].iloc[-2])
    st_prev = int(df["st_direction"].iloc[-3])
    _seen_bars.setdefault(name, set()).add(bar_ts); _save_seen(name, bar_ts)
    if st_now == st_prev:
        return   # no flip

    adx_val = float(adx.iloc[-2])
    trend   = get_1h_trend(ticker)
    spot    = float(df["close"].iloc[-1])
    st_level = float(df["supertrend"].iloc[-2])

    # ADX strength gate
    if adx_val < ADX_MIN:
        log.info("SKIP %s — ADX %.1f < %d (choppy)", name, adx_val, ADX_MIN); return

    if st_now == 1:                              # bullish flip -> Call
        if trend != 1:
            log.info("SKIP %s CALL — 1H trend not bullish", name); return
        opt, side = "CE", "🟢 BUY CALL"
    else:                                        # bearish flip -> Put
        if trend != -1:
            log.info("SKIP %s PUT — 1H trend not bearish", name); return
        opt, side = "PE", "🔴 BUY PUT"

    strike = atm_strike(spot, step)
    expiry, exp_type = nearest_weekly_expiry(name)
    log.info("%s %s %d%s exp=%s spot=%.1f adx=%.1f", name, opt, strike, opt, expiry, spot, adx_val)

    tg_send(
        f"━━━━━━━━━━━━━━━━━━━━━━\n⚡ <b>OPTIONS SCALPER — {name}</b>\n━━━━━━━━━━━━━━━━━━━━━━\n\n"
        f"📈 <b>Signal    :</b> {side}\n"
        f"📅 <b>Time      :</b> {datetime.now(IST).strftime('%d %b %Y %I:%M %p IST')}\n"
        f"⏱ <b>Timeframe :</b> 15 Minutes\n\n"
        f"🎯 <b>Buy       :</b> <code>{name} {strike} {opt}</code>\n"
        f"🗓 <b>Expiry    :</b> {expiry.strftime('%d %b %Y')} ({exp_type})\n"
        f"📍 <b>Spot      :</b> <code>{spot:.1f}</code>  (ATM strike {strike})\n\n"
        f"🛑 <b>Stop Loss :</b> exit if premium falls ~{SL_PREMIUM_PCT}%\n"
        f"🎯 <b>Target    :</b> book ~{TP_PREMIUM_PCT}% gain (1:2)\n"
        f"🧭 <b>Invalidate:</b> index closing back beyond ST ₹{st_level:.0f}\n\n"
        f"📊 <b>ADX(14)   :</b> {adx_val:.1f}   (≥ {ADX_MIN} = trend confirmed)\n"
        f"📊 <b>1H Trend  :</b> {'Bullish' if trend == 1 else 'Bearish'}\n\n"
        f"💡 Supertrend flip + 1H trend + ADX aligned\n"
        f"🏦 <i>Buy ATM {opt} — confirm nearest strike/expiry in broker</i>\n"
        f"⚠️ <i>Options decay with time — square off by 3:20 PM IST</i>\n━━━━━━━━━━━━━━━━━━━━━━"
    )
    _last_signal[name] = now_ts


# ── main ──────────────────────────────────────────────────────────────────────

def main():
    global TELEGRAM_TOKEN, CHAT_ID
    TELEGRAM_TOKEN, CHAT_ID = validate_telegram_config(TELEGRAM_TOKEN, CHAT_ID)
    _load_seen()
    log.info("Options Scalper started | %s | ST(%d,%.1f) + 1H trend + ADX>=%d",
             ", ".join(INSTRUMENTS), ST_PERIOD, ST_MULTIPLIER, ADX_MIN)
    tg_send(
        f"⚡ <b>Options Scalper Online</b>\n"
        f"📅 {datetime.now(IST).strftime('%d %b %Y %I:%M %p IST')}\n"
        f"📊 Supertrend({ST_PERIOD},{ST_MULTIPLIER}) + 1H trend + ADX(≥{ADX_MIN}) | 15min\n"
        f"🎯 NIFTY + BANKNIFTY  •  ATM weekly options\n"
        f"🟢 Bull flip → Buy Call   🔴 Bear flip → Buy Put\n"
        f"🛡 Defined risk (premium only) — buy options, don't sell\n"
        f"⏰ Active 9:15 AM – 3:10 PM IST (square off by 3:20)"
    )
    while True:
        try:
            if in_market_hours():
                for name, cfg in INSTRUMENTS.items():
                    try:
                        check_symbol(name, cfg)
                    except Exception as exc:
                        log.debug("Error on %s: %s", name, exc)
                    time.sleep(2)
            else:
                log.debug("Outside market hours — waiting")
        except Exception as exc:
            log.error("Main loop error: %s", exc)
        time.sleep(SCAN_INTERVAL)


if __name__ == "__main__":
    main()
