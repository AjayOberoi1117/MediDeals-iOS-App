"""Email notification helper via Gmail SMTP."""

import os
import smtplib
import logging
from email.mime.text import MIMEText
from dotenv import load_dotenv

load_dotenv()

log = logging.getLogger(__name__)

_FROM    = os.getenv("EMAIL_FROM", "")
_PASS    = os.getenv("EMAIL_APP_PASSWORD", "")
_TO      = os.getenv("EMAIL_TO", "")


def email_send(subject: str, body: str) -> None:
    if not _FROM or not _PASS or not _TO:
        return
    try:
        msg = MIMEText(body, "plain")
        msg["Subject"] = subject
        msg["From"]    = _FROM
        msg["To"]      = _TO
        with smtplib.SMTP("smtp.gmail.com", 587) as s:
            s.starttls()
            s.login(_FROM, _PASS)
            s.sendmail(_FROM, [_TO], msg.as_string())
        log.info("Email sent: %s", subject)
    except Exception as exc:
        log.warning("Email error: %s", exc)
