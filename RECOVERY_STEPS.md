# DigitalOcean Trading Bot Recovery - Step by Step

**Droplet IP**: 168.144.30.182  
**Repository**: /root/MediDeals-iOS-App/telegram_bot  
**Objective**: Restore fully operational trading system on existing droplet

---

## BEFORE YOU START

- ✓ Droplet is live and accessible
- ✓ Repository exists and has been verified
- ✓ Wine/MT5 environment has been set up
- ✓ MT5_PASSWORD has been added to .env
- ✓ Windows Python 3.11 is installed
- ✓ wine_server.py code exists

---

## PHASE 1: STABILIZE MT5 BRIDGE

**Goal**: Ensure Wine/MT5/bridge startup is clean and idempotent.

```bash
ssh root@168.144.30.182

cd /root/MediDeals-iOS-App

# Run stabilization script
sudo bash stabilize_mt5_bridge.sh
```

**Expected output**:
```
✓ Xvfb :99 active
✓ MT5 terminal launched
✓ wine_server.py active on port 18812
✓ Bridge responding to connections
```

**If fails**: Check `/tmp/wine_server.log` for errors.

---

## PHASE 2: VERIFY VANTAGE DEMO ACCOUNT

**Goal**: Confirm MT5 is connected to Vantage DEMO (not live-money).

```bash
cd /root/MediDeals-iOS-App

# Run verification
python3 verify_vantage_demo.py
```

**Expected output**:
```
DEMO ACCOUNT VERIFIED
  ✓ MT5 bridge accessible
  ✓ Account initialized
  ✓ Account is DEMO (safe)
  ✓ Trading permission available
  ✓ Symbol quotes available
```

**If fails**: Check .env credentials, MT5 terminal logs.

---

## PHASE 3: START TRADER.PY

**Goal**: Begin order execution from Python.

```bash
cd /root/MediDeals-iOS-App/telegram_bot

# Start trader
bash start_trader.sh
```

**Expected output**:
```
✓ Bridge port 18812 is listening
✓ trader.py running (PID: XXXX)
✓ Logging to: logs/trader.log
```

**Monitor logs**:
```bash
tail -f logs/trader.log
```

---

## PHASE 4: CLEAN DUPLICATE PROCESSES

**Goal**: Remove duplicate bot generations (keep single instances).

```bash
sudo bash cleanup_duplicate_bots.sh
```

**Expected output**:
```
Found N instances (DUPLICATE)
Removing duplicates...
✓ All bots now running in single instances
```

---

## PHASE 5: VERIFY INDIA SAFETY

**Goal**: Ensure India symbols cannot execute orders.

```bash
bash verify_india_safety.sh
```

**Expected output**:
```
✓ India symbols NOT in trader TRADEABLE list
✓ India signal bots remain signal-only
✓ Upstox used for market data only
```

---

## PHASE 6: SECURE CREDENTIALS

**Goal**: Remove hardcoded tokens from inactive EAs.

```bash
bash secure_credentials.sh
```

**Expected output**:
```
✓ trader.py uses environment variables
✓ .env file permissions secure (600)
✓ Python bots use environment for credentials
```

---

## PHASE 7: SETUP AUTOSTART

**Goal**: Configure boot persistence and watchdog.

Create `/root/start_trading_system.sh`:

```bash
#!/bin/bash
# Start all trading components
cd /root/MediDeals-iOS-App/telegram_bot

# Start MT5 bridge
bash stabilize_mt5_bridge.sh

# Start trader
bash start_trader.sh

# Start signal bots
nohup python3 gold_bot.py >> logs/gold_bot.log 2>&1 &
nohup python3 forex_scalper.py >> logs/forex_scalper.log 2>&1 &
nohup python3 btc_bot.py >> logs/btc_bot.log 2>&1 &
nohup python3 nifty_scalper.py >> logs/nifty_scalper.log 2>&1 &
```

Add to crontab:

```bash
crontab -e

# Add this line:
@reboot /root/start_trading_system.sh
```

---

## PHASE 8: FINAL VERIFICATION

**Goal**: Comprehensive health check.

```bash
# Check all processes
ps aux | grep -E 'gold_bot|forex_scalper|btc_bot|nifty_scalper|trader|wine_server|terminal64|Xvfb' | grep -v grep

# Check bridge
netstat -tuln | grep 18812

# Check Telegram (watch for signals)
tail -20 logs/gold_bot.log

# Check for errors
grep -i error logs/*.log | head -10
```

**Expected**:
- All bots running (single instances)
- Port 18812 listening
- No duplicate processes
- No error loops
- Signals flowing to Telegram

---

## ROLLBACK (if needed)

```bash
# Kill all bots
pkill -f "python3.*bot\.py\|python3.*trader\.py\|python3.*scalper\.py"

# Kill Wine/MT5
pkill -9 wineserver
pkill -f "terminal64.exe"

# Kill Xvfb
pkill -x Xvfb

# Kill watchdog
crontab -e
# Remove @reboot line
```

---

## TROUBLESHOOTING

### Bridge won't start
```bash
# Check Wine
ls -la /root/.wine_mt5/drive_c/Program\ Files/MetaTrader\ 5/

# Check logs
tail -50 /tmp/wine_server.log

# Restart
pkill -9 wineserver
bash stabilize_mt5_bridge.sh
```

### Account not DEMO
```bash
# Check .env credentials
grep MT5_ /root/MediDeals-iOS-App/telegram_bot/.env

# Verify they're for Vantage DEMO, not live
```

### trader.py not executing
```bash
# Check logs
tail -50 logs/trader.log

# Verify bridge is running
lsof -i :18812

# Restart trader
pkill -f trader.py
bash start_trader.sh
```

### Duplicate processes
```bash
# List all
pgrep -f "python3" | while read pid; do ps -p $pid -o cmd=; done

# Kill duplicates manually
kill -9 PID

# Or use automated cleanup
bash cleanup_duplicate_bots.sh
```

---

## MONITORING

Daily checks:

```bash
# System health
free -h
df -h

# Process status
ps aux | grep -E 'bot\.py|trader\.py|wine_server'

# Recent errors
journalctl -n 50 | grep -i error
tail -20 logs/*.log | grep -i error

# Signal delivery
tail -10 logs/gold_bot.log
tail -10 logs/forex_scalper.log
```

---

## FINAL STATUS

When complete:

```
✓ Xvfb running
✓ MT5 terminal running
✓ wine_server.py listening (port 18812)
✓ trader.py executing
✓ Gold bot running
✓ Forex bot running
✓ BTC bot running
✓ Nifty scanner running
✓ India signal-only verified
✓ Vantage DEMO verified
✓ Single bot instances
✓ Boot persistence enabled

TRADING BOTS FULLY OPERATIONAL ON DIGITALOCEAN
```

---

**Contact**: For issues, check logs in `/root/MediDeals-iOS-App/telegram_bot/logs/`
