# Trading Bots Incident Root Cause — 3 August 2026

## Scope and source of truth

The canonical repository is `https://github.com/ajayoberoi1117/medideals-ios-app.git`, locally `/Users/ajayoberoi/MediDeals-iOS-App`. The active Indian alert producer was `telegram_bot/scanner_bot.py`. `india_scalper.py` was also running, but its Telegram credential returned HTTP 401 and its Upstox order token was invalid. No live order or deployment was performed during this work.

Other discovered copies were rejected as sources of truth: `/Users/ajayoberoi/trading-bot` is an unversioned three-symbol prototype; both `tradinggold_bot` directories are XAUUSD-only; `justice-desk-rc2-release/app/forex_order_block_bot` is an inactive MT5 forex scaffold.

## 09:30 start

The process was actually alive at 09:00 and logged waits at 09:00. Its loop then slept a fixed 30 minutes (`SCAN_INTERVAL_MIN = 30`), so the first eligible check occurred at 09:30:16 rather than 09:15. A second launchd-managed copy, whose process phase began at 00:44, checked at 09:14 (closed) and then 09:44. The scheduler was anchored to process start instead of the 09:15 market boundary. This is not a 15-minute-candle requirement: the active scanner uses one-minute candles first.

The repository launchd calendar also used weekday values 1–5 (Sunday–Thursday on macOS), omitting Friday. `KeepAlive` masked this whenever the process survived. The proposed plist uses `RunAtLoad` plus `KeepAlive`; strategy evaluation remains separately gated by Asia/Kolkata market state.

## Startup flood

At 09:30:16, `telegram_bot/logs/scanner.log` records exactly 19 alerts, matching `.scanner_state.json`. All 19 were MEDIUM. The causes were cumulative:

1. Commit `55f4546` lowered the Telegram threshold from HIGH-only to MEDIUM+.
2. Commit `0617053` removed the five-per-scan cap and explicitly restored sending all MEDIUM+ candidates.
3. `check_signal` treated every symbol already above EMA9/EMA21 with RSI 45–68 as a new signal; it did not require a crossover on the alert candle.
4. There was no global rolling rate limit, deterministic signal ID, candle-level key, maximum signal age, or delivery idempotency.
5. Both `start_bots.sh` and launchd could run the same scanner. They shared a weak daily JSON state without locking or atomic writes.

The fix requires a fresh EMA crossover, constrains MEDIUM alerts to mandatory RSI and volume confirmation, rejects stale/backfill candidates, allows at most three alerts per rolling 15 minutes, applies per-symbol/strategy cooldown, and persists deterministic IDs atomically.

## Post-start silence

The scanner did not exit. Logs prove later scans at 10:03/10:34 and 09:44/10:15/10:46 from the two execution paths. They emitted zero because the initial scan had marked 19 symbols alerted for the whole day and no remaining candidate qualified. There was no heartbeat or health record, so healthy zero-signal scanning appeared identical to a stopped bot. Per-symbol exceptions were also reduced to unstructured prints or swallowed exceptions.

## Additional operational findings

- `india_scalper.py` attempted broker orders, but Upstox rejected them as invalid-token requests. This work did not execute or alter order code.
- India Scalper Telegram sends returned 401 Unauthorized, while email sends from Scanner returned Gmail 535 BadCredentials.
- A long sequential 100-symbol scan means scan completion itself may take about 31 minutes. Heartbeats are now persisted during the scan, not only between scans.
- The checked-in scanner contains credential defaults. Rotation/removal requires a separately approved credential-security change; no credential was changed here.
