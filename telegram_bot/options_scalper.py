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
import json
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
from nse_holidays import is_nse_holiday
from telegram_config import validate_telegram_config

load_dotenv()
socket.setdefaulttimeout(30)

# Upstream direction source: nifty_scalper's state file
NIFTY_STATE_FILE = os.path.join(os.path.dirname(__file__), ".state_nifty_scalper.json")
UPSTREAM_VALIDITY_SEC = 1800  # 30 minutes: aligned with nifty_scalper COOLDOWN
FUTURE_TIMESTAMP_TOLERANCE_SEC = 5

# Deduplication tracking
PROCESSED_SIGNALS_FILE = os.path.join(os.path.dirname(__file__), ".processed_options_signals")
DEDUP_RETENTION_LIMIT = 500
_processed_signal_ids = set()

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


# ── Upstream direction consumption ────────────────────────────────────────────

def _load_processed():
    """Load deduplication state from persistent file."""
    global _processed_signal_ids
    try:
        with open(PROCESSED_SIGNALS_FILE) as f:
            _processed_signal_ids = set(line.strip() for line in f if line.strip())
    except FileNotFoundError:
        pass

def _mark_processed(signal_id):
    """Mark signal as processed and persist atomically."""
    global _processed_signal_ids
    _processed_signal_ids.add(signal_id)

    # Keep only recent signals (bounded retention)
    if len(_processed_signal_ids) > DEDUP_RETENTION_LIMIT:
        recent = sorted(list(_processed_signal_ids))[-DEDUP_RETENTION_LIMIT:]
        _processed_signal_ids = set(recent)

    # Atomic write: temp file + rename
    try:
        temp_file = PROCESSED_SIGNALS_FILE + ".tmp"
        with open(temp_file, "w") as f:
            for sig_id in sorted(_processed_signal_ids):
                f.write(sig_id + "\n")
        os.replace(temp_file, PROCESSED_SIGNALS_FILE)
    except Exception as e:
        log.warning(f"Failed to persist dedup state: {e}")

def _read_upstream_direction(symbol):
    """
    Read and validate NIFTY/BANKNIFTY direction from nifty_scalper state.

    Returns: (direction_int, timestamp) if valid, or (None, None) if invalid/stale/missing.
      direction_int: 1 for BUY, -1 for SELL
      timestamp: Unix timestamp of signal generation
    """
    try:
        # File existence check
        if not os.path.exists(NIFTY_STATE_FILE):
            log.debug(f"No upstream state file for {symbol}")
            return None, None

        # Parse JSON
        with open(NIFTY_STATE_FILE) as f:
            state = json.load(f)

        # Validate top-level: must be dict
        if not isinstance(state, dict):
            log.warning(f"Malformed upstream state: top-level is not dict")
            return None, None

        # Validate symbol entry exists
        if symbol not in state:
            log.debug(f"Upstream state has no entry for {symbol}")
            return None, None

        symbol_state = state[symbol]

        # Validate symbol entry: must be dict
        if not isinstance(symbol_state, dict):
            log.warning(f"Malformed upstream state for {symbol}: entry is not dict")
            return None, None

        # Validate required fields
        if "direction" not in symbol_state or "timestamp" not in symbol_state:
            log.warning(f"Malformed upstream state for {symbol}: missing direction or timestamp")
            return None, None

        direction_str = symbol_state["direction"]
        timestamp = symbol_state["timestamp"]

        # Validate direction: must be exactly "BUY" or "SELL"
        if direction_str not in ("BUY", "SELL"):
            log.warning(f"Invalid upstream direction for {symbol}: {direction_str}")
            return None, None

        # Validate timestamp: numeric, not bool, finite, positive
        if isinstance(timestamp, bool) or not isinstance(timestamp, (int, float)):
            log.warning(f"Invalid timestamp type for {symbol}: {type(timestamp)}")
            return None, None

        if not (timestamp > 0 and timestamp < float('inf')):
            log.warning(f"Invalid timestamp value for {symbol}: {timestamp}")
            return None, None

        # Validate freshness
        now = time.time()
        age = now - timestamp

        # Reject future timestamps (allow small clock skew)
        if age < -FUTURE_TIMESTAMP_TOLERANCE_SEC:
            log.warning(f"Upstream {symbol} timestamp is in future by {-age:.1f}s")
            return None, None

        # Reject stale timestamps
        if age > UPSTREAM_VALIDITY_SEC:
            log.debug(f"Upstream {symbol} direction is stale ({age:.0f}s old, max {UPSTREAM_VALIDITY_SEC}s)")
            return None, None

        # Map direction string to integer
        direction_int = 1 if direction_str == "BUY" else -1

        return direction_int, timestamp

    except json.JSONDecodeError:
        log.warning(f"Malformed upstream JSON for {symbol}")
        return None, None
    except (IOError, KeyError, TypeError) as e:
        log.debug(f"Error reading upstream state for {symbol}: {e}")
        return None, None


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
    """
    Consume upstream NIFTY/BANKNIFTY direction from nifty_scalper.
    Perform options-specific analysis only. No independent directional logic.
    """
    ticker = cfg["yf"]; step = cfg["strike_step"]

    # ── UPSTREAM DIRECTION VALIDATION (MANDATORY) ─────────────────────────────
    # Do not generate independent direction. Consume only.
    upstream_dir, upstream_ts = _read_upstream_direction(name)
    if upstream_dir is None:
        log.debug(f"SKIP {name} — no valid upstream direction from nifty_scalper")
        return  # Fail closed: no signal without upstream

    # Create deduplication key: symbol + direction + timestamp
    upstream_direction_str = "BUY" if upstream_dir == 1 else "SELL"
    dedup_key = f"{name}:{upstream_direction_str}:{upstream_ts}"

    # Check if already processed
    if dedup_key in _processed_signal_ids:
        log.debug(f"SKIP {name} — already processed {dedup_key}")
        return

    log.debug(f"Valid upstream {name}: dir={upstream_direction_str} age={(time.time()-upstream_ts):.1f}s")

    # ── FETCH MARKET DATA ──────────────────────────────────────────────────────
    df = fetch_15m(name, ticker)
    if df is None:
        return

    # ── OPTIONS-SPECIFIC ANALYSIS (NO INDEPENDENT DIRECTION DERIVATION) ────────
    high = df["high"].squeeze(); low = df["low"].squeeze(); close = df["close"].squeeze()
    adx = calc_adx(high, low, close, ADX_PERIOD)

    # ADX as quality filter only (not directional)
    adx_val = float(adx.iloc[-2])
    if adx_val < ADX_MIN:
        log.debug(f"SKIP {name} — ADX {adx_val:.1f} < {ADX_MIN} (low strength)")
        return  # Quality gate, not directional

    spot = float(df["close"].iloc[-1])

    # ── MAP UPSTREAM DIRECTION TO OPTIONS SIDE ──────────────────────────────────
    if upstream_dir == 1:  # BUY from upstream
        opt, side = "CE", "🟢 BUY CALL"
    else:  # SELL from upstream
        opt, side = "PE", "🔴 BUY PUT"

    # ── OPTIONS-SPECIFIC SELECTIONS ────────────────────────────────────────────
    strike = atm_strike(spot, step)
    expiry, exp_type = nearest_weekly_expiry(name)

    log.info("OPTIONS FOLLOW-UP %s: %s side, ATM strike %d, expiry %s, spot %.1f, ADX %.1f",
             name, side, strike, expiry, spot, adx_val)

    # ── SEND DOWNSTREAM TELEGRAM ALERT ─────────────────────────────────────────
    tg_send(
        f"[OPTIONS FOLLOW-UP] ━━━━━━━━━━━━━━━━━━━━━━\n⚡ <b>NIFTY SCALPER → OPTIONS {name}</b>\n━━━━━━━━━━━━━━━━━━━━━━\n\n"
        f"📊 <b>Direction Source:</b> Nifty Scalper\n"
        f"📈 <b>{name} Direction:</b> {upstream_direction_str}\n"
        f"⏱ <b>Signal Age:</b> {(time.time()-upstream_ts):.0f}s\n\n"
        f"🎯 <b>Options Action :</b> {side}\n"
        f"📅 <b>Time          :</b> {datetime.now(IST).strftime('%d %b %Y %I:%M %p IST')}\n\n"
        f"💰 <b>Strike        :</b> <code>{name} {strike} {opt}</code>\n"
        f"🗓 <b>Expiry        :</b> {expiry.strftime('%d %b %Y')} ({exp_type})\n"
        f"📍 <b>Spot Price    :</b> {spot:.1f}\n\n"
        f"🛑 <b>Stop Loss     :</b> exit if premium falls ~{SL_PREMIUM_PCT}%\n"
        f"🎯 <b>Target        :</b> book ~{TP_PREMIUM_PCT}% gain (1:2)\n\n"
        f"📊 <b>ADX(14)       :</b> {adx_val:.1f} (≥ {ADX_MIN} = sufficient strength)\n"
        f"🔗 <b>Coupling      :</b> Upstream NIFTY direction + options ATM selection\n\n"
        f"💡 This is an options follow-up, not an independent index direction.\n"
        f"🏦 <i>Confirm strike/expiry availability in broker before executing</i>\n"
        f"⚠️ <i>Options decay with time — square off by 3:20 PM IST</i>\n━━━━━━━━━━━━━━━━━━━━━━"
    )

    # Mark as processed ONLY after successful Telegram send
    _mark_processed(dedup_key)


# ── main ──────────────────────────────────────────────────────────────────────

def main():
    global TELEGRAM_TOKEN, CHAT_ID
    TELEGRAM_TOKEN, CHAT_ID = validate_telegram_config(TELEGRAM_TOKEN, CHAT_ID)
    _load_seen()
    _load_processed()
    log.info("Options Scalper started | Consumes NIFTY/BANKNIFTY from nifty_scalper | ADX>=%d as quality filter",
             ADX_MIN)
    tg_send(
        f"[OPTIONS FOLLOW-UP] ⚡ <b>Online</b>\n"
        f"📅 {datetime.now(IST).strftime('%d %b %Y %I:%M %p IST')}\n"
        f"📊 Downstream options consumer\n"
        f"🎯 Consumes NIFTY + BANKNIFTY direction from Nifty Scalper\n"
        f"💰 ATM weekly options selection (CE/PE based on upstream)\n"
        f"🛡 ADX(≥{ADX_MIN}) quality filter • Defined risk • Premium only\n"
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
