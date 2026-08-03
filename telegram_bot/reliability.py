"""Reliability primitives for signal-only market scanners."""
from __future__ import annotations

import hashlib
import json
import os
import tempfile
import fcntl
from dataclasses import asdict, dataclass, field
from datetime import datetime, time, timedelta
from pathlib import Path
from typing import Callable
from zoneinfo import ZoneInfo

IST = ZoneInfo("Asia/Kolkata")
MARKET_OPEN = time(9, 15)
MARKET_CLOSE = time(15, 30)


def ist_now() -> datetime:
    return datetime.now(IST)


def as_ist(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=IST)
    return value.astimezone(IST)


def is_market_session(value: datetime, holiday: Callable[[datetime], bool] | None = None) -> bool:
    value = as_ist(value)
    return value.weekday() < 5 and not (holiday and holiday(value)) and MARKET_OPEN <= value.time() <= MARKET_CLOSE


def next_scan_at(value: datetime, interval_seconds: int = 60) -> datetime:
    """Return an interval boundary anchored to 09:15 IST, never process start."""
    value = as_ist(value)
    market_open = value.replace(hour=9, minute=15, second=0, microsecond=0)
    if value < market_open:
        return market_open
    elapsed = max(0, int((value - market_open).total_seconds()))
    steps = elapsed // interval_seconds + 1
    return market_open + timedelta(seconds=steps * interval_seconds)


def candle_timestamp(raw: str | datetime) -> datetime:
    value = raw if isinstance(raw, datetime) else datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
    return as_ist(value)


def deterministic_signal_id(strategy: str, symbol: str, direction: str, candle: datetime) -> str:
    canonical = "|".join((strategy, symbol, direction.upper(), as_ist(candle).isoformat()))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:24]


def retry_call(operation: Callable[[], object], attempts: int = 3,
               retryable: Callable[[Exception], bool] | None = None) -> object:
    """Bounded retry helper; callers own network timeouts and delivery commits."""
    last_error = None
    for _ in range(attempts):
        try:
            return operation()
        except Exception as exc:
            last_error = exc
            if retryable is not None and not retryable(exc):
                raise
    assert last_error is not None
    raise last_error


def acquire_instance_lock(path: str | Path):
    """Acquire a non-blocking process lock; keep the returned handle open."""
    lock_path = Path(path)
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    handle = lock_path.open("a+", encoding="utf-8")
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        handle.close()
        raise RuntimeError(f"another bot instance owns {lock_path}")
    return handle


@dataclass
class ReliabilityState:
    trading_date: str | None = None
    delivered_ids: list[str] = field(default_factory=list)
    delivered_at: dict[str, str] = field(default_factory=dict)
    last_direction_by_setup: dict[str, str] = field(default_factory=dict)
    process_start: str | None = None
    first_data_fetch: str | None = None
    first_evaluation: str | None = None
    last_heartbeat: str | None = None
    last_successful_scan: str | None = None
    last_market_data_timestamp: str | None = None
    symbols_scanned: int = 0
    last_signal_time: str | None = None
    signals_today: int = 0
    current_error: str | None = None
    next_scan_time: str | None = None


class StateStore:
    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.state = self.load()

    def load(self) -> ReliabilityState:
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
            allowed = ReliabilityState.__dataclass_fields__
            return ReliabilityState(**{key: value for key, value in raw.items() if key in allowed})
        except FileNotFoundError:
            return ReliabilityState()
        except (OSError, ValueError, TypeError):
            return ReliabilityState(current_error="state_load_failed")

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix=self.path.name, dir=self.path.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(asdict(self.state), handle, sort_keys=True)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, self.path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)

    def roll_trading_day(self, now: datetime) -> None:
        date_key = as_ist(now).date().isoformat()
        if self.state.trading_date != date_key:
            self.state.trading_date = date_key
            self.state.signals_today = 0
            self.state.last_signal_time = None
            self.save()


@dataclass(frozen=True)
class AlertDecision:
    allowed: bool
    reason: str
    signal_id: str


class AlertPolicy:
    def __init__(self, store: StateStore, max_age_seconds: int = 180, cooldown_seconds: int = 1800,
                 max_alerts: int = 3, window_seconds: int = 900):
        self.store = store
        self.max_age_seconds = max_age_seconds
        self.cooldown_seconds = cooldown_seconds
        self.max_alerts = max_alerts
        self.window_seconds = window_seconds

    def evaluate(self, *, strategy: str, symbol: str, direction: str, confidence: str,
                 confirmations_pass: bool, candle: datetime, now: datetime, live_mode: bool = True) -> AlertDecision:
        now, candle = as_ist(now), as_ist(candle)
        signal_id = deterministic_signal_id(strategy, symbol, direction, candle)
        self.store.roll_trading_day(now)
        state = self.store.state
        if not live_mode:
            return AlertDecision(False, "replay_mode", signal_id)
        if not is_market_session(now):
            return AlertDecision(False, "outside_market_hours", signal_id)
        age = (now - candle).total_seconds()
        if age < -5 or age > self.max_age_seconds:
            return AlertDecision(False, "stale_or_historical", signal_id)
        if confidence == "LOW":
            return AlertDecision(False, "low_confidence_log_only", signal_id)
        if confidence == "MEDIUM" and not confirmations_pass:
            return AlertDecision(False, "medium_confirmations_failed", signal_id)
        if signal_id in state.delivered_ids:
            return AlertDecision(False, "duplicate", signal_id)
        setup_key = f"{strategy}|{symbol}|{as_ist(candle).isoformat()}"
        prior_direction = state.last_direction_by_setup.get(setup_key)
        if prior_direction and prior_direction != direction.upper():
            return AlertDecision(False, "contradictory_direction", signal_id)
        symbol_key = f"{strategy}|{symbol}"
        last_symbol_alert = state.delivered_at.get(symbol_key)
        if last_symbol_alert and (now - candle_timestamp(last_symbol_alert)).total_seconds() < self.cooldown_seconds:
            return AlertDecision(False, "symbol_cooldown", signal_id)
        recent = [candle_timestamp(ts) for key, ts in state.delivered_at.items() if key.startswith("signal|")]
        if sum((now - ts).total_seconds() <= self.window_seconds for ts in recent) >= self.max_alerts:
            return AlertDecision(False, "global_rate_limit", signal_id)
        return AlertDecision(True, "approved", signal_id)

    def mark_delivered(self, decision: AlertDecision, strategy: str, symbol: str, direction: str,
                       candle: datetime, delivered_at: datetime) -> None:
        if not decision.allowed:
            raise ValueError("cannot deliver a rejected alert")
        state = self.store.state
        stamp = as_ist(delivered_at).isoformat()
        state.delivered_ids = (state.delivered_ids + [decision.signal_id])[-5000:]
        state.delivered_at[f"signal|{decision.signal_id}"] = stamp
        state.delivered_at[f"{strategy}|{symbol}"] = stamp
        state.last_direction_by_setup[f"{strategy}|{symbol}|{as_ist(candle).isoformat()}"] = direction.upper()
        state.last_signal_time = stamp
        state.signals_today += 1
        self.store.save()
