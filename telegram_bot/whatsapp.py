"""WhatsApp notification helper via Interakt API (freeform/session messages).

Converts Telegram HTML markup to WhatsApp-style formatting before sending.
Reads INTERAKT_API_KEY and WHATSAPP_RECIPIENTS from .env at import time.
"""

import os
import re
import logging
import requests
from dotenv import load_dotenv

load_dotenv()

log = logging.getLogger(__name__)

_API_KEY    = os.getenv("INTERAKT_API_KEY", "")
_RECIPIENTS = [r.strip() for r in os.getenv("WHATSAPP_RECIPIENTS", "").split(",") if r.strip()]


def _html_to_wa(text: str) -> str:
    """Convert Telegram HTML to WhatsApp plaintext with basic bold/italic."""
    text = re.sub(r"<b>(.*?)</b>",      r"*\1*",  text, flags=re.DOTALL)
    text = re.sub(r"<i>(.*?)</i>",      r"_\1_",  text, flags=re.DOTALL)
    text = re.sub(r"<code>(.*?)</code>", r"`\1`",  text, flags=re.DOTALL)
    text = re.sub(r"<[^>]+>", "", text)
    return (text.replace("&amp;", "&")
                .replace("&lt;",  "<")
                .replace("&gt;",  ">")
                .replace("&nbsp;", " "))


def wapp_send(text: str) -> None:
    if not _API_KEY or not _RECIPIENTS:
        return
    plain = _html_to_wa(text)
    for number in _RECIPIENTS:
        # Interakt expects the 10-digit local number; country code is separate
        phone = number[2:] if (number.startswith("91") and len(number) == 12) else number
        try:
            r = requests.post(
                "https://api.interakt.ai/v1/public/message/",
                headers={
                    "Authorization": f"Basic {_API_KEY}",
                    "Content-Type": "application/json",
                },
                json={
                    "countryCode": "91",
                    "phoneNumber": phone,
                    "callbackData": "signal",
                    "type": "Text",
                    "data": {"message": plain},
                },
                timeout=10,
            )
            if r.status_code not in (200, 201):
                log.warning("Interakt %s: HTTP %d %s", number, r.status_code, r.text[:120])
        except Exception as exc:
            log.warning("Interakt error %s: %s", number, exc)
