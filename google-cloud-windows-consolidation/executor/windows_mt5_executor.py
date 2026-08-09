"""
Windows MT5 Trade Executor (Windows Consolidation)
Reads signals from C:\TradingBots\state\.trade_queue.jsonl
Executes via MetaTrader5 Python API with fail-closed safety gates.
Implements double-gate production: BOT_EXECUTION_MODE + LIVE_TRADING_CONFIRMED
"""

import os
import sys
import json
import time
import logging
from datetime import datetime
from pathlib import Path
from dotenv import load_dotenv

try:
    import MetaTrader5 as mt5
except ImportError:
    print("ERROR: MetaTrader5 package not installed.")
    print("Run: pip install MetaTrader5")
    sys.exit(1)

import requests

load_dotenv()

# Windows-specific paths
TRADING_BOTS_ROOT = Path("C:\\TradingBots")
LOGS_DIR = TRADING_BOTS_ROOT / "logs"
STATE_DIR = TRADING_BOTS_ROOT / "state"
LOGS_DIR.mkdir(parents=True, exist_ok=True)
STATE_DIR.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    format="%(asctime)s | MT5_EXECUTOR | %(levelname)s | %(message)s",
    level=logging.INFO,
    handlers=[
        logging.FileHandler(str(LOGS_DIR / "mt5_executor.log"), encoding="utf-8"),
        logging.StreamHandler()
    ]
)
log = logging.getLogger(__name__)

# ─── Configuration ─────────────────────────────────────────────────────────
MT5_LOGIN = int(os.getenv("MT5_LOGIN", "0"))
MT5_PASSWORD = os.getenv("MT5_PASSWORD", "")
MT5_SERVER = os.getenv("MT5_SERVER", "")

TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "")

BOT_EXECUTION_MODE = os.getenv("BOT_EXECUTION_MODE", "signal_only").strip().lower()
LIVE_TRADING_CONFIRMED = os.getenv("LIVE_TRADING_CONFIRMED", "").strip().upper()

# Queue and history files in state directory
QUEUE_FILE = str(STATE_DIR / ".trade_queue.jsonl")
HISTORY_FILE = str(STATE_DIR / ".trade_history.jsonl")

POLL_SECS = 5
MAX_QUEUE_AGE = 300  # skip signals older than 5 minutes

# Magic numbers per bot+timeframe
MAGIC_MAP = {
    "EURUSD_1H": 10101,
    "GBPUSD_1H": 10201,
    "USDJPY_1H": 10301,
    "XAUUSD_1H": 10401,
    "BTCUSD_1H": 10501,
    "EURUSD_15m": 10102,
    "GBPUSD_15m": 10202,
    "USDJPY_15m": 10302,
    "XAUUSD_15m": 10402,
}
DEFAULT_MAGIC = 10000

# Allowed symbols (same as trade_executor.py)
TRADEABLE = {"EURUSD", "GBPUSD", "USDJPY", "XAUUSD", "BTCUSD"}


# ─── Execution Guards ──────────────────────────────────────────────────────

def get_execution_mode() -> str:
    """Parse and validate execution mode (fail-closed)."""
    ALLOWED_MODES = {"dry_run", "signal_only", "production"}
    mode = BOT_EXECUTION_MODE

    if mode not in ALLOWED_MODES:
        raise RuntimeError(
            f"BOT_EXECUTION_MODE must be one of: {', '.join(sorted(ALLOWED_MODES))} "
            f"(got: {repr(mode)})"
        )
    return mode


def order_execution_enabled() -> bool:
    """
    Determine if order execution is allowed (double-gate).
    PRODUCTION requires BOTH: BOT_EXECUTION_MODE=production AND LIVE_TRADING_CONFIRMED=YES
    """
    mode = get_execution_mode()
    if mode != "production":
        return False

    if LIVE_TRADING_CONFIRMED != "YES":
        return False

    return True


def validate_config():
    """Validate required configuration at startup."""
    errors = []

    if not MT5_LOGIN or not MT5_PASSWORD or not MT5_SERVER:
        errors.append("Missing MT5_LOGIN, MT5_PASSWORD, or MT5_SERVER in .env")

    try:
        get_execution_mode()
    except RuntimeError as e:
        errors.append(str(e))

    if errors:
        for err in errors:
            log.error("CONFIG ERROR: %s", err)
        sys.exit(1)

    log.info("Configuration validated")
    log.info("  Mode: %s", get_execution_mode())
    log.info("  Order execution enabled: %s", order_execution_enabled())


# ─── Telegram ──────────────────────────────────────────────────────────────

def tg_send(text: str) -> bool:
    """Send Telegram notification (safe to call even if token missing)."""
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        return False

    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    try:
        r = requests.post(
            url,
            data={"chat_id": TELEGRAM_CHAT_ID, "text": text, "parse_mode": "HTML"},
            timeout=10
        )
        if not r.json().get("ok"):
            log.warning("Telegram send failed: %s", r.text[:100])
            return False
        return True
    except Exception as e:
        log.warning("Telegram error: %s", e)
        return False


# ─── Queue Management ──────────────────────────────────────────────────────

def read_and_clear_queue() -> list:
    """Read trade queue and clear it."""
    if not os.path.exists(QUEUE_FILE):
        return []

    try:
        with open(QUEUE_FILE, "r+") as f:
            lines = f.readlines()
            f.seek(0)
            f.truncate()

        signals = []
        for line in lines:
            line = line.strip()
            if line:
                try:
                    signals.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
        return signals
    except Exception as e:
        log.warning("Queue read error: %s", e)
        return []


def write_history(signal: dict, result: str) -> None:
    """Log trade to history file."""
    try:
        record = dict(signal)
        record["result"] = result
        record["executed_at"] = datetime.now().isoformat()
        with open(HISTORY_FILE, "a") as f:
            f.write(json.dumps(record) + "\n")
    except Exception:
        pass


# ─── Order Execution ───────────────────────────────────────────────────────

def place_order(symbol: str, direction: str, sl: float, tp: float, magic: int) -> bool:
    """Place a market order via MT5."""
    try:
        info = mt5.symbol_info(symbol)
        if info is None:
            log.error("Symbol %s not found", symbol)
            return False

        if not info.visible:
            mt5.symbol_select(symbol, True)
            time.sleep(0.2)

        tick = mt5.symbol_info_tick(symbol)
        if tick is None:
            log.error("No tick data for %s", symbol)
            return False

        order_type = mt5.ORDER_TYPE_BUY if direction == "BUY" else mt5.ORDER_TYPE_SELL
        price = tick.ask if direction == "BUY" else tick.bid

        req = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": symbol,
            "volume": 0.01,  # Fixed minimum lot
            "type": order_type,
            "price": price,
            "sl": sl,
            "tp": tp,
            "deviation": 30,
            "magic": magic,
            "comment": "GCP-Bot",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }

        result = mt5.order_send(req)
        if result is None:
            log.error("order_send returned None for %s", symbol)
            return False

        if result.retcode == mt5.TRADE_RETCODE_DONE:
            log.info("✅ TRADE PLACED | %s %s | ticket=%d | price=%.5f | SL=%.5f | TP=%.5f",
                     direction, symbol, result.order, price, sl, tp)
            return True
        else:
            log.error("❌ Trade failed | %s %s | retcode=%d | %s",
                      direction, symbol, result.retcode, result.comment)
            return False
    except Exception as e:
        log.error("Order placement error: %s", e)
        return False


def process_signal(signal: dict) -> bool:
    """Process a single trade signal."""
    try:
        symbol = signal.get("symbol", "").upper()
        direction = signal.get("direction", "").upper()
        sl = float(signal.get("sl", 0))
        tp = float(signal.get("tp", 0))
        source = signal.get("source", "")
        ts = signal.get("ts", time.time())

        # Validate symbol
        if symbol not in TRADEABLE:
            log.debug("SKIP: %s not in tradeable list", symbol)
            write_history(signal, f"skipped_symbol_not_tradeable")
            return False

        # Check age
        age = time.time() - ts
        if age > MAX_QUEUE_AGE:
            log.warning("SKIP: stale %s %s (age=%.0fs)", direction, symbol, age)
            write_history(signal, f"skipped_stale age={age:.0f}s")
            return False

        magic = MAGIC_MAP.get(source, DEFAULT_MAGIC)

        # Check execution guards
        mode = get_execution_mode()
        if mode == "signal_only" or mode == "dry_run":
            log.info("SIGNAL (no execute): %s %s | SL=%.5g | TP=%.5g | magic=%d",
                     direction, symbol, sl, tp, magic)
            write_history(signal, f"signal_only_mode")
            tg_send(f"📊 Signal: {direction} {symbol} @ SL={sl:.5g} TP={tp:.5g}\n"
                    f"⚠️ Signal-only mode (no order placed)")
            return True

        # Production mode: execute only if double-gate passed
        if not order_execution_enabled():
            log.warning("SKIP: Production mode requires LIVE_TRADING_CONFIRMED=YES")
            write_history(signal, "skipped_execution_guard_failed")
            return False

        # Attempt order
        ok = place_order(symbol, direction, sl, tp, magic)
        if ok:
            write_history(signal, "executed_success")
            tg_send(f"✅ Trade: {direction} {symbol}\n"
                    f"📍 SL={sl:.5g} | TP={tp:.5g}")
        else:
            write_history(signal, "executed_failed")
            tg_send(f"❌ Trade Failed: {direction} {symbol}\n"
                    f"Check logs for details")
        return ok

    except Exception as e:
        log.error("Error processing signal: %s", e)
        write_history(signal, f"error: {str(e)[:50]}")
        return False


def main():
    """Main executor loop."""
    validate_config()

    log.info("Initializing MT5 | login=%d | server=%s", MT5_LOGIN, MT5_SERVER)
    if not mt5.initialize(login=MT5_LOGIN, password=MT5_PASSWORD, server=MT5_SERVER):
        log.error("MT5 initialization failed: %s", mt5.last_error())
        sys.exit(1)

    acc = mt5.account_info()
    log.info("Connected | Account: %s | Balance: %.2f %s",
             acc.name, acc.balance, acc.currency)

    # CRITICAL SAFETY GATE: Verify DEMO account
    if acc.trade_mode != 0:  # 0 = DEMO, 1 = REAL (via MetaTrader5.ACCOUNT_TRADE_MODE_DEMO/REAL)
        log.error("FATAL: Account is NOT DEMO (mode=%d). Refusing to proceed.", acc.trade_mode)
        log.error("This executor only accepts DEMO accounts for safety.")
        mt5.shutdown()
        sys.exit(1)

    log.info("✅ DEMO account verified (mode=%d, name=%s)", acc.trade_mode, acc.name)

    mode = get_execution_mode()
    demo_badge = "🎓 DEMO" if acc.trade_mode == 0 else "⚠️ REAL"
    tg_send(f"🤖 MT5 Executor Online\n"
            f"📅 {datetime.now().strftime('%d %b %Y %I:%M %p')}\n"
            f"⚖️ Mode: {mode}\n"
            f"{demo_badge} | Account: {acc.name}\n"
            f"💰 Balance: {acc.balance:,.2f} {acc.currency}\n"
            f"✅ Ready for signals")

    log.info("Executor ready | Polling queue every %ds | Mode: %s",
             POLL_SECS, mode)

    try:
        while True:
            time.sleep(POLL_SECS)

            signals = read_and_clear_queue()
            for sig in signals:
                process_signal(sig)

    except KeyboardInterrupt:
        log.info("Shutdown requested")
    except Exception as e:
        log.error("Unexpected error: %s", e)
    finally:
        mt5.shutdown()
        log.info("MT5 shutdown")


if __name__ == "__main__":
    main()
