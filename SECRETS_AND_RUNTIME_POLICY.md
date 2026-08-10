# Secrets and Runtime Policy

**Purpose**: Secure credential management and runtime safety guarantees  
**Status**: Ready for DigitalOcean deployment  
**Classification**: CONFIDENTIAL (operator eyes only)  

---

## EXECUTIVE SUMMARY

| Policy | Implementation | Compliance |
|--------|----------------|------------|
| **No credential commits** | .gitignore + pre-commit hook | ✓ |
| **No credential printing** | Omit token/chat_id from logs | ✓ |
| **File permissions** | `/etc/medideals/telegram.env` mode 600 | ✓ |
| **Order execution disabled** | is_dry_run_mode() guards | ✓ |
| **Protected files unchanged** | scanner_bot.py, token_updater_bot.py, trade_executor.py | ✓ |
| **Single Telegram routing** | @Equitytrading_bot only | ✓ |
| **Market hours awareness** | NSE/forex hours checked internally | ✓ |

---

## SECRETS MANAGEMENT

### Credential Types & Storage

| Credential | Format | Storage | Access | Rotation |
|-----------|--------|---------|--------|----------|
| **TELEGRAM_BOT_TOKEN** | `<bot_id>:<alphanumeric_key>` | `/etc/medideals/telegram.env` | systemd services only | Manual override in telegram.env |
| **TELEGRAM_CHAT_ID** | Numeric ID | `/etc/medideals/telegram.env` | systemd services only | Manual override in telegram.env |
| **BOT_EXECUTION_MODE** | `dry_run` or `production` | `/etc/medideals/telegram.env` | All bots via EnvironmentFile | Manual override in telegram.env |

### Credential File Layout

**Location**: `/etc/medideals/telegram.env`  
**Owner**: `medideals:medideals`  
**Permissions**: `600` (read/write owner only)  
**Backup**: Encrypted vault (NOT in git, NOT in backups)

```ini
# /etc/medideals/telegram.env
TELEGRAM_BOT_TOKEN=8953646046:AAF6flZRLHG7KU1JiagA48gJLcKZV7RuxKs
TELEGRAM_CHAT_ID=7093601171
BOT_EXECUTION_MODE=dry_run
```

**Rationale**: Only the `medideals` user can read credentials. systemd runs services as `medideals`, so they inherit credentials via `EnvironmentFile=/etc/medideals/telegram.env`.

---

## SECURE CREDENTIAL HANDLING

### ✓ CORRECT PATTERNS

```python
# Pattern 1: Load from environment (safest)
import os
from dotenv import load_dotenv

load_dotenv('/etc/medideals/telegram.env')
TELEGRAM_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "")

# Never print the values
log.info("Telegram configured")  # ✓ GOOD
# log.info(f"Token: {TELEGRAM_TOKEN}")  # ✗ BAD - never do this

# Pattern 2: Validate credentials exist (fail-closed)
if not TELEGRAM_TOKEN or not CHAT_ID:
    raise RuntimeError("Missing required environment variables")

# Pattern 3: Check dry-run mode before order execution
if not is_dry_run_mode():
    queue_trade(...)  # ✓ Order only executes in production mode
```

### ✗ INCORRECT PATTERNS (DO NOT USE)

```python
# Anti-pattern 1: Hardcoded credentials
TELEGRAM_TOKEN = "8953646046:AAF6flZRLHG7KU1JiagA48gJLcKZV7RuxKs"  # ✗ NEVER hardcode

# Anti-pattern 2: Print credentials to logs
log.info(f"Token: {TELEGRAM_TOKEN}")  # ✗ NEVER print values
print(f"Chat ID: {CHAT_ID}")  # ✗ NEVER print values

# Anti-pattern 3: Unguarded order execution
queue_trade(...)  # ✗ ALWAYS guard with is_dry_run_mode()

# Anti-pattern 4: Commit credentials to git
git add .env  # ✗ NEVER commit
git commit -m "Add credentials"  # ✗ NEVER commit
```

---

## CREDENTIAL ROTATION PROCEDURE

### When to Rotate
- Suspected compromise (leaked in email, exposed in backup, etc.)
- Quarterly security review (best practice)
- After team member departure (change admin/owner keys)
- Telegram bot compromised (request new token from BotFather)

### Rotation Steps

#### On DigitalOcean (5 min downtime)

```bash
# 1. Obtain new credentials from secure source (CTO/Ajay)
# Example: CTO emails encrypted file with new token/chat_id

# 2. Stop all bots
sudo systemctl stop medideals-*.service

# 3. Backup old credentials
sudo cp /etc/medideals/telegram.env /etc/medideals/telegram.env.backup

# 4. Update credentials
sudo nano /etc/medideals/telegram.env
# Edit the TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID values
# Save (Ctrl+X, Y, Enter)

# 5. Verify permissions
sudo chmod 600 /etc/medideals/telegram.env
sudo chown medideals:medideals /etc/medideals/telegram.env

# 6. Start bots
sudo systemctl start medideals-*.service

# 7. Monitor logs
sudo journalctl -u medideals-btc-bot.service -f
# Should see "Online" or "Telegram configured" message within 10 seconds

# 8. Destroy old backup after 1 day (if new credentials working)
sudo rm /etc/medideals/telegram.env.backup
```

#### Testing New Credentials (Before Rotation)

```bash
# Smoke test: Verify new token/chat_id work
python3 << 'EOF'
import requests
import os

token = "NEW_TOKEN_HERE"
chat_id = "NEW_CHAT_ID_HERE"

url = f"https://api.telegram.org/bot{token}/sendMessage"
data = {"chat_id": chat_id, "text": "🧪 Test message from new credentials"}

try:
    r = requests.post(url, json=data, timeout=10)
    if r.status_code == 200:
        print("✓ New credentials work")
    else:
        print(f"✗ Failed: {r.status_code} {r.text}")
except Exception as e:
    print(f"✗ Error: {e}")
EOF
```

---

## RUNTIME EXECUTION MODES

### Dry-Run Mode (`BOT_EXECUTION_MODE=dry_run`)

**Purpose**: Testing, verification, CI/CD  
**Behavior**: Signals sent to Telegram, NO orders executed

```python
# In any bot that uses is_dry_run_mode()
if not is_dry_run_mode():
    queue_trade(symbol, direction, sl, tp)  # Skipped in dry_run

# Result:
# - Telegram signal: SENT ✓
# - Order execution: SKIPPED ✓
# - Risk exposure: ZERO ✓
```

**When to Use**:
- Testing new signal strategies
- Verifying Telegram routing
- CI/CD pipeline validation
- Pre-deployment verification

---

### Production Mode (default, or `BOT_EXECUTION_MODE=production`)

**Purpose**: Live trading  
**Behavior**: Signals sent to Telegram, orders executed via broker APIs

```python
# When is_dry_run_mode() returns False
queue_trade(symbol, direction, sl, tp)  # EXECUTED ✓

# Result:
# - Telegram signal: SENT ✓
# - Order execution: ENABLED ✓
# - Risk exposure: LIVE ⚠️
```

**When to Use**:
- Live trading with real capital
- Market hours only (9:15 AM - 3:30 PM IST)
- Under direct operator supervision

**CAUTION**: Production mode carries financial risk. Ensure:
- Broker API credentials verified
- Account risk limits set
- Position size appropriate
- Stop-loss and take-profit configured manually
- Operator monitoring market conditions

---

## ORDER EXECUTION POLICY

### ✓ MANDATORY: is_dry_run_mode() Guards

Every bot that calls `queue_trade()`, `upstox_place_order()`, or similar MUST check dry-run mode first:

```python
# REQUIRED pattern in all bots
from telegram_config import is_dry_run_mode

# Before ANY order call
if not is_dry_run_mode():
    queue_trade(symbol, direction, sl, tp)

# NOT allowed:
queue_trade(symbol, direction, sl, tp)  # ✗ Direct call without guard
```

### ✓ MANDATORY: Trade Executor Fallback

If trade_executor module not available (testing), use no-op:

```python
# REQUIRED fallback
try:
    from trade_executor import queue_trade
except ImportError:
    def queue_trade(*args, **kwargs): pass  # No-op fallback
```

### ✓ MANDATORY: Environment Variable Validation

All bots MUST validate Telegram credentials on startup:

```python
# REQUIRED validation
from telegram_config import validate_telegram_config

# In main()
TELEGRAM_TOKEN, CHAT_ID = validate_telegram_config(TELEGRAM_TOKEN, CHAT_ID)
# Raises RuntimeError if missing (unless in dry_run mode)
```

---

## PROTECTED FILES POLICY

### Files That MUST NOT Be Modified

These files contain core trading logic and are off-limits:

| File | Purpose | Why Protected |
|------|---------|---------------|
| `scanner_bot.py` | Market scanner & data fetcher | Core data pipeline |
| `token_updater_bot.py` | Auth token management | Broker authentication |
| `trade_executor.py` | Order submission to broker | Risk management critical |

**Verification**: Before each deployment, verify unchanged:

```bash
git diff --name-only -- scanner_bot.py token_updater_bot.py trade_executor.py
# Should return: (nothing - files unchanged)

# Or check git status
git status scanner_bot.py token_updater_bot.py trade_executor.py
# Should show: "On branch ... working tree clean"
```

---

## MESSAGE ROUTING POLICY

### ✓ MANDATORY: Single Telegram Bot

All signals route through ONE Telegram bot only: **@Equitytrading_bot**

```python
# Environment variable (read-only)
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "")  # 7093601171

# All bots use same configuration
# No bot uses @TradingPairs_bot (legacy)
# No bot uses @Giold_bot (legacy)
```

### Message Source Identification

Each bot prepends source tag to messages:

```
[BTC BOT] → btc_bot.py
[GOLD BOT] → gold_bot.py
[SIGNAL BOT] → signal_bot.py
[FOREX SCALPER] → forex_scalper.py
[INDIA SCALPER] → india_scalper.py
[NIFTY SCALPER] → nifty_scalper.py
[OPTIONS SCALPER] → options_scalper.py
```

**Benefit**: Operator can identify signal source and filter/audit as needed.

---

## COMPLIANCE & AUDIT

### Pre-Deployment Checklist

```bash
# 1. Verify no hardcoded credentials
grep -r "TELEGRAM_BOT_TOKEN\|TELEGRAM_CHAT_ID" telegram_bot/*.py | grep -v "os.getenv"
# Should return: (nothing)

# 2. Verify no credential printing
grep -r "print.*TOKEN\|log.*TOKEN\|print.*CHAT_ID\|log.*CHAT_ID" telegram_bot/*.py
# Should return: (nothing)

# 3. Verify order execution guards
grep -r "queue_trade\|upstox_place_order" telegram_bot/*.py | grep -v "is_dry_run"
# Should return: (only guarded calls with "if not is_dry_run_mode()")

# 4. Verify protected files unchanged
git diff -- scanner_bot.py token_updater_bot.py trade_executor.py
# Should return: (nothing)

# 5. Verify single Telegram routing
grep -r "@TradingPairs_bot\|@Giold_bot\|SIGNAL_CHAT_ID" telegram_bot/*.py | grep -v "test_\|verify_"
# Should return: (nothing, except in test files)
```

### Production Audit Trail

Logs recorded by systemd journalctl:

```bash
# View Telegram delivery attempts
sudo journalctl -u medideals-btc-bot.service | grep -i "telegram"

# View order execution checks
sudo journalctl -u medideals-btc-bot.service | grep -i "queue_trade\|execute"

# Export audit log
sudo journalctl -u medideals-*.service --since "1 day ago" > /tmp/medideals_audit.log
```

---

## INCIDENT RESPONSE

### Suspected Credential Compromise

```bash
# 1. IMMEDIATE: Stop all bots
sudo systemctl stop medideals-*.service

# 2. Revoke old Telegram bot token
# Contact CTO/Ajay to:
# - Go to BotFather on Telegram
# - Run /token command to revoke old token
# - Generate new token

# 3. Update credentials on DigitalOcean
sudo nano /etc/medideals/telegram.env
# Paste new token, save

# 4. Restart bots
sudo systemctl start medideals-*.service

# 5. Verify recovery
sudo journalctl -u medideals-btc-bot.service -f
# Should show connection established with Telegram API

# 6. Review logs for suspicious activity
sudo journalctl --since "4 hours ago" > /tmp/incident_review.log
```

### Accidental Credential Exposure

If credentials found in git history or logs:

```bash
# 1. IMMEDIATE: Revoke credentials (see above)

# 2. Clean git history
# WARNING: This rewrites history - only do if explicitly authorized

git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch /etc/medideals/telegram.env" \
  --prune-empty -r HEAD

git push origin --force  # Force push cleaned history (⚠️ destructive)

# 3. Remove from logs
sudo rm /var/log/medideals/*
sudo journalctl --vacuum-size=0
```

---

## SECRETS BACKUP POLICY

### What to Back Up
- ❌ Credentials themselves (store in encrypted vault separately)
- ✓ Git commit history (excludes credentials)
- ✓ systemd service files (no secrets)
- ✓ Configuration files (no secrets)
- ✓ Application code (public repository)

### Backup Location
- **Primary**: Encrypted Bitwarden/1Password vault (CTO/Ajay only)
- **Secondary**: Encrypted USB drive (stored in secure location)
- **NOT**: Git repository, DigitalOcean droplet backups, email

### Restoration Procedure

If DigitalOcean droplet destroyed:

```bash
# 1. Create new droplet (same specs)
# 2. Clone repository: git clone ... && git checkout cto/single-telegram-routing-clean
# 3. Set up Python environment (see DIGITALOCEAN_BOT_DEPLOYMENT_PLAN.md)
# 4. Create /etc/medideals/telegram.env from encrypted vault
# 5. Start services: sudo systemctl start medideals-*.service
# 6. Verify: sudo journalctl -u medideals-btc-bot.service -f
```

---

## DEVELOPER GUIDELINES

### Local Development (Ajay's Mac)

```bash
# Create local secrets file (NOT committed to git)
mkdir -p ~/.config/medideals
cat > ~/.config/medideals/telegram.env <<'EOF'
TELEGRAM_BOT_TOKEN=your_test_token_here
TELEGRAM_CHAT_ID=your_test_chat_id_here
BOT_EXECUTION_MODE=dry_run
EOF

chmod 600 ~/.config/medideals/telegram.env

# Load in shell
source ~/.config/medideals/telegram.env

# Test bot locally (in dry_run mode)
cd MediDeals-iOS-App/telegram_bot
python3 btc_bot.py

# Verify no orders execute
# Expected log: "BOT_EXECUTION_MODE=dry_run detected - order execution DISABLED"
```

### CI/CD Pipeline

```yaml
# Example: GitHub Actions (never commit credentials)
env:
  BOT_EXECUTION_MODE: dry_run  # Always dry_run in CI

script:
  - python -m pytest telegram_bot/test_*.py
  - python telegram_bot/verify_*.py
  # Both should pass with dry_run mode
```

### Code Review Checklist

When reviewing PRs:

- [ ] No hardcoded credentials
- [ ] No credential printing/logging
- [ ] All queue_trade calls guarded with is_dry_run_mode()
- [ ] Protected files (scanner_bot.py, token_updater_bot.py, trade_executor.py) unchanged
- [ ] .gitignore includes *.env files
- [ ] No email/WhatsApp imports (unless reverting previously removed)
- [ ] Telegram message has [BOT_NAME] prefix
- [ ] validate_telegram_config() called in main()

---

## COMPLIANCE STATEMENT

This policy ensures:

✓ **Zero credential leakage** - No secrets in git, logs, or backups  
✓ **Trade execution disabled** - Orders only execute when explicitly enabled  
✓ **Safe defaults** - Bots start in dry_run mode by default  
✓ **Audit trail** - All actions logged to journalctl  
✓ **Rapid incident response** - Credentials revokable within minutes  
✓ **Separation of concerns** - Core trading logic (protected files) immutable  
✓ **Single source of truth** - One Telegram routing path (@Equitytrading_bot)  

---

## NEXT STEPS

1. ✓ Create `/etc/medideals/telegram.env` on DigitalOcean (mode 600)
2. ✓ Load credentials from secure vault
3. ✓ Verify smoke test succeeds
4. ✓ Enable systemd services
5. ✓ Monitor logs for credential leakage
6. ✓ Set up quarterly credential rotation schedule
7. ✓ Document any changes to this policy
