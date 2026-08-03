# Full-Session Replay Report

## Test window

Deterministic clock replay: Monday 3 August 2026, 09:00–15:30 Asia/Kolkata, at one-minute scan/heartbeat steps. It covers pre-open, 09:15 open, quiet periods, an API timeout at 10:00, recovery at 10:01, a valid signal at 11:00, restart/state reload at 12:00, duplicate rejection, continued scans, and the 15:30 boundary.

## Result

- Process represented alive at 09:00: PASS
- First eligible evaluation at 09:15: PASS
- No 09:30 dependency: PASS
- Historical/replay delivery blocked: PASS
- Zero-signal periods retain heartbeat: PASS
- API failure does not stop later scans: PASS
- Restart preserves delivered ID: PASS
- Duplicate Telegram delivery: 0
- Replay signals generated: 1
- Replay alerts delivered: 1
- Full-session continuation through 15:30: PASS

Command: `/opt/homebrew/bin/python3 -m unittest discover -s telegram_bot/tests -v`

Result: 14 tests run, all passed. Python compile checks for scanner, reliability layer, and tests also passed. No network, Telegram, broker, order, or production process was invoked by replay.
