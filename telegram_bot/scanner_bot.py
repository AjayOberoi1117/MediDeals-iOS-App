"""
Upstox Stock Scanner Bot — Real-Time Signals
Strategy   : EMA(9/21) crossover + RSI(14) + Confidence scoring
Data       : Upstox API (real-time prices matching your Upstox account)
Universe   : NIFTY 100
Signals    : Telegram + Email
Position   : Tier-based sizing (HIGH ₹2L / MEDIUM ₹1.5L / LOW ₹1L)
"""

import os
import time
import json
import logging
from datetime import datetime
import pytz
import requests
import pandas as pd
from dotenv import load_dotenv

load_dotenv()
logging.basicConfig(format="%(asctime)s | SCANNER  | %(levelname)s | %(message)s", level=logging.INFO)
log = logging.getLogger(__name__)

IST = pytz.timezone("Asia/Kolkata")

UPSTOX_TOKEN = os.getenv("UPSTOX_TOKEN", "")
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "7093601171")
EMAIL_FROM = os.getenv("EMAIL_FROM", "")
EMAIL_APP_PASSWORD = os.getenv("EMAIL_APP_PASSWORD", "")
EMAIL_TO = os.getenv("EMAIL_TO", "")

UPSTOX_BASE_URL = "https://api.upstox.com/v2"
EMA_FAST, EMA_SLOW = 9, 21
RSI_PERIOD, RSI_BUY_MAX = 14, 75
SL_PCT, TP_PCT = 0.5, 1.0
SCAN_INTERVAL_MIN = 5
MAX_SIGNALS_PER_DAY = 20
MARKET_OPEN, MARKET_CLOSE = (9, 15), (15, 30)

NIFTY100 = {
    # NIFTY 50
    "RELIANCE":     "NSE_EQ|INE002A01018",
    "TCS":          "NSE_EQ|INE467B01029",
    "HDFCBANK":     "NSE_EQ|INE040A01034",
    "ICICIBANK":    "NSE_EQ|INE090A01021",
    "BHARTIARTL":   "NSE_EQ|INE397D01024",
    "INFY":         "NSE_EQ|INE009A01021",
    "SBIN":         "NSE_EQ|INE062A01020",
    "HINDUNILVR":   "NSE_EQ|INE030A01027",
    "ITC":          "NSE_EQ|INE154A01025",
    "LT":           "NSE_EQ|INE018A01030",
    "KOTAKBANK":    "NSE_EQ|INE237A01036",
    "AXISBANK":     "NSE_EQ|INE238A01034",
    "BAJFINANCE":   "NSE_EQ|INE296A01032",
    "WIPRO":        "NSE_EQ|INE075A01022",
    "HCLTECH":      "NSE_EQ|INE860A01027",
    "ASIANPAINT":   "NSE_EQ|INE021A01026",
    "MARUTI":       "NSE_EQ|INE585B01010",
    "SUNPHARMA":    "NSE_EQ|INE044A01036",
    "TITAN":        "NSE_EQ|INE280A01028",
    "ULTRACEMCO":   "NSE_EQ|INE481G01011",
    "ONGC":         "NSE_EQ|INE213A01029",
    "NTPC":         "NSE_EQ|INE733E01010",
    "POWERGRID":    "NSE_EQ|INE752E01010",
    "NESTLEIND":    "NSE_EQ|INE239A01024",
    "JSWSTEEL":     "NSE_EQ|INE019A01038",
    "TATASTEEL":    "NSE_EQ|INE081A01020",
    "ADANIENT":     "NSE_EQ|INE423A01024",
    "ADANIPORTS":   "NSE_EQ|INE742F01042",
    "COALINDIA":    "NSE_EQ|INE522F01014",
    "BAJAJFINSV":   "NSE_EQ|INE918I01026",
    "BAJAJ-AUTO":   "NSE_EQ|INE917I01010",
    "BPCL":         "NSE_EQ|INE356A01018",
    "CIPLA":        "NSE_EQ|INE059A01026",
    "DRREDDY":      "NSE_EQ|INE089A01023",
    "GRASIM":       "NSE_EQ|INE047A01021",
    "HEROMOTOCO":   "NSE_EQ|INE158A01026",
    "HINDALCO":     "NSE_EQ|INE038A01020",
    "INDUSINDBK":   "NSE_EQ|INE095A01012",
    "LTIM":         "NSE_EQ|INE214A01039",
    "M&M":          "NSE_EQ|INE101A01026",
    "SHRIRAMFIN":   "NSE_EQ|INE591G01023",
    "TATACONSUM":   "NSE_EQ|INE192A01025",
    "TECHM":        "NSE_EQ|INE669C01025",
    "TRENT":        "NSE_EQ|INE849A01024",

    # NIFTY MIDCAP
    "APOLLOHOSP":   "NSE_EQ|INE437B01029",
    "BANKBARODA":   "NSE_EQ|INE028A01039",
    "BERGEPAINT":   "NSE_EQ|INE371C01023",
    "BIOCON":       "NSE_EQ|INE376G01045",
    "BOSCHLTD":     "NSE_EQ|INE323A01026",
    "CANBK":        "NSE_EQ|INE105A01019",
    "CHOLAFIN":     "NSE_EQ|INE144A01021",
    "COLPAL":       "NSE_EQ|INE259A01022",
    "DABUR":        "NSE_EQ|INE093A01010",
    "DLF":          "NSE_EQ|INE488A01046",
    "GAIL":         "NSE_EQ|INE129A01019",
    "GODREJCP":     "NSE_EQ|INE102A01016",
    "HAVELLS":      "NSE_EQ|INE465K01012",
    "ICICIGI":      "NSE_EQ|INE092A01019",
    "IDFCFIRSTB":   "NSE_EQ|INE633E01016",
    "IGL":          "NSE_EQ|INE203A01026",
    "INDUSTOWER":   "NSE_EQ|INE121J01017",
    "IOC":          "NSE_EQ|INE242A01010",
    "IRCTC":        "NSE_EQ|INE024L01017",
    "JINDALSTEL":   "NSE_EQ|INE139A01024",
    "JUBLFOOD":     "NSE_EQ|INE797H01027",
    "LICI":         "NSE_EQ|INE018E01046",
    "LUPIN":        "NSE_EQ|INE242E01010",
    "MARICO":       "NSE_EQ|INE196A01026",
    "MOTHERSON":    "NSE_EQ|INE775A01035",
    "MUTHOOTFIN":   "NSE_EQ|INE347E01026",
    "NAUKRI":       "NSE_EQ|INE663E01024",
    "NMDC":         "NSE_EQ|INE139E01025",
    "OFSS":         "NSE_EQ|INE992H01019",
    "PAGEIND":      "NSE_EQ|INE571E01038",
    "PIDILITIND":   "NSE_EQ|INE318A01026",
    "PNB":          "NSE_EQ|INE160A01022",
    "RECLTD":       "NSE_EQ|INE002E01046",
    "SAIL":         "NSE_EQ|INE114A01011",
    "SHREECEM":     "NSE_EQ|INE019A01038",
    "SIEMENS":      "NSE_EQ|INE003A01024",
    "SRF":          "NSE_EQ|INE647H01010",
    "TATAPOWER":    "NSE_EQ|INE245A01021",
    "TORNTPHARM":   "NSE_EQ|INE339A01026",
    "VEDL":         "NSE_EQ|INE205A01025",
    "VOLTAS":       "NSE_EQ|INE304C01020",
    "ZOMATO":       "NSE_EQ|INE758T01015",
}

STATE_FILE = os.path.join(os.path.dirname(__file__), ".state_scanner.json")

def load_state():
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE) as f:
            return json.load(f)
    return {"symbols_alerted": [], "signals_sent": 0}

def save_state(state):
    with open(STATE_FILE, "w") as f:
        json.dump(state, f)

def fetch_candles(symbol, ikey):
    """Fetch 50 15-min candles from Upstox."""
    try:
        url = f"{UPSTOX_BASE_URL}/historical-candle/intraday/{ikey}/15minute"
        headers = {"Authorization": f"Bearer {UPSTOX_TOKEN}"}
        params = {"limit": 50}
        r = requests.get(url, headers=headers, params=params, timeout=10)
        if r.status_code != 200:
            log.warning("Upstox fetch failed for %s: HTTP %d — %s", symbol, r.status_code, r.text[:200])
            return None
        data = r.json()
        if not data.get("data", {}).get("candles"):
            log.warning("No candles for %s: %s", symbol, data)
            return None
        candles = data["data"]["candles"]
        df = pd.DataFrame(candles, columns=["timestamp", "open", "high", "low", "close", "volume", "oi"])
        df["timestamp"] = pd.to_datetime(df["timestamp"])
        df = df[["timestamp", "open", "high", "low", "close", "volume"]].astype({
            "open": float, "high": float, "low": float, "close": float, "volume": int
        })
        return df.iloc[::-1].reset_index(drop=True)
    except Exception as exc:
        log.warning("Fetch error %s: %s", symbol, exc)
        return None

def calc_ema(s, span):
    return s.ewm(span=span, adjust=False).mean()

def calc_rsi(s, period):
    delta = s.diff()
    gain = delta.clip(lower=0).ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    loss = (-delta.clip(upper=0)).ewm(alpha=1/period, min_periods=period, adjust=False).mean()
    return 100 - 100 / (1 + gain / loss)

def check_signal(symbol, df):
    """Detect EMA bullish cross with confidence scoring."""
    if len(df) < EMA_SLOW + 5:
        return None

    close = df["close"]
    ema_fast = calc_ema(close, EMA_FAST)
    ema_slow = calc_ema(close, EMA_SLOW)
    rsi = calc_rsi(close, RSI_PERIOD)

    # Check for bullish cross: fast crosses above slow on bar[-2]
    if not ((ema_fast.iloc[-2] > ema_slow.iloc[-2]) and (ema_fast.iloc[-3] <= ema_slow.iloc[-3])):
        return None

    # RSI overbought check
    rsi_val = float(rsi.iloc[-1])
    if rsi_val > RSI_BUY_MAX:
        return None

    price = float(close.iloc[-1])
    sl = round(price * (1 - SL_PCT/100), 2)
    tp = round(price * (1 + TP_PCT/100), 2)

    # Confidence scoring
    score = 50
    if ema_fast.iloc[-1] > ema_fast.iloc[-2]:
        score += 10
    if rsi_val < 30:
        score += 15
    elif rsi_val < 50:
        score += 10
    if price > ema_slow.iloc[-1]:
        score += 10

    # Tier assignment
    if score >= 80:
        tier, qty_amt = "HIGH", 200000
    elif score >= 60:
        tier, qty_amt = "MEDIUM", 150000
    else:
        tier, qty_amt = "LOW", 100000

    risk = abs(sl - price)
    reward = abs(tp - price)

    return ("BUY", price, sl, tp, qty_amt, score, tier, rsi_val, ema_fast.iloc[-1], ema_slow.iloc[-1])

def notify(msg):
    """Send via Telegram + Email."""
    if TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID:
        try:
            url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
            requests.post(url, data={"chat_id": TELEGRAM_CHAT_ID, "text": msg, "parse_mode": "HTML"}, timeout=10)
        except Exception as exc:
            log.warning("Telegram error: %s", exc)

    if EMAIL_FROM and EMAIL_TO and EMAIL_APP_PASSWORD:
        try:
            import smtplib
            from email.mime.text import MIMEText
            msg_obj = MIMEText(msg, "html")
            msg_obj["Subject"] = "[NSE Signal] New Trading Opportunity"
            msg_obj["From"] = EMAIL_FROM
            msg_obj["To"] = EMAIL_TO
            with smtplib.SMTP("smtp.gmail.com", 587) as s:
                s.starttls()
                s.login(EMAIL_FROM, EMAIL_APP_PASSWORD)
                s.sendmail(EMAIL_FROM, [EMAIL_TO], msg_obj.as_string())
        except Exception as exc:
            log.warning("Email error: %s", exc)

def format_signal(symbol, direction, price, sl, tp, qty_amt, score, tier, rsi_val, ema_fast, ema_slow):
    rr = round(abs(tp - price) / max(abs(sl - price), 0.01), 1)
    return (f"━━━━━━━━━━━━━━━━━━━━━━\n"
            f"🔍 <b>STOCK SCANNER — {symbol}</b>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━\n\n"
            f"📈 <b>Signal    :</b> 🟢 BUY\n"
            f"📅 <b>Time      :</b> {datetime.now(IST).strftime('%d %b %Y %I:%M %p IST')}\n"
            f"⏱ <b>Timeframe :</b> 15 Minutes\n\n"
            f"📍 <b>Entry     :</b> ₹<code>{price:.2f}</code>\n"
            f"🛑 <b>Stop Loss :</b> ₹<code>{sl:.2f}</code>\n"
            f"🎯 <b>Target    :</b> ₹<code>{tp:.2f}</code>\n\n"
            f"📊 <b>Confidence:</b> {score}/100 ({tier})\n"
            f"💰 <b>Position  :</b> ₹{qty_amt/100000:.1f}L\n"
            f"📈 <b>RSI(14)   :</b> {rsi_val:.1f}\n"
            f"⚖️ <b>Risk/Reward:</b> 1 : {rr}\n\n"
            f"💡 EMA(9/21) bullish crossover confirmed\n"
            f"🏦 <i>Place as MIS (Intraday) in Upstox</i>\n"
            f"⚠️ <i>Set SL first! Square off before 3:15 PM IST</i>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━")

def in_market_hours():
    now = datetime.now(IST)
    if now.weekday() >= 5:
        return False
    return MARKET_OPEN <= (now.hour, now.minute) <= MARKET_CLOSE

def run_scan():
    state = load_state()
    new_signals = 0

    log.info("Scanning %d stocks...", len(NIFTY100))

    for symbol, ikey in NIFTY100.items():
        if state["signals_sent"] + new_signals >= MAX_SIGNALS_PER_DAY:
            break

        if symbol in state["symbols_alerted"]:
            continue

        print(f"  {symbol:<14}", end=" ")
        df = fetch_candles(symbol, ikey)

        if df is None:
            print("skip")
            continue

        result = check_signal(symbol, df)

        if result:
            direction, price, sl, tp, qty_amt, score, tier, rsi_val, ema_fast, ema_slow = result
            msg = format_signal(symbol, direction, price, sl, tp, qty_amt, score, tier, rsi_val, ema_fast, ema_slow)
            print(f"→ BUY | {tier} ({score}/100) | ₹{price} | SL ₹{sl} | TP ₹{tp}")
            notify(msg)
            state["symbols_alerted"].append(symbol)
            new_signals += 1
        else:
            print("no signal")

        time.sleep(0.3)

    state["signals_sent"] += new_signals
    save_state(state)
    log.info("Done. %d new signal(s). Total today: %d/%d", new_signals, state["signals_sent"], MAX_SIGNALS_PER_DAY)

def main():
    log.info("NSE Swing Scanner — NIFTY 100")
    log.info("EMA(9/21) | RSI | Confidence Scoring | Upstox Real-Time Prices")
    log.info("Scanning every %d mins during market hours (9:15–15:30 IST)\n", SCAN_INTERVAL_MIN)

    notify(f"🔍 <b>Stock Scanner Online</b>\n"
           f"📅 {datetime.now(IST).strftime('%d %b %Y %I:%M %p IST')}\n"
           f"📊 EMA(9/21) + RSI(14) | 15min\n"
           f"📋 Watching {len(NIFTY100)} NSE stocks\n"
           f"<i>Upstox real-time prices matching your account</i>")

    while True:
        try:
            if in_market_hours():
                run_scan()
            else:
                now = datetime.now(IST)
                log.info("[%s] Outside market hours. Waiting...", now.strftime("%H:%M"))
        except Exception as exc:
            log.error("Scan error: %s", exc)

        time.sleep(SCAN_INTERVAL_MIN * 60)

if __name__ == "__main__":
    main()
