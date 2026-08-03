from dotenv import load_dotenv
load_dotenv()
import requests
import pandas as pd
import time
import json
import os
import smtplib
import logging
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime, timedelta
from urllib.parse import quote
from reliability import AlertPolicy, StateStore, IST, acquire_instance_lock, as_ist, candle_timestamp, is_market_session, ist_now, next_scan_at
from nse_holidays import is_nse_holiday

# ── CONFIG ──────────────────────────────────────────────────────────────────
UPSTOX_TOKEN  = os.getenv("UPSTOX_TOKEN", "eyJ0eXAiOiJKV1QiLCJrZXlfaWQiOiJza192MS4wIiwiYWxnIjoiSFMyNTYifQ.eyJzdWIiOiI1SkNaWjgiLCJqdGkiOiI2YTY5OTM2NWQwODFlYzdmZGMzOTk3NDgiLCJpc011bHRpQ2xpZW50IjpmYWxzZSwiaXNQbHVzUGxhbiI6dHJ1ZSwiaXNFeHRlbmRlZCI6dHJ1ZSwiaWF0IjoxNzg1MzAzOTA5LCJpc3MiOiJ1ZGFwaS1nYXRld2F5LXNlcnZpY2UiLCJleHAiOjE4MTY4OTg0MDB9.7XoUhjIoWwI_g-OyAK8si_5PXEVhVb9i_vi80h_SMUI")
BOT_TOKEN     = os.getenv("TELEGRAM_BOT_TOKEN", "8953646046:AAF6flZRLHG7KU1JiagA48gJLcKZV7RuxKs")
CHAT_ID       = os.getenv("TELEGRAM_CHAT_ID", "7093601171")


EMAIL_TO       = "ajayoberoi1117@gmail.com"
EMAIL_FROM     = "ajayoberoi1117@gmail.com"
EMAIL_PASSWORD = "vstbuutmlhbxbpww"

MAX_SIGNALS_PER_DAY = 100
SL_PCT              = 2.0
TP_PCT              = 4.0
EMA_FAST            = 9
EMA_SLOW            = 21
LOOKBACK_DAYS       = 5       # 5 days of intraday data
SCAN_INTERVAL_SECONDS = int(os.getenv("SCANNER_INTERVAL_SECONDS", "60"))
ATR_PERIOD          = 14      # ATR period for dynamic stop-loss/take-profit
MAX_SIGNAL_AGE_SECONDS = int(os.getenv("MAX_SIGNAL_AGE_SECONDS", "180"))
HEARTBEAT_SECONDS = int(os.getenv("HEARTBEAT_SECONDS", "300"))
STRATEGY_NAME = "nifty100_ema9_21_rsi14"

# Trading hours IST (Monday-Friday, excluding NSE holidays)
MARKET_OPEN  = (9, 15)   # Market opens at 9:15 AM
MARKET_CLOSE = (15, 30)  # Market closes at 3:30 PM

# Capital by confidence
CAPITAL = {"HIGH": 200000, "MEDIUM": 150000, "LOW": 100000}

# State file to track signals sent today
STATE_FILE = os.path.join(os.path.dirname(__file__), ".scanner_state.json")
RELIABILITY_STATE_FILE = os.path.join(os.path.dirname(__file__), ".scanner_reliability.json")
HEALTH_FILE = os.path.join(os.path.dirname(__file__), ".scanner_health.json")
LOCK_FILE = os.path.join(os.path.dirname(__file__), ".scanner_bot.lock")

logging.basicConfig(format="%(asctime)s | SCANNER | %(levelname)s | %(message)s", level=logging.INFO)
log = logging.getLogger("nse_scanner")
reliability_store = StateStore(RELIABILITY_STATE_FILE)
alert_policy = AlertPolicy(reliability_store, max_age_seconds=MAX_SIGNAL_AGE_SECONDS)

# ── NIFTY 100 INSTRUMENT KEYS ────────────────────────────────────────────────
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
    "TATAMOTORS":   "NSE_EQ|INE155A01022",
    "JSWSTEEL":     "NSE_EQ|INE019A01038",
    "TATASTEEL":    "NSE_EQ|INE081A01020",
    "ADANIENT":     "NSE_EQ|INE423A01024",
    "ADANIPORTS":   "NSE_EQ|INE742F01042",
    "COALINDIA":    "NSE_EQ|INE522F01014",
    "BAJAJFINSV":   "NSE_EQ|INE918I01026",
    "BAJAJ-AUTO":   "NSE_EQ|INE917I01010",
    "TECHM":        "NSE_EQ|INE669C01036",
    "HINDALCO":     "NSE_EQ|INE038A01020",
    "GRASIM":       "NSE_EQ|INE047A01021",
    "INDUSINDBK":   "NSE_EQ|INE095A01012",
    "CIPLA":        "NSE_EQ|INE059A01026",
    "DRREDDY":      "NSE_EQ|INE089A01031",
    "DIVISLAB":     "NSE_EQ|INE361B01024",
    "BPCL":         "NSE_EQ|INE029A01011",
    "HEROMOTOCO":   "NSE_EQ|INE158A01026",
    "BRITANNIA":    "NSE_EQ|INE216A01030",
    "EICHERMOT":    "NSE_EQ|INE066A01021",
    "APOLLOHOSP":   "NSE_EQ|INE437A01024",
    "TATACONSUM":   "NSE_EQ|INE192A01025",
    "SBILIFE":      "NSE_EQ|INE123W01016",
    "HDFCLIFE":     "NSE_EQ|INE795G01014",
    "ICICIPRULI":   "NSE_EQ|INE726G01019",
    "UPL":          "NSE_EQ|INE628A01036",
    "M&M":          "NSE_EQ|INE101A01026",
    # NIFTY NEXT 50
    "ADANIGREEN":   "NSE_EQ|INE364U01010",
    "ADANITRANS":   "NSE_EQ|INE931S01010",
    "AMBUJACEM":    "NSE_EQ|INE079A01024",
    "AUROPHARMA":   "NSE_EQ|INE406A01037",
    "BANDHANBNK":   "NSE_EQ|INE545U01014",
    "BERGEPAINT":   "NSE_EQ|INE463A01038",
    "BIOCON":       "NSE_EQ|INE376G01013",
    "BOSCHLTD":     "NSE_EQ|INE323A01026",
    "CANBK":        "NSE_EQ|INE476A01022",
    "CHOLAFIN":     "NSE_EQ|INE121A01024",
    "COLPAL":       "NSE_EQ|INE259A01022",
    "CONCOR":       "NSE_EQ|INE111A01025",
    "DABUR":        "NSE_EQ|INE016A01026",
    "DLF":          "NSE_EQ|INE271C01023",
    "GAIL":         "NSE_EQ|INE129A01019",
    "GODREJCP":     "NSE_EQ|INE102D01028",
    "HAVELLS":      "NSE_EQ|INE176B01034",
    "ICICIGI":      "NSE_EQ|INE765G01017",
    "IDFCFIRSTB":   "NSE_EQ|INE092T01019",
    "IGL":          "NSE_EQ|INE203G01027",
    "INDUSTOWER":   "NSE_EQ|INE121J01017",
    "IOC":          "NSE_EQ|INE242A01010",
    "IRCTC":        "NSE_EQ|INE335Y01020",
    "JINDALSTEL":   "NSE_EQ|INE749A01030",
    "JUBLFOOD":     "NSE_EQ|INE797F01020",
    "LICI":         "NSE_EQ|INE0J1Y01017",
    "LUPIN":        "NSE_EQ|INE326A01037",
    "MARICO":       "NSE_EQ|INE196A01026",
    "MOTHERSON":    "NSE_EQ|INE775A01035",
    "MUTHOOTFIN":   "NSE_EQ|INE414G01012",
    "NAUKRI":       "NSE_EQ|INE663F01032",
    "NMDC":         "NSE_EQ|INE584A01023",
    "OFSS":         "NSE_EQ|INE881D01027",
    "PAGEIND":      "NSE_EQ|INE761H01022",
    "PIDILITIND":   "NSE_EQ|INE318A01026",
    "PNB":          "NSE_EQ|INE160A01022",
    "RECLTD":       "NSE_EQ|INE020B01018",
    "SAIL":         "NSE_EQ|INE114A01011",
    "SHREECEM":     "NSE_EQ|INE070A01015",
    "SIEMENS":      "NSE_EQ|INE003A01024",
    "SRF":          "NSE_EQ|INE647A01010",
    "TATAPOWER":    "NSE_EQ|INE245A01021",
    "TORNTPHARM":   "NSE_EQ|INE685A01028",
    "TRENT":        "NSE_EQ|INE849A01020",
    "VEDL":         "NSE_EQ|INE205A01025",
    "VOLTAS":       "NSE_EQ|INE226A01021",
    "ZOMATO":       "NSE_EQ|INE758T01015",
    "ZYDUSLIFE":    "NSE_EQ|INE010B01027",
}

HEADERS = {
    "Authorization": f"Bearer {UPSTOX_TOKEN}",
    "Accept": "application/json"
}

# ── STATE: track signals sent today ─────────────────────────────────────────
def load_state():
    today = datetime.now().strftime("%Y-%m-%d")
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE) as f:
            state = json.load(f)
        if state.get("date") == today:
            return state
    return {"date": today, "signals_sent": 0, "symbols_alerted": []}

def save_state(state):
    with open(STATE_FILE, "w") as f:
        json.dump(state, f)

# ── HELPERS ──────────────────────────────────────────────────────────────────
def fetch_candles_1min(symbol, instrument_key):
    """Try fetching 1-minute candles for more real-time data"""
    to_date   = datetime.now().strftime("%Y-%m-%d")
    from_date = (datetime.now() - timedelta(days=LOOKBACK_DAYS)).strftime("%Y-%m-%d")
    key_enc   = quote(instrument_key, safe="")
    url       = f"https://api.upstox.com/v2/historical-candle/{key_enc}/1minute/{to_date}/{from_date}"
    try:
        r = requests.get(url, headers=HEADERS, timeout=10)
        if r.status_code != 200:
            return None
        candles = r.json()["data"]["candles"]
        if len(candles) < 30:
            return None
        df = pd.DataFrame(candles, columns=["dt","open","high","low","close","volume","oi"])
        df = df.sort_values("dt").reset_index(drop=True)
        df["dt"] = pd.to_datetime(df["dt"], utc=True)
        df["close"]  = df["close"].astype(float)
        df["volume"] = df["volume"].astype(float)
        return df
    except Exception:
        log.exception("market_data_fetch_failed symbol=%s interval=1minute", symbol)
        return None

def send_telegram(msg):
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    for attempt in range(3):
        try:
            r = requests.post(url, data={"chat_id": CHAT_ID, "text": msg, "parse_mode": "HTML"}, timeout=(3, 10))
            if r.ok and r.json().get("ok"):
                return True
            log.error("telegram_rejected status=%s body=%s", r.status_code, r.text[:100])
            if r.status_code < 500 and r.status_code != 429:
                break
        except requests.ConnectTimeout:
            log.exception("telegram_attempt_failed attempt=%d", attempt + 1)
        except requests.RequestException:
            # A read timeout is ambiguous: Telegram may have accepted the
            # message. Do not retry and risk a duplicate alert.
            log.exception("telegram_delivery_ambiguous_no_retry attempt=%d", attempt + 1)
            break
        if attempt < 2:
            time.sleep(2 ** attempt)
    return False

def notify(msg):
    return send_telegram(msg)

def send_email(subject, html_body):
    try:
        msg = MIMEMultipart("alternative")
        msg["Subject"] = subject
        msg["From"]    = EMAIL_FROM
        msg["To"]      = EMAIL_TO
        html = f"<html><body style='font-family:monospace;white-space:pre'>{html_body}</body></html>"
        msg.attach(MIMEText(html, "html"))
        with smtplib.SMTP("smtp.gmail.com", 587) as server:
            server.starttls()
            server.login(EMAIL_FROM, EMAIL_PASSWORD)
            server.sendmail(EMAIL_FROM, EMAIL_TO, msg.as_string())
    except Exception as e:
        print(f"  Email failed: {e}")

def fetch_candles(symbol, instrument_key):
    to_date   = datetime.now().strftime("%Y-%m-%d")
    from_date = (datetime.now() - timedelta(days=LOOKBACK_DAYS)).strftime("%Y-%m-%d")
    key_enc   = quote(instrument_key, safe="")
    url       = f"https://api.upstox.com/v2/historical-candle/{key_enc}/30minute/{to_date}/{from_date}"
    try:
        r = requests.get(url, headers=HEADERS, timeout=10)
        if r.status_code != 200:
            print(f"    API error: {r.status_code} {r.text[:100]}")
            return None
        candles = r.json()["data"]["candles"]
        if len(candles) < 30:
            print(f"    Only {len(candles)} candles (need 30+)")
            return None
        df = pd.DataFrame(candles, columns=["dt","open","high","low","close","volume","oi"])
        df = df.sort_values("dt").reset_index(drop=True)
        df["dt"] = pd.to_datetime(df["dt"], utc=True)
        df["close"]  = df["close"].astype(float)
        df["volume"] = df["volume"].astype(float)

        # Check if latest candle is stale (more than 15 min old for better intraday signals)
        latest_ts = df["dt"].iloc[-1]
        now = ist_now()
        try:
            candle_time = candle_timestamp(latest_ts.to_pydatetime())
            age_minutes = (now - candle_time).total_seconds() / 60
            if age_minutes > 15:
                print(f"    ⚠️  Stale 30m: {age_minutes:.0f}min old")
                return None
        except (TypeError, ValueError, AttributeError):
            log.exception("invalid_candle_timestamp symbol=%s timestamp=%r", symbol, latest_ts)

        return df
    except (UnicodeEncodeError, UnicodeDecodeError) as e:
        print(f"    Token encoding error: {str(e)[:80]}")
        print(f"    UPSTOX_TOKEN may contain invalid characters. Check .env file.")
        return None
    except Exception as e:
        print(f"    Exception: {str(e)[:100]}")
        return None

def calculate_rsi(series, period=14):
    delta = series.diff()
    gain  = delta.where(delta > 0, 0).rolling(period).mean()
    loss  = (-delta.where(delta < 0, 0)).rolling(period).mean()
    rs    = gain / loss
    return 100 - (100 / (1 + rs))

def calculate_atr(df, period=14):
    high  = df["high"].astype(float)
    low   = df["low"].astype(float)
    close = df["close"].astype(float)
    tr1   = high - low
    tr2   = abs(high - close.shift())
    tr3   = abs(low - close.shift())
    tr    = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
    atr   = tr.rolling(period).mean()
    return atr

def score_signal(direction, price, c_e25, c_e50, p_e25, p_e50, c_rsi, vol_ratio):
    score = 0
    reasons = []

    # 1. EMA crossover today (strongest signal)
    if direction == "BUY":
        if p_e25 <= p_e50 and c_e25 > c_e50:
            score += 30
            reasons.append("EMA25 crossed above EMA50 today")
        elif c_e25 > c_e50:
            score += 20
            reasons.append("Price holding above EMA25 support")
    else:
        if p_e25 >= p_e50 and c_e25 < c_e50:
            score += 30
            reasons.append("EMA25 crossed below EMA50 today")
        elif c_e25 < c_e50:
            score += 20
            reasons.append("Price rejected at EMA25 resistance")

    # 2. RSI quality
    if direction == "BUY":
        if 52 <= c_rsi <= 63:
            score += 25
            reasons.append(f"RSI {round(c_rsi,1)} — ideal trending zone")
        elif 45 <= c_rsi < 52 or 63 < c_rsi <= 68:
            score += 15
            reasons.append(f"RSI {round(c_rsi,1)} — acceptable range")
    else:
        if 37 <= c_rsi <= 48:
            score += 25
            reasons.append(f"RSI {round(c_rsi,1)} — ideal downtrend zone")
        elif 32 <= c_rsi < 37 or 48 < c_rsi <= 55:
            score += 15
            reasons.append(f"RSI {round(c_rsi,1)} — acceptable range")

    # 3. Price vs EMA50 (trend confirmation)
    gap = abs(price - c_e50) / price * 100
    if direction == "BUY" and price > c_e50:
        if gap <= 5:
            score += 20
            reasons.append("Price near EMA50 — early breakout")
        else:
            score += 10
            reasons.append("Price above EMA50")
    elif direction == "SELL" and price < c_e50:
        if gap <= 5:
            score += 20
            reasons.append("Price near EMA50 — early breakdown")
        else:
            score += 10
            reasons.append("Price below EMA50")

    # 4. Volume boost
    if vol_ratio >= 1.5:
        score += 5
        reasons.append(f"Volume {round(vol_ratio,1)}x above average — strong conviction")
    elif vol_ratio >= 1.2:
        score += 3
        reasons.append(f"Volume {round(vol_ratio,1)}x above average")

    # Confidence tier
    if score >= 70:
        tier, emoji = "HIGH",   "🔥"
    elif score >= 50:
        tier, emoji = "MEDIUM", "✅"
    else:
        tier, emoji = "LOW",    "⚠️"

    return score, tier, emoji, reasons

def check_signal(symbol, df):
    close = df["close"]
    vol   = df["volume"]

    ema25 = close.ewm(span=EMA_FAST, adjust=False).mean()
    ema50 = close.ewm(span=EMA_SLOW, adjust=False).mean()
    rsi   = calculate_rsi(close)
    atr   = calculate_atr(df)

    p_e25, p_e50 = float(ema25.iloc[-2]), float(ema50.iloc[-2])
    c_e25, c_e50 = float(ema25.iloc[-1]), float(ema50.iloc[-1])
    c_rsi        = float(rsi.iloc[-1])
    c_atr        = float(atr.iloc[-1])
    price        = round(float(close.iloc[-1]), 2)
    vol_ratio    = float(vol.iloc[-1]) / float(vol.rolling(20).mean().iloc[-1])

    bullish_cross  = p_e25 <= p_e50 and c_e25 > c_e50
    ema_bounce_buy = c_e25 > c_e50 and abs(price - c_e25) / price < 0.004
    bearish_cross  = p_e25 >= p_e50 and c_e25 < c_e50
    ema_bounce_sel = c_e25 < c_e50 and abs(price - c_e25) / price < 0.004

    # A live alert represents a new setup, not merely an existing trend.  This
    # prevents every symbol above its EMA from becoming a startup alert.
    direction = None
    if bullish_cross and 45 <= c_rsi <= 68:
        direction = "BUY"

    if not direction:
        return None

    score, tier, t_emoji, reasons = score_signal(
        direction, price, c_e25, c_e50, p_e25, p_e50, c_rsi, vol_ratio
    )

    capital = CAPITAL[tier]
    qty     = max(1, int(capital / price))
    amt     = round(qty * price)

    if direction == "BUY":
        sl = round(price - c_atr, 2)
        tp = round(price + 2 * c_atr, 2)
    else:
        sl = round(price + c_atr, 2)
        tp = round(price - 2 * c_atr, 2)

    risk   = round(abs(price - sl) * qty)
    reward = round(abs(tp - price) * qty)

    candle_time = candle_timestamp(df["dt"].iloc[-1].to_pydatetime())
    mandatory_confirmations = bullish_cross and 52 <= c_rsi <= 63 and vol_ratio >= 1.2
    return (direction, price, sl, tp, qty, amt, risk, reward, score, tier,
            t_emoji, reasons, c_rsi, c_e25, c_e50, vol_ratio, candle_time,
            mandatory_confirmations)

def format_signal(direction, symbol, price, sl, tp, qty, amt, risk, reward,
                  score, tier, t_emoji, reasons, rsi, e25, e50, vol_ratio):
    now      = ist_now().strftime("%d-%b-%Y %H:%M IST")
    d_emoji  = "🟢" if direction == "BUY" else "🔴"
    arrow    = "📈" if direction == "BUY" else "📉"
    tip      = {
        "HIGH":   "Strong setup — all indicators aligned. Consider full position.",
        "MEDIUM": "Good setup — proceed with normal SL. Standard position.",
        "LOW":    "Borderline signal — reduce position size or wait for better entry.",
    }[tier]
    reason_text = "\n".join(f"  • {r}" for r in reasons)

    return (
        f"{d_emoji} <b>{direction} SIGNAL — {symbol}</b>\n"
        f"{t_emoji} <b>Confidence: {tier}  ({score}/100)</b>\n"
        f"━━━━━━━━━━━━━━━━━━━━\n"
        f"💰 <b>Entry     :</b> ₹{price}\n"
        f"🛑 <b>Stop Loss :</b> ₹{sl}  (-{SL_PCT}%)\n"
        f"🎯 <b>Take Profit:</b> ₹{tp}  (+{TP_PCT}%)\n"
        f"━━━━━━━━━━━━━━━━━━━━\n"
        f"📦 <b>Qty       :</b> {qty} shares  (~₹{amt:,})\n"
        f"⚠️  <b>Max Risk  :</b> ₹{risk:,}   <b>Reward:</b> ₹{reward:,}  (1:{round(reward/risk,1)})\n"
        f"━━━━━━━━━━━━━━━━━━━━\n"
        f"{arrow} <b>Why this signal:</b>\n{reason_text}\n"
        f"📊 RSI: {round(rsi,1)}  |  EMA{EMA_FAST}: ₹{round(e25,2)}  |  EMA{EMA_SLOW}: ₹{round(e50,2)}\n"
        f"📣 Volume: {round(vol_ratio,1)}x avg\n"
        f"━━━━━━━━━━━━━━━━━━━━\n"
        f"💡 <i>{tip}</i>\n"
        f"⏰ {now}"
    )

# ── MAIN SCAN ────────────────────────────────────────────────────────────────
def write_health():
    state = reliability_store.state
    payload = {
        "bot_name": "nse-intraday-scanner",
        "process_start_time": state.process_start,
        "last_heartbeat": state.last_heartbeat,
        "last_successful_scan": state.last_successful_scan,
        "last_market_data_timestamp": state.last_market_data_timestamp,
        "symbols_scanned": state.symbols_scanned,
        "last_signal_time": state.last_signal_time,
        "number_of_signals_today": state.signals_today,
        "current_error_state": state.current_error,
        "next_scan_time": state.next_scan_time,
    }
    temporary = HEALTH_FILE + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, sort_keys=True)
    os.replace(temporary, HEALTH_FILE)


def run_scan(now=None, live_mode=True):
    now = as_ist(now or ist_now())
    state = load_state()

    if state["signals_sent"] >= MAX_SIGNALS_PER_DAY:
        print(f"Max {MAX_SIGNALS_PER_DAY} signals already sent today. Skipping scan.")
        return

    remaining = MAX_SIGNALS_PER_DAY - state["signals_sent"]
    print(f"\n{'='*55}")
    print(f"Scan: {now.strftime('%d-%b-%Y %H:%M:%S %Z')}  |  Signals left today: {remaining}")
    print(f"{'='*55}")

    new_signals = 0
    scanned = 0
    rejected = {}

    for symbol, ikey in NIFTY100.items():
        if state["signals_sent"] + new_signals >= MAX_SIGNALS_PER_DAY:
            break

        # Skip if already alerted today
        if symbol in state["symbols_alerted"]:
            continue

        print(f"  {symbol:<14}", end=" ")

        # During market hours (9:15-15:30), use 1-minute candles for real-time signals
        # 30-minute candles are too slow for intraday trading
        df = fetch_candles_1min(symbol, ikey)
        used_1min = True

        # If 1-minute fails, fallback to 30-minute
        if df is None:
            df = fetch_candles(symbol, ikey)
            used_1min = False

        if df is None:
            print("skip")
            continue

        scanned += 1
        latest_market_time = candle_timestamp(df["dt"].iloc[-1].to_pydatetime())
        if reliability_store.state.first_data_fetch is None:
            reliability_store.state.first_data_fetch = ist_now().isoformat()
        reliability_store.state.last_market_data_timestamp = latest_market_time.isoformat()
        if scanned == 1 or scanned % 10 == 0:
            reliability_store.state.last_heartbeat = ist_now().isoformat()
            reliability_store.state.symbols_scanned = scanned
            reliability_store.save()
            write_health()
        if reliability_store.state.first_evaluation is None:
            reliability_store.state.first_evaluation = ist_now().isoformat()
        result = check_signal(symbol, df)

        if not result:
            ema9 = df["close"].ewm(span=EMA_FAST, adjust=False).mean().iloc[-1]
            ema21 = df["close"].ewm(span=EMA_SLOW, adjust=False).mean().iloc[-1]
            rsi = df["close"].diff().rolling(14).apply(lambda x: 100 - 100/(1 + (x[x>0].mean() / -x[x<0].mean())), raw=False).iloc[-1]
            interval = "1m" if used_1min else "30m"
            print(f"    [{interval}] [EMA9: ₹{ema9:.2f} | EMA21: ₹{ema21:.2f} | RSI: {rsi:.1f}]")

        if result:
            (direction, price, sl, tp, qty, amt, risk, reward,
             score, tier, t_emoji, reasons, rsi, e25, e50, vol_ratio,
             candle_time, confirmations_pass) = result

            decision = alert_policy.evaluate(
                strategy=STRATEGY_NAME, symbol=symbol, direction=direction,
                confidence=tier, confirmations_pass=confirmations_pass,
                candle=candle_time, now=now, live_mode=live_mode,
            )
            if not decision.allowed:
                rejected[decision.reason] = rejected.get(decision.reason, 0) + 1
                print(f"→ {direction} | {tier} ({score}/100) [filtered: {decision.reason}]")
                continue

            msg = format_signal(direction, symbol, price, sl, tp, qty, amt,
                                 risk, reward, score, tier, t_emoji, reasons,
                                 rsi, e25, e50, vol_ratio)
            print(f"→ {direction} | {tier} ({score}/100) | ₹{price} | SL ₹{sl} | TP ₹{tp}")
            if notify(msg):
                alert_policy.mark_delivered(decision, STRATEGY_NAME, symbol, direction, candle_time, now)
                send_email(f"[NSE Signal] {direction} {symbol} — {tier} ({score}/100)", msg)
                state["symbols_alerted"].append(symbol)
                new_signals += 1
            else:
                rejected["telegram_delivery_failed"] = rejected.get("telegram_delivery_failed", 0) + 1
        else:
            print("no signal")

        time.sleep(0.3)

    state["signals_sent"] += new_signals
    save_state(state)

    reliability_store.state.symbols_scanned = scanned
    reliability_store.state.last_successful_scan = now.isoformat()
    reliability_store.state.current_error = None
    reliability_store.save()
    write_health()

    print(f"\nDone. {new_signals} new signal(s). Total today: {state['signals_sent']}/{MAX_SIGNALS_PER_DAY}")
    log.info("scan_complete symbols_scanned=%d candidates_rejected=%s alerts_emitted=%d data_timestamp=%s",
             scanned, rejected, new_signals, reliability_store.state.last_market_data_timestamp)
    return {"symbols_scanned": scanned, "alerts_emitted": new_signals, "rejected": rejected}

# ── ENTRY ────────────────────────────────────────────────────────────────────
def in_market_hours(now=None):
    return is_market_session(as_ist(now or ist_now()), is_nse_holiday)

def main():
    instance_lock = acquire_instance_lock(LOCK_FILE)
    started = ist_now()
    reliability_store.state.process_start = started.isoformat()
    reliability_store.state.current_error = None
    reliability_store.save()
    log.info("process_start bot=nse-intraday-scanner build=%s environment=%s timezone=%s",
             os.getenv("BOT_BUILD", "development"), os.getenv("BOT_ENV", "local"), str(IST))
    print("NSE Intraday Scanner — Nifty 100")
    print(f"EMA{EMA_FAST}/EMA{EMA_SLOW} + RSI({ATR_PERIOD}) | 30-min candles (fallback to 1-min if stale)")
    print(f"SL = 1x ATR  |  TP = 2x ATR  |  HIGH ₹2L / MEDIUM ₹1.5L / LOW ₹1L")
    print(f"Signals all day during market hours (9:15–15:30 IST)")
    print(f"Scanning every {SCAN_INTERVAL_SECONDS} seconds")
    print(f"Token: {UPSTOX_TOKEN[:20]}...{UPSTOX_TOKEN[-10:]}\n")

    startup_notified = False
    last_heartbeat = None

    while True:
        now = ist_now()
        try:
            if in_market_hours(now):
                if not startup_notified:
                    log.info("market_open_detected time=%s", now.isoformat())
                    startup_text = now.strftime("%d-%b-%Y %H:%M IST")
                    notify(f"🤖 <b>NSE Intraday Scanner Started</b>\n\n"
                       f"Bot launched and ready to scan.\n"
                       f"EMA{EMA_FAST}/{EMA_SLOW} • SL {SL_PCT}% / TP {TP_PCT}%\n"
                       f"Scanning every {SCAN_INTERVAL_SECONDS} seconds\n\n"
                       f"⏰ {startup_text}")
                    startup_notified = True
                run_scan(now)
            else:
                startup_notified = False
                log.info("outside_market_hours time=%s", now.isoformat())

            after_scan = ist_now()
            next_scan = next_scan_at(after_scan, SCAN_INTERVAL_SECONDS)
            reliability_store.state.next_scan_time = next_scan.isoformat()
            if last_heartbeat is None or (now - last_heartbeat).total_seconds() >= HEARTBEAT_SECONDS:
                reliability_store.state.last_heartbeat = now.isoformat()
                last_heartbeat = now
                log.info("heartbeat market_open=%s last_scan=%s next_scan=%s error=%s",
                         in_market_hours(now), reliability_store.state.last_successful_scan,
                         next_scan.isoformat(), reliability_store.state.current_error)
            reliability_store.save()
            write_health()
            time.sleep(max(0.1, (next_scan - ist_now()).total_seconds()))
        except KeyboardInterrupt:
            log.info("graceful_shutdown reason=keyboard_interrupt")
            break
        except Exception as exc:
            reliability_store.state.current_error = f"{type(exc).__name__}: {exc}"
            reliability_store.save()
            write_health()
            log.exception("scan_loop_failure; retrying with bounded backoff")
            time.sleep(min(30, SCAN_INTERVAL_SECONDS))

if __name__ == "__main__":
    main()
