# Queue File Sharing Setup

## Problem

Ubuntu signal bots write to `.trade_queue.jsonl` locally.  
Windows MT5 executor needs to read that same queue file.  
Both machines cannot access the same local filesystem.

## Solution: Network Share

The Windows executor reads `.trade_queue.jsonl` from a **Windows network share** that the Ubuntu machine mounts.

### Architecture (with network share)

```
┌──────────────────────────────────────────────────────┐
│  Ubuntu GCP VM (Signal Bots)                         │
│  ├─ btc_bot.py, gold_bot.py, forex_scalper.py       │
│  └─ Writes: .trade_queue.jsonl                       │
│     └─ Via: /mnt/windows/.trade_queue.jsonl          │
│        (SMB mount to Windows share)                  │
└──────────────────────────────────────────────────────┘
                        ↕ (SMB)
                   Network Share
                        ↕
┌──────────────────────────────────────────────────────┐
│  Windows GCP VM (MT5 Executor)                       │
│  ├─ windows_mt5_executor.py (runs continuously)      │
│  ├─ Reads: .trade_queue.jsonl                        │
│  │  From: C:\windows-mt5-execution\                  │
│  │  (local copy or network read)                     │
│  └─ Executes: mt5.order_send()                       │
└──────────────────────────────────────────────────────┘
```

## Setup Instructions

### Windows Side (One-Time Setup)

**Step 1: Create shared folder**

```powershell
# PowerShell as Administrator
mkdir C:\shared-mt5-queue
icacls C:\shared-mt5-queue /grant:r "NETWORK SERVICE:(OI)(CI)F"
icacls C:\shared-mt5-queue /grant:r "Everyone:(OI)(CI)F"
```

**Step 2: Share the folder**

```powershell
# Using smbshare command (Windows Server) or GUI (Windows Desktop)
# GUI: Right-click folder → Share with → Specific people → Everyone (Read/Write)

# Via PowerShell (Server):
New-SmbShare -Name "MT5Queue" -Path "C:\shared-mt5-queue" -FullAccess "Everyone"
```

**Step 3: Verify share is accessible**

```powershell
net share
# Should show: MT5Queue (or your share name)
```

**Step 4: Update executor configuration**

Edit `.env`:
```env
TRADE_QUEUE_PATH=C:\shared-mt5-queue\.trade_queue.jsonl
```

### Ubuntu Side (One-Time Setup)

**Step 1: Install SMB client**

```bash
sudo apt-get install cifs-utils
```

**Step 2: Create mount point**

```bash
sudo mkdir -p /mnt/windows
```

**Step 3: Mount Windows share**

```bash
# Get Windows VM IP address
WINDOWS_IP="<GCP_WINDOWS_VM_IP>"
WINDOWS_USER="Administrator"  # or your Windows username

# Mount with credentials
sudo mount -t cifs "//${WINDOWS_IP}/MT5Queue" /mnt/windows \
  -o username=${WINDOWS_USER},password=<your_password>,uid=$(id -u),gid=$(id -g)
```

**Step 4: Verify mount**

```bash
mount | grep MT5Queue
ls -la /mnt/windows/
```

### Ubuntu Signal Bots (Update Configuration)

**In btc_bot.py, gold_bot.py, forex_scalper.py:**

```python
import os

# Update environment variable or hardcode:
QUEUE_PATH = "/mnt/windows/.trade_queue.jsonl"

# Ensure trade_executor.py uses this path
os.environ["TRADE_QUEUE_PATH"] = QUEUE_PATH
```

Or update `trade_executor.py`:

```python
QUEUE_FILE = os.path.join(
    os.getenv("TRADE_QUEUE_PATH", "/mnt/windows"),
    ".trade_queue.jsonl"
)
```

### Permanent Mount (Ubuntu)

Add to `/etc/fstab` for automatic mount on boot:

```bash
sudo nano /etc/fstab
```

Add line:
```
//${WINDOWS_IP}/MT5Queue /mnt/windows cifs username=Administrator,password=<password>,uid=$(id -u),gid=$(id -g),vers=3.0 0 0
```

Note: This stores password in plaintext. For production, use credential file:

```bash
# Create ~/.smbcredentials
cat > ~/.smbcredentials << EOF
username=Administrator
password=<your_password>
EOF
chmod 600 ~/.smbcredentials

# Update /etc/fstab
//${WINDOWS_IP}/MT5Queue /mnt/windows cifs credentials=~/.smbcredentials,uid=$(id -u),gid=$(id -g),vers=3.0 0 0
```

## Troubleshooting

### "Permission denied" on Ubuntu mount

```bash
# Check mount permissions
mount -l | grep MT5Queue
ls -la /mnt/windows/

# Remount with correct permissions
sudo mount -t cifs "//${WINDOWS_IP}/MT5Queue" /mnt/windows \
  -o username=Administrator,password=<password>,uid=$(id -u),gid=$(id -g),file_mode=0777,dir_mode=0777 -v
```

### "Connection refused" from Ubuntu

```bash
# Verify Windows IP is correct
ping <WINDOWS_IP>

# Verify Windows share is accessible
smbclient -L //${WINDOWS_IP} -U Administrator

# Verify SMB port is open
nc -zv <WINDOWS_IP> 445
```

### Queue file not updating

```bash
# Check if Ubuntu can write to mount
touch /mnt/windows/test.txt
ls -la /mnt/windows/test.txt
rm /mnt/windows/test.txt

# Check if Windows can see it
# Windows: dir C:\shared-mt5-queue
```

### Queue file not found on Windows

```powershell
# Check Windows share
net share MT5Queue

# Check TRADE_QUEUE_PATH in .env
Get-Content .env | findstr QUEUE_PATH

# Test path exists
Test-Path C:\shared-mt5-queue\.trade_queue.jsonl
```

## Alternative: Direct Connection (No Share)

If network share is not feasible:

### Option 1: SSH/SCP Sync

```bash
# Ubuntu cron job (every 5 seconds)
*/5 * * * * * scp /path/to/.trade_queue.jsonl windows_user@windows_ip:C:\shared-queue\

# PowerShell on Windows (monitor + copy)
while ($true) {
  Copy-Item "C:\shared-queue\.trade_queue.jsonl" `
    "C:\windows-mt5-execution\.trade_queue.jsonl" -Force
  Start-Sleep -Seconds 5
}
```

### Option 2: Cloud Storage (S3/GCS/Drive)

```bash
# Ubuntu uploads queue
gsutil cp .trade_queue.jsonl gs://shared-bucket/

# Windows downloads queue
gsutil cp gs://shared-bucket/.trade_queue.jsonl C:\windows-mt5-execution\
```

## Security Considerations

⚠️ **DO NOT**:
- ❌ Expose Windows share to internet (firewall it!)
- ❌ Use weak passwords for share access
- ❌ Store passwords in plaintext in .fstab (use credential file)
- ❌ Grant "Everyone" access in production

✅ **DO**:
- ✅ Firewall port 445 to Ubuntu VM only
- ✅ Use strong Windows password
- ✅ Use credential file for Ubuntu mount
- ✅ Use restricted group (not "Everyone")
- ✅ Monitor share access logs

## Validation Checklist

Before starting executors:

- [ ] Windows share exists: `C:\shared-mt5-queue`
- [ ] Ubuntu can mount: `/mnt/windows` accessible
- [ ] Ubuntu can write: `touch /mnt/windows/test.txt` succeeds
- [ ] Windows can read: `dir C:\shared-mt5-queue` shows file
- [ ] Permissions correct: No "access denied" errors
- [ ] TRADE_QUEUE_PATH set in Windows .env
- [ ] Queue path set in Ubuntu signal bots
- [ ] Both VMs can reach each other on port 445

## Testing

### Ubuntu → Windows Queue Flow

```bash
# Ubuntu: Write test signal
echo '{"symbol":"EURUSD","direction":"BUY","sl":1.082,"tp":1.094,"source":"TEST","ts":'$(date +%s)'}' \
  >> /mnt/windows/.trade_queue.jsonl

# Windows: Verify read
type C:\shared-mt5-queue\.trade_queue.jsonl
# Should show the signal you just wrote
```

### Full Integration Test

1. Ubuntu writes test signal to queue
2. Windows reads and logs it to `.trade_history.jsonl`
3. Windows does NOT place order (signal-only mode)
4. Both machines can verify the signal in history

```bash
# Ubuntu verify
tail /mnt/windows/.trade_queue.jsonl

# Windows verify
Get-Content C:\windows-mt5-execution\.trade_history.jsonl -Tail 5
```

---

**Setup Required**: Network share (SMB) between Ubuntu and Windows VMs  
**Estimated Time**: 15-20 minutes  
**Critical for**: Queue file sharing between signal bots and executor
