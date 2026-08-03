# Proposed Signal Discipline Policy

This is implemented and tested on the review branch but is not production policy until Ajay approves and deploys it.

- HIGH: immediate alert after freshness, market-hours, uniqueness, cooldown, and rate-limit checks.
- MEDIUM: alert only for a fresh EMA crossover with RSI 52–63 and volume at least 1.2× its rolling average.
- LOW: structured log only; no Telegram.
- Maximum three Telegram trade alerts in any rolling 15-minute period.
- One unique direction per symbol, strategy, and candle; contradictory directions are rejected.
- Default per-symbol/strategy cooldown: 30 minutes.
- Maximum signal age: three minutes, configurable.
- Historical/backfill/replay candidates never reach Telegram.
- Signal ID: SHA-256 of strategy, symbol, direction, and timezone-aware candle timestamp, truncated to 24 hex characters.
- IDs and delivery timestamps persist atomically, so restart does not resend.
- Delivery state is committed only after Telegram confirms success.

Every delivered message retains direction, symbol, price, stop loss, target, confidence, timestamp, strategy rationale, and indicator reasons. Existing capital, stop-loss, target, and order rules were not changed.
