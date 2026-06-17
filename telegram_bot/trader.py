"""
MT5 Auto-Trader via MetaAPI Cloud
===================================
Daemon that reads trade signals from .trade_queue.jsonl written by signal bots
and executes them on the Vantage demo MT5 account via MetaAPI.

One-time setup on VPS:
  1. Sign up free at https://metaapi.cloud
  2. Click "Add account" → MetaTrader 5 → enter your broker credentials:
       Login:    25285913  (or your login from MT5 terminal)
       Password: <your Vantage demo password>
       Server:   VantageMarkets-Demo
  3. Profile → API Tokens → copy your token
  4. On VPS: sed -i 's/^META_API_TOKEN=.*/META_API_TOKEN=<token>/' /root/MediDeals-iOS-App/telegram_bot/.env
  5. Also set MT5_PASSWORD in .env if not already set

This script auto-finds your account by MT5 login number on first run.
"""

import os
import sys
import json
import time
import asyncio
import logging
from datetime import datetime
from dotenv import load_dotenv

load_dotenv()

logging.basicConfig(
    format="%(asctime)s | TRADER   | %(levelname)s | %(message)s",
    level=logging.INFO,
)
log = logging.getLogger(__name__)

META_API_TOKEN = os.getenv("META_API_TOKEN", "")
MT5_LOGIN      = os.getenv("MT5_LOGIN",    "25285913")
MT5_PASSWORD   = os.getenv("MT5_PASSWORD", "")
MT5_SERVER     = os.getenv("MT5_SERVER",   "VantageMarkets-Demo")

QUEUE_FILE   = os.path.join(os.path.dirname(__file__), ".trade_queue.jsonl")
HISTORY_FILE = os.path.join(os.path.dirname(__file__), ".trade_history.jsonl")

LOT_SIZE      = 0.01    # micro lot — safe for demo testing
POLL_SECS     = 5       # check queue every 5 seconds
MAX_QUEUE_AGE = 300     # discard signals older than 5 minutes (stale price)

# MT5 symbol names on Vantage (bot names → broker symbol)
SYMBOL_MAP = {
    "EURUSD": "EURUSD",
    "GBPUSD": "GBPUSD",
    "USDJPY": "USDJPY",
    "XAUUSD": "XAUUSD",
    "BTCUSD": "BTCUSD",
}


def _read_and_clear_queue() -> list:
    """Atomically read and empty the queue file."""
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
    except Exception as exc:
        log.warning("Queue read error: %s", exc)
        return []


def _write_history(signal: dict, result: str) -> None:
    try:
        record = dict(signal)
        record["result"]      = result
        record["executed_at"] = datetime.now().isoformat()
        with open(HISTORY_FILE, "a") as f:
            f.write(json.dumps(record) + "\n")
    except Exception:
        pass


async def _get_or_create_account(api):
    """Find existing MetaAPI account by MT5 login, or register it fresh."""
    try:
        result = await api.metatrader_account_api.get_accounts_with_infinite_scroll_pagination(
            {"limit": 100, "offset": 0}
        )
        for acc in result.get("items", []):
            if str(acc.login) == str(MT5_LOGIN):
                log.info("Found existing MetaAPI account: %s (id=%s)", acc.name, acc.id)
                return acc
    except Exception as exc:
        log.warning("Could not list MetaAPI accounts: %s", exc)

    log.info("Registering MT5 account %s on MetaAPI for the first time...", MT5_LOGIN)
    account = await api.metatrader_account_api.create_account({
        "name":     f"Vantage Demo {MT5_LOGIN}",
        "type":     "cloud",
        "login":    str(MT5_LOGIN),
        "password": MT5_PASSWORD,
        "server":   MT5_SERVER,
        "platform": "mt5",
        "magic":    47,
    })
    log.info("Account registered: id=%s", account.id)
    return account


async def run_trader():
    if not META_API_TOKEN:
        log.error("META_API_TOKEN not set in .env")
        log.error("  1. Sign up at https://metaapi.cloud (free)")
        log.error("  2. Add MT5 account: login=%s  server=%s", MT5_LOGIN, MT5_SERVER)
        log.error("  3. Copy token from Profile → API Tokens")
        log.error("  4. Set META_API_TOKEN=<token> in .env")
        sys.exit(1)

    if not MT5_PASSWORD:
        log.error("MT5_PASSWORD not set in .env — cannot connect to broker")
        sys.exit(1)

    try:
        from metaapi_cloud_sdk import MetaApi
    except ImportError:
        log.error("metaapi-cloud-sdk not installed. Run: pip install metaapi-cloud-sdk")
        sys.exit(1)

    log.info("Connecting to MetaAPI (login=%s  server=%s)...", MT5_LOGIN, MT5_SERVER)
    api = MetaApi(META_API_TOKEN)

    account = await _get_or_create_account(api)

    log.info("Deploying account and connecting to broker...")
    await account.deploy()
    await account.wait_connected()

    conn = account.get_rpc_connection()
    await conn.connect()
    await conn.wait_synchronized()

    log.info("Ready to trade | lot=%.2f  poll=%ds  account=%s", LOT_SIZE, POLL_SECS, MT5_LOGIN)
    log.info("Watching queue: %s", QUEUE_FILE)

    while True:
        await asyncio.sleep(POLL_SECS)

        signals = _read_and_clear_queue()
        if not signals:
            continue

        for sig in signals:
            age = time.time() - sig.get("ts", 0)
            if age > MAX_QUEUE_AGE:
                log.warning("SKIP stale: %s %s (age=%.0fs > %ds)",
                            sig.get("direction"), sig.get("symbol"), age, MAX_QUEUE_AGE)
                _write_history(sig, f"skipped_stale age={age:.0f}s")
                continue

            symbol    = SYMBOL_MAP.get(sig["symbol"], sig["symbol"])
            direction = sig["direction"].upper()
            sl        = float(sig["sl"])
            tp        = float(sig["tp"])
            src       = sig.get("source", "")

            log.info("Placing %s %s  lot=%.2f  SL=%.5g  TP=%.5g  src=%s",
                     direction, symbol, LOT_SIZE, sl, tp, src)
            try:
                if direction == "BUY":
                    result = await conn.create_market_buy_order(
                        symbol, LOT_SIZE, sl, tp, {"comment": f"bot:{src}"}
                    )
                else:
                    result = await conn.create_market_sell_order(
                        symbol, LOT_SIZE, sl, tp, {"comment": f"bot:{src}"}
                    )
                order_id = result.get("orderId", "?")
                log.info("Trade placed: orderId=%s", order_id)
                _write_history(sig, f"ok orderId={order_id}")
            except Exception as exc:
                log.error("Trade execution error (%s %s): %s", direction, symbol, exc)
                _write_history(sig, f"error: {exc}")


def main():
    asyncio.run(run_trader())


if __name__ == "__main__":
    main()
