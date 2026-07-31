#!/usr/bin/env python3
"""
Market Calendar — Determines NSE trading days and holidays.
"""

from datetime import datetime, timedelta
from typing import List

class NSEMarketCalendar:
    """
    NSE market calendar for India.
    Known holidays and trading exceptions.
    """

    # NSE holidays 2026 (update as needed)
    HOLIDAYS_2026 = [
        "2026-01-26",  # Republic Day
        "2026-03-29",  # Holi
        "2026-03-30",  # Holi (holiday)
        "2026-04-02",  # Good Friday
        "2026-04-10",  # Eid ul-Fitr
        "2026-05-01",  # May Day
        "2026-05-15",  # Eid ul-Adha
        "2026-08-15",  # Independence Day
        "2026-08-27",  # Janmashtami
        "2026-09-30",  # Dussehra
        "2026-10-02",  # Gandhi Jayanti
        "2026-10-20",  # Diwali
        "2026-10-21",  # Diwali (holiday)
        "2026-11-16",  # Guru Nanak Jayanti
        "2026-12-25",  # Christmas
    ]

    def __init__(self):
        pass

    @staticmethod
    def is_trading_day(date: datetime = None) -> bool:
        """Check if a date is a trading day (Mon-Fri, not a holiday)."""
        if date is None:
            date = datetime.now()

        # Not a trading day if weekend
        if date.weekday() >= 5:  # 5=Saturday, 6=Sunday
            return False

        # Not a trading day if in holiday list
        date_str = date.strftime("%Y-%m-%d")
        if date_str in NSEMarketCalendar.HOLIDAYS_2026:
            return False

        return True

    @staticmethod
    def is_market_open(hour: int = None, minute: int = None) -> bool:
        """Check if market is currently open (9:15 AM - 3:30 PM IST)."""
        if hour is None or minute is None:
            now = datetime.now()
            hour = now.hour
            minute = now.minute

        market_open = (9, 15)
        market_close = (15, 30)

        time_tuple = (hour, minute)
        return market_open <= time_tuple <= market_close

    @staticmethod
    def next_trading_day(date: datetime = None) -> datetime:
        """Get the next trading day."""
        if date is None:
            date = datetime.now()

        date += timedelta(days=1)
        while not NSEMarketCalendar.is_trading_day(date):
            date += timedelta(days=1)

        return date

    @staticmethod
    def previous_trading_day(date: datetime = None) -> datetime:
        """Get the previous trading day."""
        if date is None:
            date = datetime.now()

        date -= timedelta(days=1)
        while not NSEMarketCalendar.is_trading_day(date):
            date -= timedelta(days=1)

        return date

    @staticmethod
    def trading_days_in_range(start: datetime, end: datetime) -> List[datetime]:
        """Get list of trading days between start and end dates."""
        days = []
        current = start
        while current <= end:
            if NSEMarketCalendar.is_trading_day(current):
                days.append(current)
            current += timedelta(days=1)
        return days


if __name__ == '__main__':
    # Test
    today = datetime.now()
    print(f"Today ({today.strftime('%Y-%m-%d')})")
    print(f"  Is trading day: {NSEMarketCalendar.is_trading_day(today)}")
    print(f"  Market open now: {NSEMarketCalendar.is_market_open()}")
    print(f"  Next trading day: {NSEMarketCalendar.next_trading_day(today).strftime('%Y-%m-%d')}")
