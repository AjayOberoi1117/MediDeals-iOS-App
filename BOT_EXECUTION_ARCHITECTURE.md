# Bot Execution Architecture

## Confirmed current inventory

| Bot | Entry point | Local manager | Purpose/status |
|---|---|---|---|
| NSE Nifty 100 Scanner | `telegram_bot/scanner_bot.py` | launchd and `start_bots.sh` | Generated the 19 alerts on 3 August |
| India Nifty 50 Scalper | `telegram_bot/india_scalper.py` | launchd | Active; Telegram and broker authentication failing |
| Nifty Scalper | `telegram_bot/nifty_scalper.py` | shell/VPS launcher | Separate index strategy |
| Forex/Gold/Crypto bots | corresponding files in `telegram_bot` | shell launcher; some launchd | Out of Indian incident scope |

Signal engine and confidence scoring currently live inside each script. Scanner delivery is `send_telegram`/`notify`; state is `.scanner_state.json`. The production Mac manager is launchd. The repository also contains VPS cron (`setup_vps.sh`), shell launchers, watchdog, and systemd units, creating duplicate-deployment risk.

## Correct execution model

One owner process per bot instance:

`launchd KeepAlive → process starts → records build/timezone/start → waits until 09:15 IST → continuous scan cycles → policy/idempotency gate → Telegram → atomic delivery commit → heartbeat/health record → after-market wait`

Process liveness is independent from strategy readiness. The first completed candle may delay a strategy decision, but must not delay process startup or heartbeat. The scanner records process start, first data timestamp, scan completion, last market-data timestamp, last signal, errors, and next scan. Health is false/stale if heartbeat or market data stops advancing.

Use exactly one process manager. On this Mac, launchd is appropriate if the machine remains awake, logged in, network-connected, and powered. Remove scanner startup from `start_bots.sh` when the launchd configuration is deployed, or vice versa. Do not combine both. A laptop that sleeps is not suitable for guaranteed session coverage; a non-scale-to-zero always-on worker would be the infrastructure alternative, subject to Ajay's explicit cost/deployment approval.

The repository plist change is not installed. Production launchd remains untouched.
