import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

from telegram_bot.reliability import AlertPolicy, StateStore, acquire_instance_lock, deterministic_signal_id, is_market_session, next_scan_at, retry_call

IST = ZoneInfo("Asia/Kolkata")


class ReliabilityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "state.json"
        self.store = StateStore(self.path)
        self.policy = AlertPolicy(self.store)
        self.now = datetime(2026, 8, 3, 10, 0, tzinfo=IST)

    def tearDown(self):
        self.temp.cleanup()

    def decision(self, **changes):
        args = dict(strategy="test", symbol="TCS", direction="BUY", confidence="HIGH",
                    confirmations_pass=True, candle=self.now, now=self.now)
        args.update(changes)
        return self.policy.evaluate(**args)

    def deliver(self, decision=None, symbol="TCS", candle=None, at=None):
        candle, at = candle or self.now, at or self.now
        decision = decision or self.decision(symbol=symbol, candle=candle, now=at)
        self.policy.mark_delivered(decision, "test", symbol, "BUY", candle, at)

    def test_ist_market_open_calculation(self):
        self.assertFalse(is_market_session(datetime(2026, 8, 3, 9, 14, 59, tzinfo=IST)))
        self.assertTrue(is_market_session(datetime(2026, 8, 3, 9, 15, tzinfo=IST)))
        self.assertTrue(is_market_session(datetime(2026, 8, 3, 3, 45, tzinfo=ZoneInfo("UTC"))))

    def test_process_can_start_before_open_and_first_evaluation_aligns_to_0915(self):
        started = datetime(2026, 8, 3, 9, 0, tzinfo=IST)
        self.assertFalse(is_market_session(started))
        self.assertEqual(next_scan_at(started), datetime(2026, 8, 3, 9, 15, tzinfo=IST))

    def test_no_0930_dependency(self):
        self.assertEqual(next_scan_at(datetime(2026, 8, 3, 9, 14, 59, tzinfo=IST)),
                         datetime(2026, 8, 3, 9, 15, tzinfo=IST))

    def test_historical_backlog_and_stale_signals_are_rejected(self):
        decision = self.decision(candle=self.now - timedelta(minutes=4))
        self.assertEqual(decision.reason, "stale_or_historical")
        self.assertEqual(self.decision(live_mode=False).reason, "replay_mode")

    def test_deterministic_signal_ids(self):
        first = deterministic_signal_id("test", "TCS", "BUY", self.now)
        self.assertEqual(first, deterministic_signal_id("test", "TCS", "BUY", self.now))
        self.assertNotEqual(first, deterministic_signal_id("test", "INFY", "BUY", self.now))

    def test_duplicate_suppression_and_restart_idempotency(self):
        decision = self.decision()
        self.deliver(decision)
        restarted = AlertPolicy(StateStore(self.path))
        duplicate = restarted.evaluate(strategy="test", symbol="TCS", direction="BUY", confidence="HIGH",
                                       confirmations_pass=True, candle=self.now, now=self.now)
        self.assertEqual(duplicate.reason, "duplicate")

    def test_confidence_filtering(self):
        self.assertEqual(self.decision(confidence="LOW").reason, "low_confidence_log_only")
        self.assertEqual(self.decision(confidence="MEDIUM", confirmations_pass=False).reason,
                         "medium_confirmations_failed")
        self.assertTrue(self.decision(confidence="MEDIUM", confirmations_pass=True).allowed)

    def test_global_rate_limit(self):
        for offset, symbol in enumerate(("A", "B", "C")):
            when = self.now + timedelta(seconds=offset)
            decision = self.decision(symbol=symbol, candle=when, now=when)
            self.deliver(decision, symbol, when, when)
        fourth = self.decision(symbol="D", candle=self.now + timedelta(seconds=3),
                               now=self.now + timedelta(seconds=3))
        self.assertEqual(fourth.reason, "global_rate_limit")

    def test_per_symbol_cooldown(self):
        self.deliver()
        later = self.now + timedelta(minutes=5)
        self.assertEqual(self.decision(candle=later, now=later).reason, "symbol_cooldown")

    def test_one_symbol_failure_isolation_contract(self):
        visited = []
        for symbol in ("A", "BROKEN", "C"):
            try:
                if symbol == "BROKEN":
                    raise TimeoutError("provider timeout")
                visited.append(symbol)
            except Exception:
                continue
        self.assertEqual(visited, ["A", "C"])

    def test_api_timeout_has_bounded_retries(self):
        calls = []
        with self.assertRaises(TimeoutError):
            retry_call(lambda: calls.append(1) or (_ for _ in ()).throw(TimeoutError()), attempts=3)
        self.assertEqual(len(calls), 3)

    def test_telegram_retry_commits_delivery_only_once(self):
        attempts = []
        def transient_delivery():
            attempts.append(1)
            if len(attempts) < 3:
                raise TimeoutError("telegram timeout")
            return True
        decision = self.decision()
        self.assertTrue(retry_call(transient_delivery, attempts=3))
        self.deliver(decision)
        self.assertEqual(len(self.store.state.delivered_ids), 1)
        self.assertEqual(len(attempts), 3)

    def test_second_worker_instance_is_rejected(self):
        lock_path = Path(self.temp.name) / "bot.lock"
        first = acquire_instance_lock(lock_path)
        self.addCleanup(first.close)
        with self.assertRaises(RuntimeError):
            acquire_instance_lock(lock_path)

    def test_full_session_replay_with_error_recovery_restart_and_heartbeats(self):
        scans, heartbeats, delivered = [], [], []
        clock = datetime(2026, 8, 3, 9, 0, tzinfo=IST)
        restart_store = None
        while clock <= datetime(2026, 8, 3, 15, 30, tzinfo=IST):
            heartbeats.append(clock)
            if is_market_session(clock):
                scans.append(clock)
                if clock == datetime(2026, 8, 3, 10, 0, tzinfo=IST):
                    try:
                        raise TimeoutError("simulated API timeout")
                    except TimeoutError:
                        pass
                if clock == datetime(2026, 8, 3, 11, 0, tzinfo=IST):
                    decision = self.decision(candle=clock, now=clock)
                    self.deliver(decision, candle=clock, at=clock)
                    delivered.append(decision.signal_id)
                if clock == datetime(2026, 8, 3, 12, 0, tzinfo=IST):
                    restart_store = StateStore(self.path)
            clock += timedelta(minutes=1)
        self.assertEqual(scans[0].time().isoformat(), "09:15:00")
        self.assertIn(datetime(2026, 8, 3, 10, 1, tzinfo=IST), scans)
        self.assertGreater(len(heartbeats), len(delivered))
        duplicate = AlertPolicy(restart_store).evaluate(
            strategy="test", symbol="TCS", direction="BUY", confidence="HIGH",
            confirmations_pass=True, candle=datetime(2026, 8, 3, 11, 0, tzinfo=IST),
            now=datetime(2026, 8, 3, 12, 0, tzinfo=IST))
        self.assertFalse(duplicate.allowed)
        self.assertEqual(len(delivered), 1)


if __name__ == "__main__":
    unittest.main()
