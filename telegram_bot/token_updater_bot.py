"""
Token Updater Bot
Listens for Telegram commands from the authorized user.
/upstox <token>  — update UPSTOX_TOKEN in .env and restart Indian bots
/status          — show live status of all 8 bots
"""

import os
import re
import subprocess
import time
import logging
import requests
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

# ── Config ────────────────────────────────────────────────────────────────────

TELEGRAM_TOKEN  = os.getenv("ELITE_BOT_TOKEN", "")
AUTHORIZED_CHAT = str(os.getenv("SIGNAL_CHAT_ID", "1994067941"))
ENV_PATH        = Path(__file__).parent / ".env"
BOT_DIR         = Path(__file__).parent
POLL_TIMEOUT    = 30

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    format="%(asctime)s | TOKEN_BOT | %(levelname)s | %(message)s",
    level=logging.INFO,
)
log = logging.getLogger(__name__)

# ── Telegram helpers ──────────────────────────────────────────────────────────

def tg_send(chat_id: str, text: str) -> None:
    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
    try:
        requests.post(url,
                      data={"chat_id": chat_id, "text": text, "parse_mode": "HTML"},
                      timeout=10)
    except Exception as exc:
        log.warning("Telegram error: %s", exc)


def get_updates(offset: int) -> list:
    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/getUpdates"
    try:
        r = requests.get(url,
                         params={"timeout": POLL_TIMEOUT, "offset": offset},
                         timeout=POLL_TIMEOUT + 10)
        return r.json().get("result", [])
    except Exception as exc:
        log.warning("getUpdates error: %s", exc)
        return []

# ── .env updater ──────────────────────────────────────────────────────────────

def update_upstox_token(new_token: str) -> None:
    content = ENV_PATH.read_text()
    if "UPSTOX_TOKEN=" in content:
        content = re.sub(
            r"^UPSTOX_TOKEN=.*$",
            f"UPSTOX_TOKEN={new_token}",
            content,
            flags=re.MULTILINE,
        )
    else:
        content += f"\nUPSTOX_TOKEN={new_token}\n"
    ENV_PATH.write_text(content)
    os.environ["UPSTOX_TOKEN"] = new_token
    log.info("UPSTOX_TOKEN updated in .env")

# ── Bot restart ───────────────────────────────────────────────────────────────

def restart_indian_bots() -> None:
    """Kill Upstox-dependent bots. Watchdog restarts them within 5 minutes."""
    for bot in ["nifty_scalper.py", "scanner_bot.py"]:
        result = subprocess.run(["pkill", "-f", bot], capture_output=True)
        log.info("pkill %s → rc=%d", bot, result.returncode)
    log.info("Indian bots killed — watchdog will restart them shortly")

# ── Status check ──────────────────────────────────────────────────────────────

_BOT_LABELS = [
    ("eurusd_bot.py",        "EURUSD 1H"),
    ("gbpusd_bot.py",        "GBPUSD 1H"),
    ("usdjpy_bot.py",        "USDJPY 1H"),
    ("gold_bot.py",          "XAUUSD 1H"),
    ("nifty_scalper.py",     "Nifty 15m"),
    ("scanner_bot.py",       "Scanner 15m"),
    ("forex_scalper.py",     "Forex Scalper"),
    ("token_updater_bot.py", "Token Updater"),
    ("btc_bot.py",           "BTCUSD 1H"),
]

def build_status_message() -> str:
    lines = ["🤖 <b>Bot Status Dashboard</b>", "━━━━━━━━━━━━━━━━━━━━━━"]
    all_ok = True
    for script, label in _BOT_LABELS:
        running = subprocess.run(["pgrep", "-f", script], capture_output=True).returncode == 0
        icon = "🟢" if running else "🔴"
        if not running:
            all_ok = False
        lines.append(f"{icon} <b>{label}</b>")
    lines += [
        "━━━━━━━━━━━━━━━━━━━━━━",
        "✅ All bots running" if all_ok else "⚠️ Some bots are down (watchdog will restart)",
    ]
    return "\n".join(lines)

# ── Message handler ───────────────────────────────────────────────────────────

def handle_message(msg: dict) -> None:
    chat_id = str(msg.get("chat", {}).get("id", ""))
    text    = msg.get("text", "").strip()

    if chat_id != AUTHORIZED_CHAT:
        log.info("Ignored message from unauthorized chat_id=%s", chat_id)
        return

    if text.lower().startswith("/upstox "):
        new_token = text[len("/upstox "):].strip()

        if len(new_token) < 50:
            tg_send(chat_id,
                "❌ Token looks too short.\n"
                "Paste the full JWT access token after /upstox\n"
                "Example: <code>/upstox eyJhbGc...</code>")
            return

        update_upstox_token(new_token)
        restart_indian_bots()

        tg_send(chat_id,
            "✅ <b>Upstox Token Updated!</b>\n"
            "━━━━━━━━━━━━━━━━━━━━━━\n"
            "🔄 Nifty Scalper &amp; Stock Scanner are restarting...\n"
            "⏱ Back online in &lt;5 minutes (watchdog will restart them)\n"
            "📊 Next signal will use the fresh token.\n"
            "━━━━━━━━━━━━━━━━━━━━━━")
        log.info("Upstox token updated and Indian bots restarted via Telegram command.")

    elif text.lower() == "/status":
        tg_send(chat_id, build_status_message())
        log.info("Status report sent.")

    elif text.lower() == "/help":
        tg_send(chat_id,
            "🔑 <b>Token Updater Commands</b>\n"
            "━━━━━━━━━━━━━━━━━━━━━━\n"
            "/upstox &lt;token&gt; — Update Upstox access token\n"
            "/status — Check all 8 bots are running\n"
            "/help — Show this message\n"
            "━━━━━━━━━━━━━━━━━━━━━━\n"
            "<i>Copy your daily access token from Upstox algo setup and send:\n"
            "/upstox eyJhbGc...</i>")

# ── Main loop ─────────────────────────────────────────────────────────────────

def main() -> None:
    if not TELEGRAM_TOKEN:
        raise SystemExit("ELITE_BOT_TOKEN not set in .env")

    log.info("Token Updater Bot started | authorized_chat=%s", AUTHORIZED_CHAT)

    tg_send(AUTHORIZED_CHAT,
        "🔑 <b>Token Updater Online</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        "Every morning, copy your fresh Upstox access token\n"
        "and send this command:\n\n"
        "<code>/upstox YOUR_NEW_TOKEN_HERE</code>\n\n"
        "Check all bots: /status\n"
        "━━━━━━━━━━━━━━━━━━━━━━")

    offset = 0
    while True:
        updates = get_updates(offset)
        for update in updates:
            offset = update["update_id"] + 1
            if "message" in update:
                try:
                    handle_message(update["message"])
                except Exception as exc:
                    log.error("Error handling message: %s", exc)
        if not updates:
            time.sleep(1)


if __name__ == "__main__":
    main()
