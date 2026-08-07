# DigitalOcean Deployment Guide

**Status**: Ready for deployment  
**Architecture**: Headless MT5 Bridge via Wine + Python/systemd  
**Execution Mode**: Dry-run (default, no orders) → Production (after gates)  
**Last Updated**: 2026-08-07  

---

## EXECUTIVE SUMMARY

This guide deploys the complete MediDeals trading bot suite to DigitalOcean:

| Service | Purpose | Execution | Data Source |
|---------|---------|-----------|------------|
| **MT5 Bridge** | Headless MT5 terminal (Wine) | Vantage DEMO only | N/A |
| **Gold Bot** | XAUUSD trading signals | MT5 + Python | Live market data |
| **Forex Scalper** | EURUSD/GBPUSD trading signals | MT5 + Python | Live market data |
| **BTC Bot** | BTCUSD trading signals | Signal-only | Yahoo Finance |
| **Nifty Scalper** | NIFTY/BANKNIFTY signals (signal owner) | Signal-only | Upstox |
| **Options Scalper** | Options signals (downstream of Nifty) | Signal-only | Upstox |
| **India Scalper** | Equity signals for Nifty 100 | Signal-only | Upstox |

**Critical Controls**:
- ✓ All credentials loaded from environment (never hardcoded)
- ✓ Default: `BOT_EXECUTION_MODE=dry_run` (signals only, no orders)
- ✓ Orders only execute in production mode + `LIVE_TRADING_CONFIRMED=YES`
- ✓ India-market bots: SIGNAL-ONLY (no order execution)
- ✓ Forex/Gold bots: Orders execute to Vantage DEMO account only
- ✓ All services auto-restart on failure and auto-start at boot

---

## PREREQUISITES

### 1. DigitalOcean Droplet

**Minimum specs:**
- Ubuntu 22.04 LTS
- 2 GB RAM
- 2 vCPU
- 60 GB SSD

**Network:**
- Public IP address
- SSH access as root or sudo user

### 2. Credentials (from secure vault)

Gather these before deployment:
```
TELEGRAM_BOT_TOKEN          (Telegram bot API token)
TELEGRAM_CHAT_ID            (Telegram destination chat ID)
MT5_LOGIN                   (Vantage demo account login)
MT5_PASSWORD                (Vantage demo account password)
UPSTOX_API_KEY              (Upstox market data API key)
UPSTOX_API_SECRET           (Upstox market data API secret)
```

**Do NOT paste these into chat or email — load from encrypted vault only.**

### 3. Vantage MT5 Account

- Login credential: Vantage demo account (e.g., 25285913)
- Server: VantageMarkets-Demo (not live/real account)
- Permission: Automated trading enabled in MT5 settings

---

## STEP 1: DROPLET SETUP

### SSH into the droplet:

```bash
ssh root@<droplet-ip>
```

### Update system:

```bash
apt update && apt upgrade -y
```

### Create medideals service user:

```bash
useradd -m -s /bin/bash medideals
usermod -aG sudo medideals
```

### Install dependencies:

```bash
apt install -y \
    git curl wget python3-pip python3-venv \
    wine wine32 wine64 xvfb x11vnc \
    libglib2.0-0:i386 libsm6 libxrender1 libxext6 \
    systemd-container
```

### Install winetricks:

```bash
wget -q -O /usr/local/bin/winetricks \
    https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
chmod +x /usr/local/bin/winetricks
```

### Create log directory:

```bash
mkdir -p /var/log/medideals
chown medideals:medideals /var/log/medideals
chmod 755 /var/log/medideals
```

---

## STEP 2: CLONE REPOSITORY

### As medideals user:

```bash
sudo -u medideals bash -c '
  cd /home/medideals
  git clone https://github.com/AjayOberoi1117/MediDeals-iOS-App.git
  cd MediDeals-iOS-App/telegram_bot
  python3 -m venv .venv
  source .venv/bin/activate
  pip install -q -r requirements.txt
'
```

---

## STEP 3: LOAD CREDENTIALS

### Create secure config file:

```bash
cat > /etc/medideals/telegram.env <<'EOF'
TELEGRAM_BOT_TOKEN=<PASTE_FROM_VAULT>
TELEGRAM_CHAT_ID=7093601171
BOT_EXECUTION_MODE=dry_run
MT5_LOGIN=<PASTE_FROM_VAULT>
MT5_PASSWORD=<PASTE_FROM_VAULT>
MT5_SERVER=VantageMarkets-Demo
UPSTOX_API_KEY=<PASTE_FROM_VAULT>
UPSTOX_API_SECRET=<PASTE_FROM_VAULT>
DEPLOYMENT_ENVIRONMENT=digitalocean
VANTAGE_ACCOUNT_VERIFIED=NO
LIVE_TRADING_CONFIRMED=NO
INDIA_ORDERS_ENABLED=NO
EOF
```

### Set secure permissions:

```bash
chmod 600 /etc/medideals/telegram.env
chown medideals:medideals /etc/medideals/telegram.env
```

### Verify (no output = correct):

```bash
sudo -u medideals cat /etc/medideals/telegram.env
```

---

## STEP 4: ONE-TIME VNC LOGIN TO VANTAGE MT5

**This step is required ONLY ONCE.** After login, MT5 auto-connects on every reboot.

### Setup virtual display + Wine:

```bash
sudo -u medideals bash <<'SETUP'
export WINEPREFIX=/home/medideals/.wine_mt5
export WINEARCH=win64
export DISPLAY=:99

# Start Xvfb virtual display
Xvfb :99 -screen 0 1024x768x24 &
sleep 3

# Initialize Wine
WINEDEBUG=-all wine wineboot --init 2>/dev/null
winetricks -q corefonts 2>/dev/null || true
sleep 5

# Download and install Windows Python 3.11
wget -q -O /tmp/python-win.exe \
    "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
WINEDEBUG=-all wine /tmp/python-win.exe /quiet InstallAllUsers=1 PrependPath=1
sleep 15

# Install MetaTrader5 + mt5linux packages in Wine Python
WINEDEBUG=-all wine python -m pip install --quiet MetaTrader5 mt5linux
sleep 5

# Download and install MT5 terminal
wget -q -O /tmp/mt5setup.exe \
    "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"
WINEDEBUG=-all wine /tmp/mt5setup.exe /auto
sleep 30

echo "Wine setup complete. Ready for VNC login."
SETUP
```

### Start VNC server (on droplet):

```bash
sudo -u medideals bash <<'VNC'
export WINEPREFIX=/home/medideals/.wine_mt5
export DISPLAY=:99
export WINEDEBUG=-all

# Start VNC server
x11vnc -display :99 -nopw -listen 0.0.0.0 -port 5900 &

# Launch MT5 terminal
wine '/home/medideals/.wine_mt5/drive_c/Program Files/MetaTrader 5/terminal64.exe' &

echo "VNC server running on port 5900"
echo "Connect from your Mac with: vnc://$(curl -s ifconfig.me):5900"
VNC
```

### On your Mac:

1. Open **Terminal** (or use VNC viewer app)
2. Connect to VNC:
   ```bash
   open "vnc://$(ssh root@<droplet-ip> curl -s ifconfig.me):5900"
   ```

### In the MT5 window on VNC:

1. **File** → **Login to Trade Account**
   - **Login**: (your Vantage demo login, e.g., 25285913)
   - **Server**: VantageMarkets-Demo
   - **Password**: (your Vantage demo password)
   - ✓ **Save password** (required for auto-reconnect)

2. **Tools** → **Options** → **Expert Advisors**
   - ✓ Allow automated trading
   - ✓ Allow WebRequest
   - Click OK

3. **Close VNC and terminal** (Ctrl+C in droplet terminal)

**That's it!** MT5 will auto-reconnect on every reboot from now on.

---

## STEP 5: INSTALL SYSTEMD SERVICES

### Copy service files to droplet:

```bash
# From your local machine
scp medideals-*.service medideals-*.target \
    root@<droplet-ip>:/etc/systemd/system/
```

### On droplet, reload systemd:

```bash
systemctl daemon-reload
systemctl enable medideals-bots.target
```

### Start all services:

```bash
systemctl start medideals-bots.target
```

---

## STEP 6: RUN VERIFICATION GATES

Before enabling production mode, run all verification checks:

```bash
sudo -u medideals python3 \
    /home/medideals/MediDeals-iOS-App/DIGITALOCEAN_VERIFICATION_GATES.py
```

**Expected output:**
```
✓ GATE 1: Environment Variables: PASS
✓ GATE 2: MT5 Wine Bridge Running: PASS
✓ GATE 3: MT5 Vantage DEMO Account Verified: PASS
✓ GATE 4: Upstox Market Data Connectivity: PASS
✓ GATE 5: Telegram Delivery Verified: PASS
✓ GATE 6: Nifty 100 Universe Data: PASS
✓ GATE 7: Order Execution Guard (dry_run): PASS
✓ GATE 8: Systemd Services Healthy: PASS

Summary: 8 PASS, 0 FAIL, 0 SKIP

✓ ALL GATES PASSED — DEPLOYMENT READY
```

**If any gate fails**, fix the issue and re-run until all pass.

---

## STEP 7: VERIFY IN DRY-RUN MODE

Run for 24-48 hours in dry-run mode to verify:
- All bots start successfully
- Signals flow to Telegram
- No errors in logs
- MT5 bridge stays connected

### Monitor logs:

```bash
# Watch all bots in real-time
journalctl -u medideals-bots.target -f

# Watch specific bot
journalctl -u medideals-gold-bot.service -f

# View last 100 lines of a bot
journalctl -u medideals-gold-bot.service -n 100
```

### Expected log output:

```
medideals-gold-bot[12345]: [GOLD BOT] Scanning XAUUSD...
medideals-gold-bot[12345]: [GOLD BOT] EMA crossover detected at 2026.50
medideals-gold-bot[12345]: [GOLD BOT] Signal sent to Telegram [DRY-RUN MODE]
medideals-gold-bot[12345]: [GOLD BOT] Order execution DISABLED (BOT_EXECUTION_MODE=dry_run)
```

---

## STEP 8: SWITCH TO PRODUCTION MODE (CTO ONLY)

**Only after 48+ hours of dry-run verification and explicit CTO approval.**

### Edit credentials file:

```bash
sudo nano /etc/medideals/telegram.env
```

Change these lines:
```ini
BOT_EXECUTION_MODE=production
LIVE_TRADING_CONFIRMED=YES
VANTAGE_ACCOUNT_VERIFIED=YES
```

### Restart all services:

```bash
systemctl restart medideals-bots.target
```

### Re-run verification gates:

```bash
sudo -u medideals python3 \
    /home/medideals/MediDeals-iOS-App/DIGITALOCEAN_VERIFICATION_GATES.py
```

### Watch logs closely for first 30 minutes:

```bash
journalctl -u medideals-bots.target -f
```

---

## OPERATIONAL COMMANDS

### Status of all bots:

```bash
systemctl status medideals-bots.target
```

### List running services:

```bash
systemctl list-units --type=service | grep medideals
```

### Restart single bot:

```bash
systemctl restart medideals-gold-bot.service
```

### Stop all bots:

```bash
systemctl stop medideals-bots.target
```

### View logs for specific timeframe:

```bash
journalctl -u medideals-gold-bot.service --since "2 hours ago" --until "1 hour ago"
```

### Export audit log:

```bash
journalctl -u medideals-bots.target --since "1 week ago" > /tmp/medideals_audit.log
```

---

## TROUBLESHOOTING

### MT5 bridge won't start

```bash
journalctl -u medideals-mt5-bridge.service -n 50
```

Check if Xvfb is running:
```bash
pgrep -x Xvfb
```

### Bot crashing repeatedly

Check logs for errors:
```bash
journalctl -u medideals-gold-bot.service -n 100 | grep -i error
```

Restart with more logging:
```bash
systemctl stop medideals-gold-bot.service
cd /home/medideals/MediDeals-iOS-App/telegram_bot
source .venv/bin/activate
python3 -u gold_bot.py
```

### Telegram message not delivering

Verify token and chat ID:
```bash
source /etc/medideals/telegram.env
echo "Token: ${TELEGRAM_BOT_TOKEN:0:10}..."
echo "Chat ID: $TELEGRAM_CHAT_ID"
```

Test manually:
```bash
curl -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}&text=Test"
```

### No orders executing (in production mode)

1. Verify `BOT_EXECUTION_MODE=production`
2. Verify `LIVE_TRADING_CONFIRMED=YES`
3. Verify MT5 is connected to Vantage DEMO (not live)
4. Check MT5 terminal log for "Allow automated trading" enabled
5. Check for sufficient margin in Vantage account

---

## SECURITY CHECKLIST

- [ ] `/etc/medideals/telegram.env` is mode 600
- [ ] Credentials never appear in logs (grep for token)
- [ ] No credentials hardcoded in Python files
- [ ] systemd services run as `medideals` user (not root)
- [ ] Log retention configured (30 days)
- [ ] SSH key-based auth only (no passwords)
- [ ] Firewall restricts inbound to SSH only

---

## BACKUP & RECOVERY

### Backup configuration:

```bash
tar -czf /tmp/medideals_backup_$(date +%Y%m%d).tar.gz \
  /etc/medideals /home/medideals/.wine_mt5
```

### Restore from backup:

```bash
tar -xzf /tmp/medideals_backup_20260808.tar.gz -C /
systemctl restart medideals-bots.target
```

---

## MONITORING & ALERTING

### Health check (run every 5 minutes):

```bash
*/5 * * * * /home/medideals/health_check.sh
```

### Expected metrics to monitor:

- All 7 bot processes running
- MT5 bridge connected
- Upstox API responsive
- Telegram delivery success rate > 99%
- P&L reports sent daily at scheduled time

---

## FINAL VERIFICATION CHECKLIST

Run this before marking deployment complete:

```
□ All 8 verification gates pass
□ All 7 bots running for 48+ hours without crashes
□ Signals flowing to Telegram
□ No credentials in logs or stdout
□ systemd services auto-restart on failure
□ systemd services auto-start at boot
□ MT5 bridge stays connected
□ Upstox data available and fresh
□ India order execution blocked (INDIA_ORDERS_ENABLED=NO)
□ Forex/Gold orders execute to DEMO account only
□ Log rotation configured
□ Backup procedures tested
```

---

**When all items are checked: TRADING SYSTEM FULLY OPERATIONAL ON DIGITALOCEAN**

For support, contact: CTO (Ajay Oberoi)
