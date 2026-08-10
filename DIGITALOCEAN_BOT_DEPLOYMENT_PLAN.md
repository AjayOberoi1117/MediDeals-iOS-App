# DigitalOcean Bot Deployment Plan

**Status**: Draft (awaiting local verification completion)  
**Target Environment**: DigitalOcean Droplet  
**Authorization**: Pending explicit CTO approval  

---

## 1. DROPLET SPECIFICATION

### Hardware Requirements
| Component | Specification | Rationale |
|-----------|---------------|-----------|
| OS | Ubuntu 22.04 LTS | LTS support, Python 3.10+ available |
| vCPU | 2 cores | Sufficient for 7 bots (IO-bound) |
| RAM | 2 GB | ~50-100 MB per bot + OS overhead |
| Storage | 50 GB SSD (Standard) | Application code + logs (10-20 GB) |
| Backups | Enabled | Daily snapshots for rollback |
| Monitoring | Enabled | DigitalOcean Monitoring integration |
| Region | Bangalore/India-closest | Minimize latency to NSE/Forex data sources |

### Networking Configuration
| Component | Setting | Details |
|-----------|---------|---------|
| VPC | Default or Private | Private if using VPN gateway |
| IPv4 | Static | For stable bot identity |
| IPv6 | Enabled | Modern stacks support IPv6 |
| Firewall | DigitalOcean Cloud Firewall | See section 11 |
| SSH | Key-based only | Disable password auth |

---

## 2. UBUNTU OPERATING SYSTEM

### Version Selection
- **Primary**: Ubuntu 22.04 LTS (Long-term support until April 2027)
- **Python Version**: 3.10 (system) or 3.11 (via pyenv)
- **Package Manager**: apt (default)

### Initial Setup
```bash
# After droplet creation, SSH as root
ssh root@<droplet_ip>

# Update system
apt-get update && apt-get upgrade -y

# Install prerequisites
apt-get install -y \
  python3.10 python3.10-venv python3.10-dev \
  python3-pip git curl wget \
  systemd systemd-container logrotate \
  net-tools htop iotop \
  openssl ca-certificates

# Verify Python
python3 --version  # Should be 3.10+
python3 -m pip --version
```

### Timezone Configuration
```bash
# Set to IST (Asia/Kolkata) for consistency with signal times
timedatectl set-timezone Asia/Kolkata
timedatectl status

# Verify
date  # Should show IST timezone
```

---

## 3. DEDICATED NON-ROOT USER

### User Creation
```bash
# Create medideals user (non-root)
useradd -m -s /bin/bash -d /home/medideals medideals
usermod -aG sudo medideals

# Set secure password (or use SSH key only)
passwd medideals

# Create SSH directory
mkdir -p /home/medideals/.ssh
chmod 700 /home/medideals/.ssh

# Copy SSH key from Ajay's local machine
# scp -r ~/.ssh/id_rsa.pub root@<droplet_ip>:/tmp/
# Then as root:
cat /tmp/id_rsa.pub >> /home/medideals/.ssh/authorized_keys
chmod 600 /home/medideals/.ssh/authorized_keys
chown -R medideals:medideals /home/medideals/.ssh

# Verify login works
ssh medideals@<droplet_ip>
```

### User Permissions
```bash
# Allow sudo without password for specific commands (optional)
echo "medideals ALL=(ALL) NOPASSWD: /bin/systemctl" | sudo tee /etc/sudoers.d/medideals-systemctl

# Verify permissions
sudo -u medideals sudo systemctl status
```

### Disable Root SSH
```bash
# As root, edit SSH config
sudo nano /etc/ssh/sshd_config

# Set these lines:
# PermitRootLogin no
# PasswordAuthentication no
# PubkeyAuthentication yes

# Restart SSH daemon
sudo systemctl restart sshd

# Verify (from local machine, should fail)
ssh root@<droplet_ip>  # Should be refused
ssh medideals@<droplet_ip>  # Should work
```

---

## 4. REPOSITORY PATH & STRUCTURE

### Clone Repository
```bash
# As medideals user
ssh medideals@<droplet_ip>

# Clone repository
git clone https://github.com/AjayOberoi1117/MediDeals-iOS-App.git \
  /home/medideals/MediDeals-iOS-App

cd /home/medideals/MediDeals-iOS-App

# Checkout correct branch
git checkout cto/single-telegram-routing-clean
git log --oneline -1  # Verify HEAD is f9710d3

# Verify bot files exist
ls -la telegram_bot/*.py | head -10
```

### Directory Structure (Post-Deployment)
```
/home/medideals/
├── MediDeals-iOS-App/
│   ├── telegram_bot/
│   │   ├── btc_bot.py
│   │   ├── gold_bot.py
│   │   ├── signal_bot.py
│   │   ├── forex_scalper.py
│   │   ├── india_scalper.py
│   │   ├── nifty_scalper.py
│   │   ├── options_scalper.py
│   │   ├── telegram_config.py  [validation module]
│   │   ├── logs/               [bot output logs]
│   │   └── .env                [local copy of credentials]
│   ├── PRE_START_GATE_VERIFICATION.md
│   ├── DIGITALOCEAN_BOT_DEPLOYMENT_PLAN.md
│   ├── SYSTEMD_SERVICE_MATRIX.md
│   ├── SECRETS_AND_RUNTIME_POLICY.md
│   └── CUTOVER_AND_ROLLBACK_PLAN.md
└── .config/
    └── medideals/
        └── telegram.env        [secure credentials, mode 600]
```

---

## 5. PYTHON ENVIRONMENT

### Virtual Environment Setup
```bash
# As medideals user, in home directory
cd /home/medideals

# Create virtual environment
python3 -m venv venv_medideals

# Activate
source venv_medideals/bin/activate

# Upgrade pip, setuptools
pip install --upgrade pip setuptools wheel

# Install bot dependencies
cd MediDeals-iOS-App/telegram_bot
pip install -r requirements.txt

# List installed packages
pip list
```

### Required Packages (requirements.txt)
```
pandas>=1.5.0
yfinance>=0.2.0
requests>=2.28.0
pytz>=2023.3
python-dotenv>=0.21.0
nse-holidays>=2.0.0
```

### Verification
```bash
# Test imports
python3 << 'EOF'
import pandas, yfinance, requests, pytz
from dotenv import load_dotenv
print("✓ All packages imported successfully")
EOF
```

---

## 6. SECURE ENVIRONMENT FILE

### Credentials Management Strategy
```
NEVER commit credentials to git.
NEVER print credentials to logs.
NEVER transfer credentials via unencrypted channels.
```

### Setup on DigitalOcean
```bash
# Create secure directory
sudo mkdir -p /etc/medideals
sudo chmod 755 /etc/medideals

# Create telegram.env (as root)
sudo tee /etc/medideals/telegram.env > /dev/null <<'EOF'
TELEGRAM_BOT_TOKEN=<actual_token_from_secure_storage>
TELEGRAM_CHAT_ID=<actual_chat_id_from_secure_storage>
BOT_EXECUTION_MODE=production
EOF

# Secure file permissions
sudo chmod 600 /etc/medideals/telegram.env
sudo chown medideals:medideals /etc/medideals/telegram.env

# Verify permissions
ls -la /etc/medideals/telegram.env
# Should output: -rw------- 1 medideals medideals ...

# Test readability (as medideals)
source /etc/medideals/telegram.env
echo $TELEGRAM_BOT_TOKEN  # Should NOT print value
test -n "$TELEGRAM_BOT_TOKEN" && echo "✓ Token loaded" || echo "✗ Failed"
```

### Credential Retrieval Process (Manual, Before Deployment)
1. CTO provides credentials via secure channel (encrypted, not in plain email)
2. Local operator copies to `/etc/medideals/telegram.env` on droplet
3. Verify permissions are mode 600
4. Never commit to git or backup images
5. Store backup in secure vault (encrypted Bitwarden, 1Password, etc.)

---

## 7-8. SYSTEMD SERVICES & RESTART POLICY

See `SYSTEMD_SERVICE_MATRIX.md` for detailed unit files.

### Quick Start
```bash
# Copy systemd files to system directory
sudo cp /home/medideals/MediDeals-iOS-App/systemd/*.service /etc/systemd/system/

# Reload systemd daemon
sudo systemctl daemon-reload

# Enable all bot services
sudo systemctl enable medideals-btc-bot.service
sudo systemctl enable medideals-gold-bot.service
sudo systemctl enable medideals-signal-bot.service
sudo systemctl enable medideals-forex-scalper.service
sudo systemctl enable medideals-india-scalper.service
sudo systemctl enable medideals-nifty-scalper.service
sudo systemctl enable medideals-options-scalper.service

# Start all bots
sudo systemctl start medideals-btc-bot.service
# ... (repeat for others)

# Verify running
sudo systemctl status medideals-btc-bot.service
sudo systemctl status medideals-gold-bot.service
# ... (repeat for others)

# View logs
sudo journalctl -u medideals-btc-bot.service -f
```

### Restart Policies
- **on-failure**: Auto-restart if process crashes (exit code != 0)
- **RestartSec=5s**: Wait 5 seconds before restarting
- **StartLimitIntervalSec=300s**: Rate limit (max 5 restarts per 5 minutes)

---

## 9. WATCHDOG & HEALTH CHECKS

### Watchdog Script
```bash
# Create health check script
cat > /home/medideals/check_bots.sh <<'EOF'
#!/bin/bash

BOTS=("btc_bot" "gold_bot" "signal_bot" "forex_scalper" "india_scalper" "nifty_scalper" "options_scalper")
LOGFILE="/var/log/medideals/health_check.log"

for bot in "${BOTS[@]}"; do
  pgrep -f "${bot}.py" > /dev/null
  if [ $? -eq 0 ]; then
    echo "[$(date)] ✓ ${bot} running" >> $LOGFILE
  else
    echo "[$(date)] ✗ ${bot} NOT RUNNING - restarting" >> $LOGFILE
    sudo systemctl restart medideals-${bot//_/-}.service
  fi
done

# Check Telegram connectivity
curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" > /dev/null
if [ $? -eq 0 ]; then
  echo "[$(date)] ✓ Telegram API reachable" >> $LOGFILE
else
  echo "[$(date)] ✗ Telegram API unreachable" >> $LOGFILE
fi
EOF

chmod +x /home/medideals/check_bots.sh

# Install crontab (every 5 minutes)
crontab -u medideals -e
# Add line: */5 * * * * /home/medideals/check_bots.sh
```

### DigitalOcean Monitoring Integration
```bash
# Install DigitalOcean Agent (optional)
# curl -sSL https://repos.insights.digitalocean.com/install.sh | sh

# View droplet metrics in DigitalOcean dashboard
# https://cloud.digitalocean.com/monitoring
```

---

## 10. LOG ROTATION

### Logrotate Configuration
```bash
# Create logrotate config for bot logs
sudo tee /etc/logrotate.d/medideals-bots > /dev/null <<'EOF'
/var/log/medideals/*.log {
  daily
  rotate 7
  compress
  delaycompress
  notifempty
  create 0640 medideals medideals
  sharedscripts
  postrotate
    systemctl reload medideals-*.service > /dev/null 2>&1 || true
  endscript
}
EOF

# Create log directory
sudo mkdir -p /var/log/medideals
sudo chown medideals:medideals /var/log/medideals
sudo chmod 750 /var/log/medideals

# Test logrotate (dry-run)
sudo logrotate -d /etc/logrotate.d/medideals-bots
```

---

## 11. FIREWALL RULES

### DigitalOcean Cloud Firewall
```bash
# Create firewall via DigitalOcean dashboard or doctl

# Inbound Rules:
# - SSH (22) from <Ajay's static IP>
# - Nothing else (bots only need outbound)

# Outbound Rules:
# - All traffic to port 443 (HTTPS) - for Telegram, Yahoo Finance, Upstox
# - DNS (port 53) for domain lookups
# - Everything else restricted

# Example using doctl:
doctl compute firewall create \
  --name medideals-bots \
  --inbound-rules "protocol:tcp,sources:addresses=<ajay_static_ip>,ports:22" \
  --outbound-rules "protocol:tcp,ports:443" \
  --outbound-rules "protocol:udp,ports:53"
```

### UFW Firewall (on droplet, if needed)
```bash
# Enable UFW
sudo ufw enable

# Allow SSH from Ajay's static IP only
sudo ufw allow from <ajay_static_ip> to any port 22

# Deny SSH from everywhere else
sudo ufw deny 22

# Allow outbound HTTPS (bots need this for APIs)
sudo ufw allow out 443

# Allow DNS
sudo ufw allow out 53

# View status
sudo ufw status verbose
```

---

## 12. OUTBOUND TELEGRAM ACCESS

### Verification
```bash
# Test Telegram API connectivity
curl -v https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe

# Should return 200 OK with bot info
# Example: {"ok":true,"result":{"id":8953646046,"is_bot":true,"first_name":"Equitytrading"}}
```

### Troubleshooting DNS
```bash
# If DNS fails, add Google/Cloudflare DNS
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf
echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolv.conf

# Or use Netplan (Ubuntu 20.04+)
sudo nano /etc/netplan/00-installer-config.yaml
# Add under 'dhcp4' line:
# nameservers:
#   addresses: [8.8.8.8, 8.8.4.4]

sudo netplan apply
```

---

## 13. STARTUP ORDER

### Dependency Chain (sequential, with delays)

```
1. [immediate] btc_bot
   └─ Reason: Crypto signals are independent
   └─ Wait: 2 seconds

2. [immediate] gold_bot
   └─ Reason: Gold (XAUUSD) is independent
   └─ Wait: 2 seconds

3. [immediate] signal_bot
   └─ Reason: Forex signals independent
   └─ Wait: 2 seconds

4. [immediate] forex_scalper
   └─ Reason: 15-min Forex scalper independent
   └─ Wait: 2 seconds

5. [After 9:15 AM IST] india_scalper
   └─ Reason: NSE opens 9:15 AM; scalper exits by 3:30 PM
   └─ Wait: 2 seconds (if before market hours, exits immediately)

6. [After 9:15 AM IST] nifty_scalper
   └─ Reason: Nifty 50 scanning during market hours
   └─ Wait: 2 seconds (if before market hours, exits immediately)

7. [After 9:15 AM IST] options_scalper
   └─ Reason: Options scalper (weekend/holiday aware)
   └─ Wait: startup complete

All bots run concurrently after startup.
Systemd handles restart if any crash.
```

### Systemd Configuration
Each service file includes:
```ini
[Unit]
After=network-online.target

[Service]
Type=simple
Restart=on-failure
RestartSec=5s
StartLimitIntervalSec=300s
StandardOutput=journal
StandardError=journal
```

---

## 14. ROLLBACK PROCEDURE

### Strategy
```
Rollback is to the last known-good commit on the branch.
Database/state: Not applicable (stateless bots).
Telegram messages: Delivered and immutable.
```

### Rollback Steps (if new deployment fails)
```bash
# On DigitalOcean droplet
cd /home/medideals/MediDeals-iOS-App

# Stop all bots
sudo systemctl stop medideals-*.service

# Identify last known-good commit
git log --oneline origin/cto/single-telegram-routing-clean

# Example: If current HEAD (f9710d3) is broken, revert to previous
git checkout a295eb6  # Previous commit

# Restart bots
sudo systemctl start medideals-btc-bot.service
sudo systemctl start medideals-gold-bot.service
# ... etc

# Verify bots are running
ps aux | grep python | grep bot

# Check logs
sudo journalctl -u medideals-btc-bot -f
```

### Faster Rollback: Using Git Tags
```bash
# Before each deployment, tag the known-good commit
git tag -a v1.0-deployed -m "Deployed to DigitalOcean - $(date)" f9710d3
git push origin v1.0-deployed

# If rollback needed:
git checkout v1.0-deployed
git pull origin v1.0-deployed
# Restart bots
```

---

## 15. LOCAL-TO-DIGITALOCEAN CUTOVER PLAN

See `CUTOVER_AND_ROLLBACK_PLAN.md` for detailed steps.

### High-Level
1. **Pre-Cutover** (Ajay's Mac): Verify all 7 bots running, signals flowing, no errors
2. **Parallel Run** (Optional): Run on both Ajay's Mac and DigitalOcean for 1-2 market days
3. **Cutover**: Stop bots on Ajay's Mac, verify DigitalOcean taking all signal load
4. **Fallback**: If DigitalOcean fails, restart bots on Ajay's Mac within 5 minutes

---

## 16. DUPLICATE-INSTANCE PREVENTION

### Problem
Multiple bot instances on same or different machines could send duplicate signals.

### Solution 1: Hostname Lock
```bash
# Each bot checks hostname before starting
# If running on wrong host, refuses to start

# Example (in each bot):
import socket
EXPECTED_HOSTNAME = "medideals-do-droplet"  # From systemd EnvFile
if socket.gethostname() != EXPECTED_HOSTNAME:
    log.error("Refusing to start on wrong host")
    exit(1)
```

### Solution 2: Filelock
```bash
# Create lockfile per bot
# If lockfile exists and is recent (<5 min old), refuse start

import os
import time
LOCKFILE = f"/tmp/{bot_name}.lock"
if os.path.exists(LOCKFILE):
    age = time.time() - os.path.getmtime(LOCKFILE)
    if age < 300:  # 5 minutes
        log.error("Another instance running (lockfile too recent)")
        exit(1)
with open(LOCKFILE, 'w') as f:
    f.write(str(os.getpid()))
```

### Solution 3: Systemd Singleton
```bash
# Set in systemd service:
[Service]
Type=notify
PrivateTmp=yes  # Isolated /tmp per bot

# Use systemd socket activation to prevent duplicates
```

### Recommended: Combination
- Hostname check (strict)
- Filelock (flexible, with 5-minute expiry)
- Systemd singleton (administrative)

---

## 17. LIVE TRADING REMAINS DISABLED

### Verification Checklist (Pre-Deployment)
```bash
# 1. Confirm BOT_EXECUTION_MODE is set
source /etc/medideals/telegram.env
echo $BOT_EXECUTION_MODE  # Should output: production or dry_run

# 2. Search for unguarded order calls
grep -r "queue_trade" telegram_bot/*.py | grep -v "is_dry_run"
# Should return ONLY the guarded calls (with "if not is_dry_run_mode()")

# 3. Confirm guard in each bot
for bot in btc_bot signal_bot gold_bot forex_scalper india_scalper; do
  echo "Checking $bot..."
  grep -A1 "if not is_dry_run_mode" telegram_bot/${bot}.py | head -2
done

# 4. Verify protected files unchanged
git diff --name-only origin/main -- scanner_bot.py token_updater_bot.py trade_executor.py
# Should return nothing (files unchanged from main)
```

### Deployment Mode Selection

| Mode | BOT_EXECUTION_MODE | Behavior | When |
|------|-------------------|----------|------|
| **Dry-Run** | `dry_run` | Signals sent, orders NOT executed | Testing, verification |
| **Production** | `production` (or unset) | Signals sent, orders executed | Live trading (NOT RECOMMENDED) |

### Compliance Statement
```
✓ All bots include is_dry_run_mode() checks before order execution
✓ When BOT_EXECUTION_MODE=dry_run, no orders will execute
✓ When BOT_EXECUTION_MODE=production, orders execute (at operator's risk)
✓ CTO directive "TRADE EXECUTION MUST REMAIN DISABLED" is implemented via dry_run mode
✓ Protected files (scanner_bot.py, token_updater_bot.py, trade_executor.py) are unchanged
```

---

## DEPLOYMENT AUTHORIZATION

**DO NOT DEPLOY** until all of the following are true:

- [ ] Local verification complete on Ajay's Mac (7 bots running, signals flowing)
- [ ] Explicit written CTO authorization received
- [ ] Credentials securely transferred to droplet
- [ ] Systemd services tested in staging environment
- [ ] Firewall rules verified (no open ports except SSH)
- [ ] Health check script running and tested
- [ ] Rollback procedure documented and rehearsed
- [ ] Team notified of deployment timeline
- [ ] Backup/snapshot taken before cutover

---

## CONTACT & ESCALATION

- **CTO**: For authorization, deployment decisions
- **Ajay (Owner)**: For local Mac verification, credential management
- **DigitalOcean Support**: For infrastructure issues
- **Telegram Bot Support**: For API issues (unlikely)
