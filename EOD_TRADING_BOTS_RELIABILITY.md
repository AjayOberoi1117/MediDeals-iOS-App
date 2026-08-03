# End-of-Day Trading Bots Reliability

STATUS: Code and deterministic replay complete on isolated review branch; not deployed.

CANONICAL REPOSITORY: `/Users/ajayoberoi/MediDeals-iOS-App` (`ajayoberoi1117/medideals-ios-app`).

ACTIVE BOT OR BOTS: Scanner Bot and India Scalper confirmed active under launchd; shell-launched Scanner also evidenced by separate live log/state path.

PRODUCTION ENTRY POINT: `telegram_bot/scanner_bot.py` generated today's alerts.

CURRENT EXECUTION PLATFORM: macOS launchd plus overlapping shell/VPS-style launcher configuration.

ROOT CAUSE — 9:30 START: Fixed 30-minute sleeps anchored to 09:00 process start; second instance had a different phase. Process was alive before open, but evaluation was not aligned to 09:15.

ROOT CAUSE — STARTUP SIGNAL FLOOD: Existing EMA trend was treated as a fresh event across 100 symbols; MEDIUM threshold enabled; per-scan cap reverted; no rolling limit, freshness gate, candle ID, or durable delivery idempotency. Exactly 19 MEDIUM alerts are in the 09:30 log/state.

ROOT CAUSE — POST-START SILENCE: Bots remained alive and scanned later. Initial daily symbol suppression plus no new candidates yielded zero alerts; absence of heartbeat made this appear dead.

FILES CHANGED: `telegram_bot/scanner_bot.py`, `telegram_bot/reliability.py`, `telegram_bot/__init__.py`, `telegram_bot/com.medideals.scanner-bot.plist`, `telegram_bot/tests/test_reliability.py`, and five incident/reliability reports.

SCHEDULER CHANGES: Asia/Kolkata-aware session clock; scan boundaries anchored at 09:15; launchd review plist uses RunAtLoad/KeepAlive; process and strategy timing separated.

SIGNAL DISCIPLINE CHANGES: Fresh crossover requirement; HIGH immediate; confirmed MEDIUM only; LOW log-only; stale/backfill rejection; maximum three alerts/15 minutes.

DEDUPLICATION CHANGES: Deterministic setup IDs, atomic persisted delivery ledger, restart idempotency, per-symbol/strategy/candle isolation, contradictory-direction rejection, and a single-instance process lock.

HEARTBEAT AND HEALTH CHECK: Structured lifecycle/scan/heartbeat logging and `.scanner_health.json` fields for start, heartbeat, scan, data, symbols, signals, errors, and next scan.

ERROR-RECOVERY CHANGES: Request timeouts retained; Telegram bounded retry; symbol failure isolation; loop-level exception state and bounded retry; no silent top-level failures.

UNIT TEST RESULTS: 14/14 passed; compile checks passed.

FULL-SESSION REPLAY RESULT: PASS, 09:00–15:30 IST including error, recovery, restart, quiet periods, and close.

SIGNALS GENERATED IN REPLAY: 1.

DUPLICATES SUPPRESSED: 1 restart duplicate in replay; no duplicate delivery.

BLOCKERS: Production currently runs old code. Exact remote/VPS process inventory cannot be proven from local files alone. Installed launchd plist and shell launch path must be reconciled before deployment.

INFRASTRUCTURE DECISIONS REQUIRED FROM AJAY: Choose one manager (recommended: launchd on an always-awake Mac, otherwise an approved always-on worker). Approve any paid always-on infrastructure separately.

TRADING-POLICY DECISIONS REQUIRED FROM AJAY: Approve or amend the proposed HIGH/MEDIUM/LOW policy, three-per-15-minute cap, 30-minute cooldown, and three-minute maximum age.

BRANCH: `fix/trading-bot-reliability`.

COMMIT: Not committed.

DRAFT PR: Not opened.

NO-LIVE-TRADING CONFIRMATION: No broker call, order, real-fund action, or safety-rule change was performed.

NO-DEPLOYMENT CONFIRMATION: No process reload, launchd install, VPS update, push, merge, or deployment was performed.

TOMORROW RECOMMENDATION: After policy approval, deploy during a controlled pre-open window in signal-only mode, disable the duplicate scanner launch path, verify 08:55–09:15 heartbeat/data freshness, and observe the first two scan cycles before enabling notifications.
