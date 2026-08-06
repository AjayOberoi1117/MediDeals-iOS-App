# Systemd Service Matrix

**Purpose**: Define systemd unit files for all 7 signal bots  
**Location**: `/etc/systemd/system/medideals-*.service`  
**Status**: Ready for DigitalOcean deployment  

---

## SERVICE OVERVIEW

| Bot | Service Name | Python File | Exec Start | Active Hours |
|-----|--------------|-------------|-----------|--------------|
| BTC Bot | `medideals-btc-bot` | `btc_bot.py` | 24/7 (all hours) | Any |
| Gold Bot | `medideals-gold-bot` | `gold_bot.py` | 24/7 (all hours) | Any |
| Signal Bot | `medideals-signal-bot` | `signal_bot.py` | 24/7 (all hours) | Any |
| Forex Scalper | `medideals-forex-scalper` | `forex_scalper.py` | 24/7 (all hours) | EURUSD/GBPUSD hours |
| India Scalper | `medideals-india-scalper` | `india_scalper.py` | 24/7 (exits if outside market) | 9:15 AM - 3:30 PM IST |
| Nifty Scalper | `medideals-nifty-scalper` | `nifty_scalper.py` | 24/7 (exits if outside market) | 9:15 AM - 3:15 PM IST |
| Options Scalper | `medideals-options-scalper` | `options_scalper.py` | 24/7 (exits if outside market) | 9:15 AM - 3:10 PM IST |

**Note**: All bots are stateless and include market-hour checks internally. Safe to run 24/7.

---

## SHARED CONFIGURATION

### Common Environment Variables (via EnvironmentFile)
```ini
# File: /etc/medideals/telegram.env
TELEGRAM_BOT_TOKEN=<value>
TELEGRAM_CHAT_ID=<value>
BOT_EXECUTION_MODE=dry_run  # or production
```

### Common Settings
- **User**: `medideals`
- **Group**: `medideals`
- **WorkingDirectory**: `/home/medideals/MediDeals-iOS-App/telegram_bot`
- **ExecStart**: `/home/medideals/venv_medideals/bin/python3 <bot>.py`
- **Type**: `simple`
- **Restart**: `on-failure`
- **RestartSec**: `5s`
- **StartLimitIntervalSec**: `300s` (max 5 restarts per 5 minutes)
- **StandardOutput**: `journal`
- **StandardError**: `journal`

---

## INDIVIDUAL SERVICE FILES

### 1. medideals-btc-bot.service

```ini
[Unit]
Description=MediDeals BTC Bot - Crypto Trading Signal
Documentation=https://github.com/AjayOberoi1117/MediDeals-iOS-App
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=medideals
Group=medideals
WorkingDirectory=/home/medideals/MediDeals-iOS-App/telegram_bot
EnvironmentFile=/etc/medideals/telegram.env
ExecStart=/home/medideals/venv_medideals/bin/python3 btc_bot.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=medideals-btc-bot
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
```

---

### 2. medideals-gold-bot.service

```ini
[Unit]
Description=MediDeals Gold Bot - XAUUSD Trading Signal
Documentation=https://github.com/AjayOberoi1117/MediDeals-iOS-App
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=medideals
Group=medideals
WorkingDirectory=/home/medideals/MediDeals-iOS-App/telegram_bot
EnvironmentFile=/etc/medideals/telegram.env
ExecStart=/home/medideals/venv_medideals/bin/python3 gold_bot.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=medideals-gold-bot
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
```

---

### 3. medideals-signal-bot.service

```ini
[Unit]
Description=MediDeals Signal Bot - Forex Trading Signal
Documentation=https://github.com/AjayOberoi1117/MediDeals-iOS-App
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=medideals
Group=medideals
WorkingDirectory=/home/medideals/MediDeals-iOS-App/telegram_bot
EnvironmentFile=/etc/medideals/telegram.env
ExecStart=/home/medideals/venv_medideals/bin/python3 signal_bot.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=medideals-signal-bot
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
```

---

### 4. medideals-forex-scalper.service

```ini
[Unit]
Description=MediDeals Forex Scalper - 15min EURUSD/GBPUSD Signals
Documentation=https://github.com/AjayOberoi1117/MediDeals-iOS-App
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=medideals
Group=medideals
WorkingDirectory=/home/medideals/MediDeals-iOS-App/telegram_bot
EnvironmentFile=/etc/medideals/telegram.env
ExecStart=/home/medideals/venv_medideals/bin/python3 forex_scalper.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=medideals-forex-scalper
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
```

---

### 5. medideals-india-scalper.service

```ini
[Unit]
Description=MediDeals India Scalper - Nifty 50 Stock Scalper (9:15AM-3:30PM IST)
Documentation=https://github.com/AjayOberoi1117/MediDeals-iOS-App
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=medideals
Group=medideals
WorkingDirectory=/home/medideals/MediDeals-iOS-App/telegram_bot
EnvironmentFile=/etc/medideals/telegram.env
ExecStart=/home/medideals/venv_medideals/bin/python3 india_scalper.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=medideals-india-scalper
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
```

---

### 6. medideals-nifty-scalper.service

```ini
[Unit]
Description=MediDeals Nifty Scalper - Nifty Intraday Scalper (9:15AM-3:15PM IST)
Documentation=https://github.com/AjayOberoi1117/MediDeals-iOS-App
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=medideals
Group=medideals
WorkingDirectory=/home/medideals/MediDeals-iOS-App/telegram_bot
EnvironmentFile=/etc/medideals/telegram.env
ExecStart=/home/medideals/venv_medideals/bin/python3 nifty_scalper.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=medideals-nifty-scalper
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
```

---

### 7. medideals-options-scalper.service

```ini
[Unit]
Description=MediDeals Options Scalper - Nifty/BankNifty ATM Option Buying Signals
Documentation=https://github.com/AjayOberoi1117/MediDeals-iOS-App
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=medideals
Group=medideals
WorkingDirectory=/home/medideals/MediDeals-iOS-App/telegram_bot
EnvironmentFile=/etc/medideals/telegram.env
ExecStart=/home/medideals/venv_medideals/bin/python3 options_scalper.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=medideals-options-scalper
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
```

---

## INSTALLATION PROCEDURE

### Step 1: Create Service Files on DigitalOcean

```bash
# As root user
sudo tee /etc/systemd/system/medideals-btc-bot.service > /dev/null <<'EOF'
[Unit]
Description=MediDeals BTC Bot - Crypto Trading Signal
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=medideals
Group=medideals
WorkingDirectory=/home/medideals/MediDeals-iOS-App/telegram_bot
EnvironmentFile=/etc/medideals/telegram.env
ExecStart=/home/medideals/venv_medideals/bin/python3 btc_bot.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=medideals-btc-bot
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF

# Repeat for gold_bot, signal_bot, forex_scalper, india_scalper, nifty_scalper, options_scalper
```

### Step 2: Reload Systemd Daemon

```bash
sudo systemctl daemon-reload
```

### Step 3: Enable Services (Auto-start on boot)

```bash
sudo systemctl enable medideals-btc-bot.service
sudo systemctl enable medideals-gold-bot.service
sudo systemctl enable medideals-signal-bot.service
sudo systemctl enable medideals-forex-scalper.service
sudo systemctl enable medideals-india-scalper.service
sudo systemctl enable medideals-nifty-scalper.service
sudo systemctl enable medideals-options-scalper.service

# Verify
sudo systemctl list-unit-files | grep medideals
```

### Step 4: Start Services

```bash
# Start one at a time (with 2-second delays)
sudo systemctl start medideals-btc-bot.service && sleep 2
sudo systemctl start medideals-gold-bot.service && sleep 2
sudo systemctl start medideals-signal-bot.service && sleep 2
sudo systemctl start medideals-forex-scalper.service && sleep 2
sudo systemctl start medideals-india-scalper.service && sleep 2
sudo systemctl start medideals-nifty-scalper.service && sleep 2
sudo systemctl start medideals-options-scalper.service

# Or start all at once
sudo systemctl start medideals-*.service
```

---

## OPERATIONAL COMMANDS

### Check Status of All Bots

```bash
# View all services
sudo systemctl status medideals-*.service

# Or individually
sudo systemctl status medideals-btc-bot.service
sudo systemctl status medideals-gold-bot.service
# ... etc
```

### View Logs

```bash
# Real-time logs (all bots)
sudo journalctl -u 'medideals-*.service' -f

# Logs for specific bot
sudo journalctl -u medideals-btc-bot.service -f

# Last 50 lines
sudo journalctl -u medideals-btc-bot.service -n 50

# Time range (last 24 hours)
sudo journalctl -u medideals-btc-bot.service --since "24 hours ago"
```

### Control Individual Bots

```bash
# Stop a bot
sudo systemctl stop medideals-btc-bot.service

# Start a bot
sudo systemctl start medideals-btc-bot.service

# Restart a bot
sudo systemctl restart medideals-btc-bot.service

# Disable auto-start on boot
sudo systemctl disable medideals-btc-bot.service

# Enable auto-start on boot
sudo systemctl enable medideals-btc-bot.service
```

### Monitor Process Resource Usage

```bash
# Install htop if not present
sudo apt-get install -y htop

# Monitor bot processes
htop -p $(pgrep -f "btc_bot|gold_bot|signal_bot" | tr '\n' ',')

# Or use ps
ps aux | grep -E "(btc_bot|gold_bot|signal_bot)" | grep -v grep
```

### Check Restart History

```bash
# View restart count and failure reasons
sudo journalctl -u medideals-btc-bot.service | grep -E "Restart|Exited"

# Monitor for crashes
watch -n 2 'sudo systemctl status medideals-*.service | grep -E "Active|Restart"'
```

---

## RESTART BEHAVIOR

### Scenario 1: Bot Crashes (Exit Code != 0)

```
Time  Event
0s    Bot running normally
60s   Bot crashes (e.g., API timeout, OOM)
60s   systemd detects crash
65s   systemd waits RestartSec=5s
65s   systemd restarts bot
65s   Bot running again
```

### Scenario 2: Max Restarts Exceeded

```
Condition: More than 5 restarts in 300 seconds

Time  Event
0s    1st restart attempt (crash)
5s    2nd restart attempt (crash)
10s   3rd restart attempt (crash)
15s   4th restart attempt (crash)
20s   5th restart attempt (crash)
20s   6th attempt would violate StartLimitBurst=5
20s   Service enters "failed" state
300s  Counter resets, can attempt again
```

### Manual Override

```bash
# Reset restart counter and try again
sudo systemctl reset-failed medideals-btc-bot.service
sudo systemctl start medideals-btc-bot.service
```

---

## DEPENDENCY & ORDERING

### Boot Sequence

```
1. Network comes online (After=network-online.target)
2. systemd signals to start medideals-*.service
3. All services start in parallel (no ordering specified)
4. Each bot self-checks market hours and exits if appropriate
5. Services run indefinitely, auto-restart on failure
```

### Market Hours Self-Check

Each bot includes checks like:

```python
# India Scalper - exits if outside NSE hours
def in_market_hours():
    now = datetime.now(IST)
    if now.weekday() >= 5:  # Sat/Sun
        return False
    if is_nse_holiday(now):
        return False
    return MARKET_OPEN <= (now.hour, now.minute) <= MARKET_CLOSE

# Main loop
while True:
    if in_market_hours():
        scan_and_generate_signals()
    else:
        log.debug("Waiting for market hours...")
    time.sleep(SCAN_INTERVAL)
```

So bots run 24/7 but only generate signals during active market hours.

---

## FAILURE SCENARIOS & RECOVERY

| Scenario | Systemd Behavior | Recovery |
|----------|------------------|----------|
| Bot crashes | Auto-restart after 5s | Continue 24/7 |
| Network down | Bot hangs on API call | Timeout, then crash/restart cycle |
| Droplet reboots | systemd starts all services | Auto-recovery, no manual action |
| Memory leak | Bot grows slowly, eventual OOM | Crash and restart (clears memory) |
| Credential expiry | Bot fails auth, logs error | Operator updates `/etc/medideals/telegram.env` and restarts |
| Max restarts exceeded | Service enters "failed" state | Operator runs `systemctl reset-failed` + `systemctl start` |

---

## MULTI-BOT HEALTH CHECK

### Monitoring Script (Optional)

```bash
#!/bin/bash
# /home/medideals/health_check.sh

BOTS=("btc-bot" "gold-bot" "signal-bot" "forex-scalper" "india-scalper" "nifty-scalper" "options-scalper")
LOG_FILE="/var/log/medideals/health.log"

{
  echo "[$(date)] Health Check Started"
  
  for bot in "${BOTS[@]}"; do
    status=$(sudo systemctl is-active medideals-${bot}.service 2>/dev/null || echo "unknown")
    if [ "$status" = "active" ]; then
      echo "✓ medideals-${bot}.service: $status"
    else
      echo "✗ medideals-${bot}.service: $status - RESTARTING"
      sudo systemctl restart medideals-${bot}.service
    fi
  done
  
  echo "[$(date)] Health Check Completed"
} >> $LOG_FILE

# Install as cron job (run every 5 minutes)
# crontab -e
# */5 * * * * /home/medideals/health_check.sh
```

---

## COMPLIANCE CHECKLIST

- [x] All 7 bots have individual systemd service files
- [x] Services use medideals (non-root) user
- [x] Auto-restart on-failure configured
- [x] Rate limiting configured (5 restarts per 5 minutes)
- [x] Logging to journalctl configured
- [x] Environment variables via EnvironmentFile
- [x] Documentation links included
- [x] Market-hour checks implemented in each bot
- [x] Telegram credentials secured (not in service files)
- [x] Order execution guards implemented (is_dry_run_mode)

---

## NEXT STEPS

1. Create service files on DigitalOcean droplet
2. Run `sudo systemctl daemon-reload`
3. Enable services: `sudo systemctl enable medideals-*.service`
4. Start services in sequence with 2-second delays
5. Monitor logs for 5 minutes to verify stability
6. Set up health check cron job (optional but recommended)
7. Document any customizations for future reference
