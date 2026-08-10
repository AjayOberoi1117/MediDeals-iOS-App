# MediDeals DigitalOcean Deployment

Complete automated deployment of trading bot suite to DigitalOcean.

## Quick Start (One Command)

```bash
# 1. SSH into DigitalOcean droplet
ssh root@<droplet-ip>

# 2. Clone repository and configure credentials
git clone -b claude/bots-trade-signals-debug-wjevgt \
    https://github.com/AjayOberoi1117/MediDeals-iOS-App.git
cd MediDeals-iOS-App

# 3. Collect credentials from secure vault and create config
sudo bash credentials-prompt.sh

# 4. Deploy (10 phases, ~30 minutes)
sudo bash deploy.sh

# 5. STOP HERE — VNC login required (one-time only)
# Follow instructions in terminal for MT5 Vantage DEMO login via VNC
# (This is done ONCE; MT5 auto-reconnects thereafter)

# 6. After VNC login completes, deployment resumes automatically
# Final status: "TRADING SYSTEM LIVE ON DIGITALOCEAN"
```

## Prerequisites

**DigitalOcean Droplet:**
- Ubuntu 22.04 LTS
- 2 vCPU, 2 GB RAM, 60 GB SSD
- ~$12/month

**Credentials (from secure vault):**
```
TELEGRAM_BOT_TOKEN          (Telegram bot API key)
TELEGRAM_CHAT_ID            (destination: 7093601171 for @Equitytrading_bot)
MT5_LOGIN                   (Vantage demo account login)
MT5_PASSWORD                (Vantage demo account password)
UPSTOX_API_KEY              (optional: for India equity data)
UPSTOX_API_SECRET           (optional)
```

## Deployment Scripts

| Script | Purpose |
|--------|---------|
| `deploy.sh` | Main automation (10 phases) |
| `credentials-prompt.sh` | Interactive credential collection |
| `verify.sh` | Verify deployment health |
| `rollback.sh` | Safely rollback deployment |
| `health_check.sh` | Continuous health monitoring |

## Phases

1. **Provision Host** — System hardening, packages, user setup
2. **Deploy Code** — Git clone, Python venv, requirements
3. **Install Services** — Systemd units, enablement
4. **Headless MT5** — Wine setup, MT5 terminal, Xvfb
5. **Execution Gates** — Mode checks, account verification
6. **Controlled Demo Trade** — Test order execution
7. **Gold/Forex Auto-Trading** — Enable demo execution
8. **India Signals** — Upstox connection, signal-only mode
9. **Parallel Validation** — Compare with Mac scanner
10. **Health & Observability** — Boot persistence, logs, monitoring

## Deployment Status

Deployment runs until ONE of these outputs:

### ✅ Success
```
TRADING SYSTEM LIVE ON DIGITALOCEAN

Status Summary:
  • All 7 trading bots running
  • MT5 bridge connected to Vantage DEMO
  • Execution mode: dry_run (no orders execute)
  • India order execution: BLOCKED
  • Telegram routing: @Equitytrading_bot
  • Services auto-restart on failure
  • Boot persistence enabled
  • Secrets protected (mode 600)
```

### ❌ Failure
```
BLOCKED — <specific reason>

See deployment log for details:
  cat /var/log/medideals/deployment.log
```

## Operation Commands

```bash
# Check all services
systemctl status medideals-bots.target

# View live logs
journalctl -u medideals-bots.target -f

# View specific bot
journalctl -u medideals-gold-bot.service -n 100

# Restart all bots
systemctl restart medideals-bots.target

# Stop all bots
systemctl stop medideals-bots.target

# Health check
bash verify.sh

# Continuous health monitoring (every 60 seconds)
watch -n 60 bash health_check.sh

# Export logs
journalctl -u medideals-bots.target --since "1 day ago" > logs.txt
```

## Credentials Management

**File:** `/etc/medideals/telegram.env`
**Permissions:** 600 (owner only)
**Owner:** medideals:medideals

### View credentials (do NOT print to terminal):
```bash
# Check if configured (no value shown)
grep "TELEGRAM_BOT_TOKEN" /etc/medideals/telegram.env
```

### Update credentials:
```bash
sudo nano /etc/medideals/telegram.env
# Edit values
# Save (Ctrl+X, Y, Enter)
systemctl restart medideals-bots.target
```

### Rotate credentials (emergency):
```bash
# Stop services
systemctl stop medideals-bots.target

# Backup old credentials
sudo cp /etc/medideals/telegram.env /etc/medideals/telegram.env.backup

# Collect new credentials
sudo bash credentials-prompt.sh

# Restart services
systemctl restart medideals-bots.target

# Monitor
journalctl -u medideals-bots.target -f
```

## Important

### ⚠️ Execution Mode (Fail-Closed)

**Default:** `BOT_EXECUTION_MODE=dry_run`
- Signals flow to Telegram
- NO orders execute
- Safe for testing

**Production (requires authorization):**
```bash
# Only after 48-72 hours of stable observation
sudo nano /etc/medideals/telegram.env

# Change:
BOT_EXECUTION_MODE=production
LIVE_TRADING_CONFIRMED=YES

# Restart
systemctl restart medideals-bots.target
```

### ⚠️ India Order Protection

**INDIA_ORDERS_ENABLED=NO** (hardcoded)
- India bots send signals ONLY
- Zero order execution to any broker
- Cannot be changed via environment

### ⚠️ Vantage DEMO Only

**Account type verification happens automatically:**
1. Deployment checks account is DEMO
2. If live-money account detected: BLOCKED
3. Orders execute to Vantage DEMO only

### ⚠️ Mac Scanner Protection

**Existing service:** `com.ajay.trading-signals.scanner`
- STILL RUNNING on MacBook
- Remains UNTOUCHED until DigitalOcean proven
- Parallel validation: 24-48 hours
- Only retire Mac scanner after cutover confirmed

## Troubleshooting

### Bot not starting
```bash
journalctl -u medideals-gold-bot.service -n 50
# Check for errors above
systemctl restart medideals-gold-bot.service
```

### MT5 bridge not connecting
```bash
journalctl -u medideals-mt5-bridge.service -n 20
# Verify Xvfb is running
pgrep -x Xvfb

# Restart bridge
systemctl restart medideals-mt5-bridge.service
```

### Telegram messages not delivering
```bash
# Check token/chat ID
grep "TELEGRAM" /etc/medideals/telegram.env | head -2

# Test manually
curl -X POST "https://api.telegram.org/bot<TOKEN>/sendMessage" \
  -d "chat_id=7093601171&text=Test"
```

### No signals appearing
```bash
# Check bot logs
journalctl -u medideals-nifty-scalper.service -n 50

# Verify Upstox connection
grep "UPSTOX" /etc/medideals/telegram.env

# Check network
curl -s https://api.upstox.com/v2/market/quotes
```

## Monitoring

### Automated cron monitoring (every 5 minutes):
```bash
# Edit crontab
crontab -e

# Add line:
*/5 * * * * /home/medideals/MediDeals-iOS-App/health_check.sh >> /var/log/medideals/health.log 2>&1

# View health log
tail -f /var/log/medideals/health.log
```

### Live dashboard:
```bash
# Terminal 1: Watch services
watch -n 5 systemctl status medideals-bots.target

# Terminal 2: Watch logs
journalctl -u medideals-bots.target -f

# Terminal 3: Watch health
watch -n 60 bash verify.sh
```

## Rollback

If deployment fails or needs to be undone:

```bash
sudo bash rollback.sh

# Confirm rollback
# Services stop
# Code deleted
# Credentials preserved (can redeploy)
```

## Security Checklist

- [ ] SSH keys only (no password SSH)
- [ ] Firewall restricts to SSH port only
- [ ] Credentials file mode 600
- [ ] No credentials in logs (grep for tokens)
- [ ] Automatic security updates enabled
- [ ] Swap configured (2GB)
- [ ] Timezone set to UTC
- [ ] Log rotation configured (30 days)

## Log Locations

```
/var/log/medideals/deployment.log    # Deployment log
/var/log/medideals/health.log         # Health check log
journalctl -u medideals-*             # Systemd logs
```

## Support

For deployment issues:
1. Check deployment log: `cat /var/log/medideals/deployment.log`
2. Check service logs: `journalctl -u medideals-bots.target -n 100`
3. Run verification: `bash verify.sh`
4. See Troubleshooting section above

## Final Notes

- **DO NOT** deploy with live-money account credentials
- **DO NOT** share credentials via email/Slack
- **DO NOT** modify systemd files unless you know what you're doing
- **DO NOT** disable India order protection guard
- **DO NOT** retire Mac scanner until DigitalOcean is proven stable
- **DO** keep credentials file backed up securely
- **DO** monitor logs for first 48 hours after deployment
- **DO** test in dry_run mode before enabling production mode

---

**Ready to deploy?**

```bash
sudo bash credentials-prompt.sh && sudo bash deploy.sh
```