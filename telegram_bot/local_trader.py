"""
local_trader.py — Windows Auto-Trade Executor
Runs EMA(9/21) + RSI(14) signal detection locally and places trades directly
in MetaTrader5. Sends Telegram confirmation after every trade.

Install (Windows CMD):
    pip install MetaTrader5 yfinance pandas requests python-dotenv

Create a .env file in the same folder with:
    MT5_LOGIN=345600136
    MT5_PASSWORD=your_xm_password
    MT5_SERVER=XMGlobal-MT5 3
    VANTAGE_EA_TOKEN=8810867297:AAHZ9QAkQv1KujiaBbJp7CrPQhyHIZMN9oc
    SIGNAL_CHAT_ID=7093601171
    LOT_SIZE=0.01

Run:
    python local_trader.py
"""

import os
import time
import logging
from datetime import datetime

import pandas as pd
import yfinance as yf
import requests
import MetaTrader5 as mt5
from dotenv import load_dotenv

load_dotenv()

# ── Config ─────────────────────────────────────────────────────────────────────
BOT_TOKEN    = os.getenv("VANTAGE_EA_TOKEN", "8810867297:AAHZ9QAkQv1KujiaBbJp7CrPQhyHIZMN9oc")
CHAT_ID      = os.getenv("SIGNAL_CHAT_ID",   "7093601171")

MT5_LOGIN    = int(os.getenv("MT5_LOGIN",    "0"))
MT5_PASSWORD = os.getenv("MT5_PASSWORD",     "")
MT5_SERVER   = os.getenv("MT5_SERVER",       "")

LOT_SIZE     = float(os.getenv("LOT_SIZE",   "0.01"))

FAST_EMA     = 9
SLOW_EMA     = 21
RSI_PERIOD   = 14
RSI_BUY_MAX  = 65
RSI_SELL_MIN = 35
ATR_SL_MULT  = 1.0
ATR_TP_MULT  = 3.0
POLL_SECS    = 60
CACHE_TTL    = 840   # 14-min cache (same as GCP bots)

# Forex + Gold only — XM MT5 does not offer Indian stocks/Nifty
SYMBOLS = {
    "EURUSD": "EURUSD=X",
    "GBPUSD": "GBPUSD=X",
    "USDJPY": "USDJPY=X",
    "XAUUSD": "GC=F",
}

logging.basicConfig(
    format="%(asctime)s | LOCAL_TRADER | %(levelname)s | %(message)s",
    level=logging.INFO,
    handlers=[
        logging.FileHandler("local_trader.log", encoding="utf-8"),
        logging.StreamHandler()
    ]
)
log = logging.getLogger(__name__)

_seen_bars = {}   # {symbol: last_bar_ts}
_cache     = {}   # {cache_key: (ts, df)}


# ── Telegram ───────────────────────────────────────────────────────────────────

def tg_send(text):
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    try:
        r = requests.post(url, data={"chat_id": CHAT_ID, "text": text,
                                     "parse_mode": "HTML"}, timeout=10)
        if not r.json().get("ok"):
            log.warning("Telegram failed: %s", r.text[:100])
    except Exception as exc:
        log.warning("Telegram error: %s", exc)


# ── Indicators ─────────────────────────────────────────────────────────────────

def calc_rsi(close, period):
    delta = close.diff()
    ag = delta.clip(lower=0).ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    al = (-delta.clip(upper=0)).ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    return 100 - 100 / (1 + ag / al)

def calc_atr(high, low, close, period):
    pc = close.shift(1)
    tr = pd.concat([high-low, (high-pc).abs(), (low-pc).abs()], axis=1).max(axis=1)
    return tr.ewm(span=period, adjust=False).mean()


# ── Data fetch ─────────────────────────────────────────────────────────────────

def fetch_data(name):
    ticker    = SYMBOLS[name]
    cache_key = f"{ticker}_1h"
    now       = time.time()
    cached    = _cache.get(cache_key)
    if cached and now - cached[0] < CACHE_TTL:
        return cached[1]
    for attempt in range(3):
        try:
            df = yf.download(ticker, period="30d", interval="1h",
                             progress=False, auto_adjust=True)
            if df is not None and len(df) >= SLOW_EMA + 10:
                if isinstance(df.columns, pd.MultiIndex):
                    df.columns = [col[0] for col in df.columns]
                _cache[cache_key] = (now, df)
                return df
        except Exception as exc:
            log.warning("yfinance attempt %d for %s: %s", attempt+1, name, exc)
        if attempt < 2:
            time.sleep(5 * (2 ** attempt))
    return None


# ── Signal detection ───────────────────────────────────────────────────────────

def check_signal(name):
    df = fetch_data(name)
    if df is None:
        return None

    close = df["Close"].squeeze()
    high  = df["High"].squeeze()
    low   = df["Low"].squeeze()
    if isinstance(close, pd.DataFrame): close = close.iloc[:, 0]
    if isinstance(high,  pd.DataFrame): high  = high.iloc[:,  0]
    if isinstance(low,   pd.DataFrame): low   = low.iloc[:,   0]
    close = close.dropna()

    fast_ema = close.ewm(span=FAST_EMA, adjust=False).mean()
    slow_ema = close.ewm(span=SLOW_EMA, adjust=False).mean()
    rsi = calc_rsi(close, RSI_PERIOD)
    atr = calc_atr(high, low, close, RSI_PERIOD)

    i      = -2
    bar_ts = str(df.index[i])
    if bar_ts == _seen_bars.get(name):
        return None   # already processed this bar

    bull = (fast_ema.iloc[i] > slow_ema.iloc[i]) and (fast_ema.iloc[i-1] <= slow_ema.iloc[i-1])
    bear = (fast_ema.iloc[i] < slow_ema.iloc[i]) and (fast_ema.iloc[i-1] >= slow_ema.iloc[i-1])

    rsi_val = float(rsi.iloc[i])
    price   = float(close.iloc[i])
    atr_min = {"EURUSD": 0.00150, "GBPUSD": 0.00180, "USDJPY": 0.20, "XAUUSD": 3.0}
    atr_val = max(float(atr.iloc[i]), atr_min.get(name, 0))
    dec     = 3 if "JPY" in name else 5

    log.info("Bar %s | %s | price=%.{d}f | rsi=%.1f | bull=%s | bear=%s".format(d=dec),
             bar_ts, name, price, rsi_val, bull, bear)

    _seen_bars[name] = bar_ts

    if bull and rsi_val < RSI_BUY_MAX:
        entry = round(price, dec)
        sl    = round(entry - ATR_SL_MULT * atr_val, dec)
        tp    = round(entry + ATR_TP_MULT * atr_val, dec)
        return "BUY", entry, sl, tp, rsi_val, atr_val

    if bear and rsi_val > RSI_SELL_MIN:
        entry = round(price, dec)
        sl    = round(entry + ATR_SL_MULT * atr_val, dec)
        tp    = round(entry - ATR_TP_MULT * atr_val, dec)
        return "SELL", entry, sl, tp, rsi_val, atr_val

    return None


# ── MT5 trade placement ────────────────────────────────────────────────────────

def place_trade(name, direction, sl, tp):
    info = mt5.symbol_info(name)
    if info is None:
        log.error("Symbol %s not found in MT5 — check your broker's symbol name", name)
        return False
    if not info.visible:
        mt5.symbol_select(name, True)
        time.sleep(0.2)

    tick = mt5.symbol_info_tick(name)
    if tick is None:
        log.error("No tick data for %s — market may be closed", name)
        return False

    order_type = mt5.ORDER_TYPE_BUY  if direction == "BUY"  else mt5.ORDER_TYPE_SELL
    price      = tick.ask             if direction == "BUY"  else tick.bid

    req = {
        "action":        mt5.TRADE_ACTION_DEAL,
        "symbol":        name,
        "volume":        LOT_SIZE,
        "type":          order_type,
        "price":         price,
        "sl":            sl,
        "tp":            tp,
        "deviation":     30,
        "magic":         20260630,
        "comment":       "GCP-Bot",
        "type_time":     mt5.ORDER_TIME_GTC,
        "type_filling":  mt5.ORDER_FILLING_IOC,
    }

    result = mt5.order_send(req)
    if result is None:
        log.error("order_send returned None for %s — MT5 connection lost?", name)
        return False

    if result.retcode == mt5.TRADE_RETCODE_DONE:
        log.info("✅ TRADE PLACED | %s %s | ticket=%d | price=%.5f | SL=%.5f | TP=%.5f",
                 direction, name, result.order, price, sl, tp)
        return True, result.order, price
    else:
        log.error("❌ Trade failed | %s %s | retcode=%d | %s",
                  direction, name, result.retcode, result.comment)
        return False, 0, 0


# ── Main loop ──────────────────────────────────────────────────────────────────

def main():
    if not MT5_LOGIN or not MT5_PASSWORD or not MT5_SERVER:
        raise SystemExit("Set MT5_LOGIN, MT5_PASSWORD, MT5_SERVER in .env file")

    log.info("Connecting to MT5 | login=%d | server=%s", MT5_LOGIN, MT5_SERVER)
    if not mt5.initialize(login=MT5_LOGIN, password=MT5_PASSWORD, server=MT5_SERVER):
        raise SystemExit(f"MT5 init failed: {mt5.last_error()}")

    acc = mt5.account_info()
    log.info("Connected | Account: %s | Balance: %.2f %s | Leverage: 1:%d",
             acc.name, acc.balance, acc.currency, acc.leverage)

    tg_send(
        f"🤖 <b>Auto Trader Online</b>\n"
        f"📅 {datetime.now().strftime('%d %b %Y %I:%M %p')}\n"
        f"💰 Balance: {acc.balance:,.2f} {acc.currency}\n"
        f"📊 EMA({FAST_EMA}/{SLOW_EMA}) + RSI({RSI_PERIOD}) | 1H\n"
        f"💱 Watching: {' • '.join(SYMBOLS.keys())}\n"
        f"📦 Lot size: {LOT_SIZE} (per trade)\n"
        f"⚠️ <i>Auto-trading LIVE — trades will be placed automatically</i>"
    )

    while True:
        for name in SYMBOLS:
            try:
                result = check_signal(name)
                if result:
                    direction, entry, sl, tp, rsi_val, atr_val = result
                    log.info("SIGNAL | %s %s | entry=%.5f | sl=%.5f | tp=%.5f | rsi=%.1f",
                             direction, name, entry, sl, tp, rsi_val)
                    ok, ticket, actual_price = place_trade(name, direction, sl, tp)
                    if ok:
                        dec = 3 if "JPY" in name else 5
                        pfx = "$" if name == "XAUUSD" else ""
                        em  = "🟢 BUY" if direction == "BUY" else "🔴 SELL"
                        rr  = round(ATR_TP_MULT / ATR_SL_MULT, 1)
                        tg_send(
                            f"━━━━━━━━━━━━━━━━━━━━━━\n"
                            f"✅ <b>AUTO TRADE PLACED — {name}</b>\n"
                            f"━━━━━━━━━━━━━━━━━━━━━━\n\n"
                            f"📈 <b>Direction :</b> {em}\n"
                            f"📅 <b>Time      :</b> {datetime.now().strftime('%d %b %Y %I:%M %p')}\n\n"
                            f"📍 <b>Entry     :</b> {pfx}<code>{actual_price:.{dec}f}</code>\n"
                            f"🛑 <b>Stop Loss :</b> {pfx}<code>{sl:.{dec}f}</code>\n"
                            f"🎯 <b>Target    :</b> {pfx}<code>{tp:.{dec}f}</code>\n\n"
                            f"📊 <b>RSI(14)   :</b> {rsi_val:.1f}\n"
                            f"⚖️ <b>Risk/Reward:</b> 1 : {rr}\n"
                            f"📦 <b>Lot size  :</b> {LOT_SIZE}\n"
                            f"🎫 <b>Ticket    :</b> #{ticket}\n"
                            f"━━━━━━━━━━━━━━━━━━━━━━"
                        )
            except Exception as exc:
                log.error("Error scanning %s: %s", name, exc)
            time.sleep(2)

        time.sleep(POLL_SECS)


if __name__ == "__main__":
    main()
