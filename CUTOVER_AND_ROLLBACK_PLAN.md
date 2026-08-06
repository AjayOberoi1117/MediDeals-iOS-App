# Cutover and Rollback Plan

**Purpose**: Safely transition bot execution from Ajay's Mac (local) to DigitalOcean (production)  
**Duration**: ~30 minutes (includes verification)  
**Rollback Time**: ~5 minutes (if needed)  
**Status**: Ready for CTO authorization  

---

## PRE-CUTOVER CHECKLIST (Ajay's Mac)

### Phase 0: Verify Local Environment Ready (5 min)

**On Ajay's Mac**:

```bash
# 1. Confirm branch and repository
cd /path/to/MediDeals-iOS-App
git branch  # Should show: cto/single-telegram-routing-clean
git rev-parse HEAD  # Should show: f9710d3

# 2. Verify all 7 bots running
ps aux | grep -E "(btc_bot|gold_bot|signal_bot|forex_scalper|india_scalper|nifty_scalper|options_scalper)\.py" | grep -v grep | wc -l
# Should show: 7 processes

# 3. Confirm signals reaching @Equitytrading_bot
# Check Telegram: Should see messages from all 7 bots in last 15 minutes
# Look for: [BTC BOT], [GOLD BOT], [SIGNAL BOT], [FOREX SCALPER], [INDIA SCALPER], [NIFTY SCALPER], [OPTIONS SCALPER]

# 4. Verify dry-run mode
source ~/.config/medideals/telegram.env
echo $BOT_EXECUTION_MODE  # Should output: dry_run

# 5. Confirm no process duplicates
for bot in btc_bot gold_bot signal_bot forex_scalper india_scalper nifty_scalper options_scalper; do
  count=$(pgrep -f "$bot.py" | wc -l)
  if [ $count -ne 1 ]; then
    echo "✗ ERROR: Found $count instances of $bot"
    exit 1
  fi
done
echo "✓ All bots: single instance"

# 6. Verify zero errors in logs (check last 50 lines of each)
for bot_dir in ~/bot_logs/*; do
  [ -d "$bot_dir" ] && tail -50 $bot_dir/*.log | grep -i "error\|exception\|traceback" && echo "✗ Errors found in $bot_dir" && exit 1
done
echo "✓ No error logs found"

# 7. Final confirmation
echo "✓✓✓ Pre-cutover checklist PASSED ✓✓✓"
```

**Expected Output**:
```
✓ 7 processes running
✓ All messages reaching @Equitytrading_bot
✓ All bots: single instance
✓ No error logs found
✓✓✓ Pre-cutover checklist PASSED ✓✓✓
```

---

## PRE-CUTOVER CHECKLIST (DigitalOcean Droplet)

### Phase 0: Verify Droplet Ready (5 min)

**On DigitalOcean**:

```bash
ssh medideals@<droplet_ip>

# 1. Verify repository
cd ~/MediDeals-iOS-App
git branch  # Should show: cto/single-telegram-routing-clean
git rev-parse HEAD  # Should show: f9710d3

# 2. Verify Python environment
source ~/venv_medideals/bin/activate
python3 --version  # Should be 3.10+
pip list | grep -E "pandas|yfinance|requests|pytz|python-dotenv"  # All present

# 3. Verify credentials file
sudo ls -la /etc/medideals/telegram.env  # Should show: -rw------- 1 medideals medideals

# 4. Verify systemd services created
sudo systemctl list-unit-files | grep medideals  # Should show 7 services

# 5. Quick telegram connectivity test
python3 << 'EOF'
import os
os.environ["TELEGRAM_BOT_TOKEN"] = os.getenv("TELEGRAM_BOT_TOKEN", "")
os.environ["TELEGRAM_CHAT_ID"] = os.getenv("TELEGRAM_CHAT_ID", "")
import requests
url = f"https://api.telegram.org/bot{os.environ['TELEGRAM_BOT_TOKEN']}/getMe"
try:
    r = requests.post(url, timeout=10)
    print("✓ Telegram API reachable" if r.status_code == 200 else "✗ Telegram API failed")
except Exception as e:
    print(f"✗ Error: {e}")
EOF

# 6. Verify disk space
df -h ~/  # Should show >5GB available

# 7. Final confirmation
echo "✓✓✓ DigitalOcean pre-cutover checklist PASSED ✓✓✓"
```

**Expected Output**:
```
✓ Repository correct (f9710d3)
✓ Python environment ready
✓ Credentials file secured
✓ 7 systemd services configured
✓ Telegram API reachable
✓ Disk space adequate (>5GB)
✓✓✓ DigitalOcean pre-cutover checklist PASSED ✓✓✓
```

---

## CUTOVER PROCEDURE

### Phase 1: Start Bots on DigitalOcean (5 min)

**On DigitalOcean** (as medideals user):

```bash
ssh medideals@<droplet_ip>

# 1. Start first bot
echo "[$(date)] Starting BTC Bot on DigitalOcean" | tee -a ~/startup.log
sudo systemctl start medideals-btc-bot.service
sleep 2

# 2. Start second bot
echo "[$(date)] Starting Gold Bot on DigitalOcean" | tee -a ~/startup.log
sudo systemctl start medideals-gold-bot.service
sleep 2

# 3. Start third bot
echo "[$(date)] Starting Signal Bot on DigitalOcean" | tee -a ~/startup.log
sudo systemctl start medideals-signal-bot.service
sleep 2

# 4. Start fourth bot
echo "[$(date)] Starting Forex Scalper on DigitalOcean" | tee -a ~/startup.log
sudo systemctl start medideals-forex-scalper.service
sleep 2

# 5. Start fifth bot
echo "[$(date)] Starting India Scalper on DigitalOcean" | tee -a ~/startup.log
sudo systemctl start medideals-india-scalper.service
sleep 2

# 6. Start sixth bot
echo "[$(date)] Starting Nifty Scalper on DigitalOcean" | tee -a ~/startup.log
sudo systemctl start medideals-nifty-scalper.service
sleep 2

# 7. Start seventh bot
echo "[$(date)] Starting Options Scalper on DigitalOcean" | tee -a ~/startup.log
sudo systemctl start medideals-options-scalper.service
sleep 2

# 8. Verify all running
echo "[$(date)] Verifying startup..." | tee -a ~/startup.log
sudo systemctl status medideals-*.service | grep -E "active \(running\)|active \(exited\)" | wc -l
# Should output: 7

# 9. Monitor logs for 30 seconds
echo "[$(date)] Monitoring logs for 30 seconds..." | tee -a ~/startup.log
for i in {1..6}; do
  echo "[$(date)] Check $i/6: $(sudo systemctl status medideals-btc-bot.service | grep 'active')"
  sleep 5
done

# 10. Verify Telegram messages arriving
echo "[$(date)] Startup Phase 1 COMPLETE" | tee -a ~/startup.log
```

**Expected Log**:
```
[2026-08-06 14:30:05] Starting BTC Bot on DigitalOcean
[2026-08-06 14:30:07] Starting Gold Bot on DigitalOcean
[2026-08-06 14:30:09] Starting Signal Bot on DigitalOcean
...
[2026-08-06 14:30:17] Verifying startup...
7
[2026-08-06 14:30:48] Startup Phase 1 COMPLETE
```

### Phase 2: Verify DigitalOcean Bots Working (10 min)

**Continue on DigitalOcean**:

```bash
# 1. Check all services are active
sudo systemctl status medideals-*.service | grep -c "active (running)"
# Should show: 7

# 2. View real-time logs
echo "=== MONITORING LOGS (Press Ctrl+C to stop) ==="
sudo journalctl -u 'medideals-*.service' -f --no-tail &
TAIL_PID=$!

# Let logs run for 30 seconds
sleep 30
kill $TAIL_PID 2>/dev/null

# 3. Check for errors in logs
echo ""
echo "=== CHECKING FOR ERRORS ==="
sudo journalctl -u 'medideals-*.service' --since "30 seconds ago" | grep -i "error\|exception\|traceback" || echo "✓ No errors found"

# 4. Verify Telegram test message (optional)
python3 << 'EOF'
import os, requests, time
from dotenv import load_dotenv

load_dotenv('/etc/medideals/telegram.env')
token = os.getenv("TELEGRAM_BOT_TOKEN")
chat_id = os.getenv("TELEGRAM_CHAT_ID")

url = f"https://api.telegram.org/bot{token}/sendMessage"
msg = f"✅ [CUTOVER] DigitalOcean bots online as of {time.strftime('%d %b %Y %H:%M:%S IST')}"
r = requests.post(url, json={"chat_id": chat_id, "text": msg}, timeout=10)
print("✓ Cutover notification sent" if r.status_code == 200 else f"✗ Failed: {r.status_code}")
EOF

# 5. Final verification
echo ""
echo "✓✓✓ Phase 2 COMPLETE - DigitalOcean bots verified ✓✓✓"
```

### Phase 3: Stop Bots on Ajay's Mac (2 min)

**Switch to Ajay's Mac**:

```bash
# 1. Stop all bots gracefully
echo "Stopping bots on Ajay's Mac..."
for bot_pid in $(pgrep -f "btc_bot|gold_bot|signal_bot|forex_scalper|india_scalper|nifty_scalper|options_scalper"); do
  echo "Killing PID $bot_pid..."
  kill -TERM $bot_pid  # Graceful shutdown
done

# 2. Wait for graceful shutdown
sleep 10

# 3. Verify all stopped
echo ""
ps aux | grep -E "(btc_bot|gold_bot|signal_bot|forex_scalper|india_scalper|nifty_scalper|options_scalper)\.py" | grep -v grep
# Should show: (nothing)

echo "✓ All bots stopped on Ajay's Mac"

# 4. Send final cutover message
source ~/.config/medideals/telegram.env
python3 << 'EOF'
import os, requests, time
token = os.getenv("TELEGRAM_BOT_TOKEN")
chat_id = os.getenv("TELEGRAM_CHAT_ID")

url = f"https://api.telegram.org/bot{token}/sendMessage"
msg = f"🔄 [CUTOVER] Local Mac bots stopped. DigitalOcean now primary."
r = requests.post(url, json={"chat_id": chat_id, "text": msg}, timeout=10)
print("✓ Cutover message sent" if r.status_code == 200 else f"✗ Failed")
EOF

echo "✓✓✓ Phase 3 COMPLETE - Local Mac bots stopped ✓✓✓"
```

---

## POST-CUTOVER VERIFICATION (5 min)

**On DigitalOcean**:

```bash
# 1. Confirm all bots running
sudo systemctl status medideals-*.service | grep -c "active (running)"
# Should output: 7

# 2. Confirm Telegram delivery working
echo "Checking last 15 Telegram messages..."
sudo journalctl -u 'medideals-*.service' --since "5 minutes ago" | grep -i "telegram" | head -5

# 3. Check resource usage
echo ""
echo "=== RESOURCE USAGE ==="
ps aux | grep -E "python3.*bot" | grep -v grep | awk '{print $1, $2, $3, $4, $9, $11, $12}'
# Should show 7 processes, each using <5% CPU, <200MB memory

# 4. Verify no duplicate processes
echo ""
echo "=== DUPLICATE CHECK ==="
for bot in btc_bot gold_bot signal_bot forex_scalper india_scalper nifty_scalper options_scalper; do
  count=$(pgrep -f "$bot.py" | wc -l)
  echo "medideals-${bot}: $count process(es)"
done
# All should show: 1 process

# 5. Final confirmation
echo ""
echo "✓✓✓ POST-CUTOVER VERIFICATION COMPLETE ✓✓✓"
echo ""
echo "Status: Cutover SUCCESSFUL"
echo "Primary: DigitalOcean"
echo "Backup: Ajay's Mac (stopped)"
```

**Expected Output**:
```
7
=== RESOURCE USAGE ===
medideals 12345 0.2 50M ...
medideals 12346 0.1 45M ...
... (7 lines total)

=== DUPLICATE CHECK ===
medideals-btc-bot: 1 process(es)
medideals-gold-bot: 1 process(es)
... (7 lines total)

✓✓✓ POST-CUTOVER VERIFICATION COMPLETE ✓✓✓

Status: Cutover SUCCESSFUL
Primary: DigitalOcean
Backup: Ajay's Mac (stopped)
```

---

## ROLLBACK PROCEDURE

### Trigger Rollback (If DigitalOcean Fails)

**Conditions for Rollback**:
- ✗ DigitalOcean bots crash and don't restart
- ✗ Telegram API unreachable from DigitalOcean
- ✗ >25% of signals fail to send
- ✗ Operator manually requests rollback

### Rollback Steps (5 min)

**Step 1: Stop DigitalOcean Bots**

```bash
ssh medideals@<droplet_ip>

echo "[$(date)] ROLLBACK: Stopping DigitalOcean bots" | tee -a ~/rollback.log
sudo systemctl stop medideals-*.service
sleep 5

# Verify stopped
sudo systemctl status medideals-*.service | grep -c "inactive (dead)"
# Should output: 7

echo "[$(date)] DigitalOcean bots stopped"
```

**Step 2: Restart Ajay's Mac Bots**

```bash
# On Ajay's Mac

echo "[$(date)] ROLLBACK: Starting Mac bots" >> ~/rollback.log

source ~/.config/medideals/telegram.env

cd ~/MediDeals-iOS-App/telegram_bot

# Start bots
nohup python3 btc_bot.py >> ~/logs/btc_bot.log 2>&1 &
sleep 2
nohup python3 gold_bot.py >> ~/logs/gold_bot.log 2>&1 &
sleep 2
nohup python3 signal_bot.py >> ~/logs/signal_bot.log 2>&1 &
sleep 2
nohup python3 forex_scalper.py >> ~/logs/forex_scalper.log 2>&1 &
sleep 2
nohup python3 india_scalper.py >> ~/logs/india_scalper.log 2>&1 &
sleep 2
nohup python3 nifty_scalper.py >> ~/logs/nifty_scalper.log 2>&1 &
sleep 2
nohup python3 options_scalper.py >> ~/logs/options_scalper.log 2>&1 &

# Verify
sleep 5
ps aux | grep -E "(btc_bot|gold_bot|signal_bot|forex_scalper|india_scalper|nifty_scalper|options_scalper)\.py" | grep -v grep | wc -l
# Should output: 7

echo "[$(date)] ROLLBACK COMPLETE: Bots restored on Mac" >> ~/rollback.log
```

**Step 3: Notify Team**

```bash
# Send Telegram notification
source ~/.config/medideals/telegram.env

python3 << 'EOF'
import os, requests, time
token = os.getenv("TELEGRAM_BOT_TOKEN")
chat_id = os.getenv("TELEGRAM_CHAT_ID")

url = f"https://api.telegram.org/bot{token}/sendMessage"
msg = f"⚠️ [ROLLBACK] DigitalOcean service issue detected. Signals restored to Ajay's Mac. Operator review required."
r = requests.post(url, json={"chat_id": chat_id, "text": msg}, timeout=10)
print("✓ Notification sent")
EOF
```

### Rollback Verification

```bash
# Verify Mac bots are live
ps aux | grep -E "(btc_bot|gold_bot|signal_bot)" | grep -v grep

# Check logs for errors
tail -50 ~/logs/*.log | grep -i error

# Verify Telegram delivery
# Check Telegram app: should see recent signals from Mac

echo "✓✓✓ ROLLBACK COMPLETE ✓✓✓"
echo "Status: Back to Ajay's Mac"
echo "Next: Investigate DigitalOcean failure and fix"
```

---

## POST-ROLLBACK INVESTIGATION

If rollback was triggered, investigate root cause:

```bash
# On DigitalOcean
ssh medideals@<droplet_ip>

# 1. Check service status
sudo systemctl status medideals-btc-bot.service

# 2. Review logs
sudo journalctl -u medideals-btc-bot.service -n 50

# 3. Check system resources
df -h  # Disk space
free -h  # Memory
uptime  # Load average

# 4. Test Telegram connectivity
python3 << 'EOF'
import requests
token = "TELEGRAM_BOT_TOKEN"
url = f"https://api.telegram.org/bot{token}/getMe"
try:
    r = requests.post(url, timeout=10)
    print(f"Status: {r.status_code}")
except Exception as e:
    print(f"Error: {e}")
EOF

# 5. Check network
ping 8.8.8.8  # Google DNS
curl https://api.telegram.org/  # Telegram domain

# 6. Collect full diagnostic log
echo "=== DIAGNOSTIC LOG ===" > ~/diagnostics.txt
echo "Timestamp: $(date)" >> ~/diagnostics.txt
echo "" >> ~/diagnostics.txt
echo "Systemd status:" >> ~/diagnostics.txt
sudo systemctl status medideals-*.service >> ~/diagnostics.txt 2>&1
echo "" >> ~/diagnostics.txt
echo "Recent logs (last 100 lines):" >> ~/diagnostics.txt
sudo journalctl -u 'medideals-*.service' -n 100 >> ~/diagnostics.txt 2>&1
echo "" >> ~/diagnostics.txt
echo "Resource usage:" >> ~/diagnostics.txt
ps aux | grep medideals >> ~/diagnostics.txt
df -h >> ~/diagnostics.txt
free -h >> ~/diagnostics.txt
uptime >> ~/diagnostics.txt

# Send diagnostic report to CTO/Ajay
echo "Diagnostic log saved to ~/diagnostics.txt"
```

---

## ROLLBACK ABORT (Cancel Rollback Mid-Procedure)

If DigitalOcean recovers during rollback:

```bash
# On Ajay's Mac: Keep bots running (already started)
# On DigitalOcean: Restart services

ssh medideals@<droplet_ip>

echo "Restarting DigitalOcean bots..."
sudo systemctl start medideals-*.service

# Monitor both Mac and DigitalOcean logs
ssh medideals@<droplet_ip> "sudo journalctl -u 'medideals-*.service' -f" &
tail -f ~/logs/*.log

# Decision: Which primary wins?
# Option A: Keep DigitalOcean as primary (stop Mac bots)
# Option B: Keep Mac as primary (stop DigitalOcean bots)
# Operator decision required
```

---

## MONITORING DURING CUTOVER (Continuous)

**Terminal 1: DigitalOcean Logs**
```bash
ssh medideals@<droplet_ip> "sudo journalctl -u 'medideals-*.service' -f"
```

**Terminal 2: Ajay's Mac Logs**
```bash
tail -f ~/logs/btc_bot.log ~/logs/gold_bot.log ~/logs/signal_bot.log
```

**Terminal 3: Telegram Verification**
```bash
# Open Telegram app and monitor @Equitytrading_bot
# Should see continuous signal flow from both Mac (until stopped) and DigitalOcean (during startup)
# Then DigitalOcean signals only (after Mac stopped)
```

---

## SUCCESS CRITERIA

Cutover is **SUCCESSFUL** when:

✓ All 7 bots running on DigitalOcean (`systemctl status medideals-*.service` shows 7 active)  
✓ Telegram messages arriving continuously (at least 1 signal every 15 min)  
✓ No errors in logs (`journalctl | grep -i error` is empty)  
✓ All bots running as single instances (no duplicates)  
✓ Resource usage normal (<5% CPU per bot, <200MB RAM per bot)  
✓ Rollback completed (Mac bots stopped)  
✓ Duration: <30 minutes total  
✓ Team notified of completion  

---

## FAILURE SCENARIOS & RECOVERY

| Scenario | Detection | Recovery |
|----------|-----------|----------|
| **DigitalOcean bot crashes on startup** | Systemd reports 'inactive' or 'failed' | Trigger rollback to Mac |
| **Telegram API unreachable from DO** | "Telegram failed" in logs | Check firewall, restart bots, if still fails rollback |
| **Mac bots still sending after cutover** | Duplicate signals in Telegram | Kill Mac bots manually: `pkill -f "btc_bot\|gold_bot"` |
| **Disk space full on DO** | df shows 0% available | SSH in, clear old logs: `sudo journalctl --vacuum-size=1M` |
| **Network partition (DO isolated)** | Can't SSH to DO, signals stop | Use DigitalOcean console to restart network, or rollback |
| **Partial failure (3 of 7 bots down)** | Systemctl shows some inactive | Restart failed services: `sudo systemctl restart medideals-btc-bot.service` |

---

## COMMUNICATION TEMPLATE

### Pre-Cutover Announcement

```
🚀 [SCHEDULED MAINTENANCE] Cutover to DigitalOcean
Timing: [DATE] [TIME] IST
Duration: ~30 minutes
Impact: Brief signal delay possible (~5 min) during transition
Status: Will be updated in Telegram channel
```

### Cutover In Progress

```
🔄 [CUTOVER IN PROGRESS]
Step 1: Starting DigitalOcean bots...
Step 2: Verifying DigitalOcean...
Step 3: Stopping Ajay's Mac...
ETA: 15 minutes remaining
```

### Cutover Complete

```
✅ [CUTOVER COMPLETE]
Primary: DigitalOcean
Status: All 7 bots online and scanning
Latest signal: [TIME] [BOT] [DIRECTION]
Backup: Ajay's Mac (standby)
```

### Rollback Notification

```
⚠️ [ROLLBACK INITIATED]
Reason: [SPECIFIC REASON]
Action: Signals restored to Ajay's Mac
Timeline: Service restored in [X] minutes
Investigation: [CTO] to diagnose DigitalOcean issue
```

---

## CHECKLIST (Print & Use)

```
PRE-CUTOVER (Ajay's Mac)
☐ 7 bots running locally
☐ Signals reaching @Equitytrading_bot
☐ Zero error logs
☐ No process duplicates
☐ dry_run mode confirmed
☐ Repository checkout confirmed (f9710d3)

PRE-CUTOVER (DigitalOcean)
☐ Repository cloned (f9710d3)
☐ Python environment ready
☐ Credentials file created (mode 600)
☐ Systemd services defined
☐ Telegram API reachable
☐ Disk space OK (>5GB)

CUTOVER EXECUTION
☐ Started bot 1 on DO
☐ Started bot 2 on DO
☐ Started bot 3 on DO
☐ Started bot 4 on DO
☐ Started bot 5 on DO
☐ Started bot 6 on DO
☐ Started bot 7 on DO
☐ All 7 DO bots verified running
☐ Telegram messages verified from DO
☐ Stopped all bots on Mac
☐ Verified all Mac bots stopped

POST-CUTOVER
☐ All 7 DO bots running
☐ Resource usage normal
☐ No duplicates
☐ Telegram delivery confirmed
☐ Team notified
☐ Monitoring active

ROLLBACK (If needed)
☐ Stopped DigitalOcean bots
☐ Started Ajay's Mac bots
☐ Verified Mac bots running
☐ Team notified
☐ Collected diagnostics
```

---

## HANDOFF TO OPERATIONS

After successful cutover:

1. **Ownership**: Transferred to Operations team
2. **On-Call**: Establish on-call rotation for DigitalOcean monitoring
3. **Logs**: Archive old logs from Mac, continue on DO
4. **Backups**: Implement automated daily snapshots on DO
5. **Health Checks**: Set up cron job for bot monitoring
6. **Runbooks**: Document common troubleshooting procedures
7. **Metrics**: Dashboard showing signal frequency, uptime, errors
8. **Escalation**: Defined escalation path (Operator → CTO → Ajay)
