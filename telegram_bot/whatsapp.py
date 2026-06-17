"""WhatsApp notification helper via Meta WhatsApp Cloud API.

Converts Telegram HTML markup to WhatsApp-style formatting before sending.
Reads META_WA_TOKEN and WHATSAPP_RECIPIENTS from .env at import time.
"""

import os
import re
import logging
import requests
from dotenv import load_dotenv

load_dotenv()

log = logging.getLogger(__name__)

_WA_TOKEN   = os.getenv("META_WA_TOKEN", "")
_PHONE_ID   = os.getenv("META_WA_PHONE_ID", "1181643655024251")
_RECIPIENTS = [r.strip() for r in os.getenv("WHATSAPP_RECIPIENTS", "").split(",") if r.strip()]
_API_URL    = f"https://graph.facebook.com/v25.0/{_PHONE_ID}/messages"


def _html_to_wa(text: str) -> str:
    """Convert Telegram HTML to WhatsApp plaintext with basic bold/italic."""
    text = re.sub(r"<b>(.*?)</b>",       r"*\1*", text, flags=re.DOTALL)
    text = re.sub(r"<i>(.*?)</i>",       r"_\1_", text, flags=re.DOTALL)
    text = re.sub(r"<code>(.*?)</code>", r"`\1`",  text, flags=re.DOTALL)
    text = re.sub(r"<[^>]+>", "", text)
    return (text.replace("&amp;", "&")
                .replace("&lt;",  "<")
                .replace("&gt;",  ">")
                .replace("&nbsp;", " "))


def wapp_send(text: str) -> None:
    if not _WA_TOKEN or not _RECIPIENTS:
        return
    plain = _html_to_wa(text)
    for number in _RECIPIENTS:
        try:
            r = requests.post(
                _API_URL,
                headers={
                    "Authorization": f"Bearer {_WA_TOKEN}",
                    "Content-Type": "application/json",
                },
                json={
                    "messaging_product": "whatsapp",
                    "to": number,
                    "type": "text",
                    "text": {"body": plain},
                },
                timeout=10,
            )
            if r.status_code not in (200, 201):
                log.warning("WhatsApp %s: HTTP %d %s", number, r.status_code, r.text[:120])
        except Exception as exc:
            log.warning("WhatsApp error %s: %s", number, exc)
