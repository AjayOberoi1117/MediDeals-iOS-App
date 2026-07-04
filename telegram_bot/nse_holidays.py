"""
NSE trading holidays.

Dates from the NSE "Trading Holidays" circular. Fixed-date holidays
(Republic Day, Maharashtra Day, Independence Day, Gandhi Jayanti,
Christmas) are exact; lunar-calendar holidays are best-effort and should
be verified against the official list each January:
https://www.nseindia.com/resources/exchange-communication-holidays

Weekend-falling holidays are included harmlessly (weekday check already
skips them).
"""

NSE_HOLIDAYS = {
    # 2026
    "2026-01-26",  # Republic Day
    "2026-03-04",  # Holi
    "2026-03-21",  # Id-ul-Fitr (Ramzan Eid)
    "2026-03-26",  # Ram Navami
    "2026-04-03",  # Good Friday
    "2026-04-14",  # Dr. Ambedkar Jayanti
    "2026-05-01",  # Maharashtra Day
    "2026-05-27",  # Bakri Id
    "2026-06-26",  # Muharram
    "2026-08-15",  # Independence Day
    "2026-09-14",  # Ganesh Chaturthi
    "2026-10-02",  # Mahatma Gandhi Jayanti
    "2026-10-20",  # Dussehra
    "2026-11-09",  # Diwali Balipratipada
    "2026-11-24",  # Guru Nanak Jayanti
    "2026-12-25",  # Christmas
}


def is_nse_holiday(dt) -> bool:
    """True if the given date/datetime falls on an NSE trading holiday."""
    return dt.strftime("%Y-%m-%d") in NSE_HOLIDAYS
