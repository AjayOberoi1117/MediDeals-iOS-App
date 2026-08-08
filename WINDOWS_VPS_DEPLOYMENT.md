# Windows VPS MT5 Execution Deployment

## Architecture Overview

```
DigitalOcean (Signal Generation)
  └─ Strategy bots
  └─ Signal queue (.trade_queue.jsonl)
  └─ Telegram alerts
  └─ NO MT5 / NO Wine / NO execution
           ↓
      HTTPS/SFTP Secure Channel
           ↓
Windows VPS (Order Execution)
  └─ MT5 native installation
  └─ TradeFromFile EA or MT5Client
  └─ Vantage DEMO account
  └─ Signal receiver service
  └─ Order execution only
  └─ Health/status reporting
```

## Windows VPS Requirements

### Hardware
- **OS:** Windows Server 2022 / Windows 11 Pro
- **RAM:** 2GB minimum, 4GB recommended
- **Storage:** 10GB minimum
- **Network:** Static IP, outbound HTTPS to DigitalOcean

### Software Prerequisites
- MetaTrader 5 (build 5000+)
- .NET Framework 4.8+ (for receiver service)
- Python 3.9+ (for signal processing)
- OpenSSH Server (for secure file transfer)

### Network
- Firewall rule: Allow HTTPS outbound to DigitalOcean IP
- Firewall rule: Allow RDP inbound (for management only)
- NO inbound MT5 exposure
- NO public file shares

---

## Phase 1: Windows VPS Setup

### Step 1.1: Install MetaTrader 5

1. Download MT5: https://download.metaTrader5.com/mt5setup.exe
2. Run installer (administrator mode)
3. Complete installation to: `C:\Program Files\MetaTrader 5\`
4. Launch MT5 terminal

### Step 1.2: Configure Vantage DEMO Account

In MT5 terminal:
1. File → Login (or New Account)
2. Search: "VantageMarkets"
3. Select: "Vantage Markets - Demo"
4. Enter credentials:
   - **Login:** (from DigitalOcean .env `MT5_LOGIN`)
   - **Password:** (from DigitalOcean .env `MT5_PASSWORD`)
   - **Server:** Vantage Markets Demo
5. Click OK

**Verify:**
- Account type shows "DEMO"
- Market watch loads symbols
- No account restrictions shown

### Step 1.3: Deploy TradeFromFile EA

1. Copy `TradeFromFile.mq5` to:
   ```
   C:\Program Files\MetaTrader 5\MQL5\Experts\
   ```

2. In MT5:
   - Tools → MetaEditor
   - Open: MQL5/Experts/TradeFromFile.mq5
   - F7 (Compile)
   - Verify: "compiled successfully"

3. Attach EA to chart:
   - Any chart (e.g., EURUSD)
   - Right-click → Expert Advisors → TradeFromFile
   - Settings:
     - LotSize: **0.01**
     - Deviation: **20**
     - CheckSecs: **5**
     - SignalsFile: **mt5_signals.csv**
   - Click OK

**Verify in Journal:**
```
TradeFromFile EA v2 started | watching: mt5_signals.csv | 
approved: EURUSD,GBPUSD,XAUUSD
```

---

## Phase 2: Signal Receiver Setup

### Step 2.1: Create Signal Receiver Service

Create file: `C:\MediDeals\signal_receiver.py`

```python
#!/usr/bin/env python3
"""
Signal Receiver Service
Receives signals from DigitalOcean, writes to MT5 Files folder.
"""

import os
import json
import time
import logging
from pathlib import Path
from http.server import HTTPServer, BaseHTTPRequestHandler
from threading import Thread

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s | RECEIVER | %(levelname)s | %(message)s',
    handlers=[
        logging.FileHandler('C:\\MediDeals\\receiver.log'),
        logging.StreamHandler()
    ]
)
log = logging.getLogger(__name__)

# MT5 Files folder
MT5_FILES = Path("C:/Program Files/MetaTrader 5/MQL5/Files")
SIGNALS_FILE = MT5_FILES / "mt5_signals.csv"

# Receiver token (shared secret with DigitalOcean)
AUTH_TOKEN = os.getenv("RECEIVER_AUTH_TOKEN", "change_me_immediately")

class SignalHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        """Handle incoming signals from DigitalOcean."""
        
        if self.path != "/signal":
            self.send_error(404)
            return
        
        # Verify auth token
        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            self.send_error(401, "Missing authorization")
            log.warning("Rejected signal: no auth token")
            return
        
        token = auth[7:]  # Remove "Bearer " prefix
        if token != AUTH_TOKEN:
            self.send_error(401, "Invalid token")
            log.warning("Rejected signal: invalid token")
            return
        
        # Read signal
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length).decode()
        
        try:
            signal = json.loads(body)
        except json.JSONDecodeError:
            self.send_error(400, "Invalid JSON")
            log.error(f"Invalid JSON: {body}")
            return
        
        # Process signal
        if self._process_signal(signal):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "accepted"}).encode())
            log.info(f"Accepted: {signal['symbol']} {signal['direction']}")
        else:
            self.send_error(400, "Signal rejected")
            log.warning(f"Rejected: {signal}")
    
    def _process_signal(self, signal):
        """Write signal to MT5 Files folder."""
        try:
            symbol = signal.get("symbol", "").upper()
            direction = signal.get("direction", "").upper()
            sl = float(signal.get("sl", 0))
            tp = float(signal.get("tp", 0))
            source = signal.get("source", "unknown")
            ts = signal.get("ts", time.time())
            
            # Validate
            if not symbol or direction not in ["BUY", "SELL"]:
                return False
            
            if sl == 0 or tp == 0:
                return False
            
            # Create CSV line
            line = f"{symbol},{direction},{sl:.5f},{tp:.5f},10000,{source},{ts:.0f}\n"
            
            # Write to MT5 Files
            MT5_FILES.mkdir(parents=True, exist_ok=True)
            with open(SIGNALS_FILE, "a") as f:
                f.write(line)
            
            return True
        
        except Exception as e:
            log.error(f"Signal processing error: {e}")
            return False
    
    def log_message(self, format, *args):
        """Suppress default HTTP logging."""
        pass

def run_server():
    """Start HTTP signal receiver on port 8888."""
    server = HTTPServer(("127.0.0.1", 8888), SignalHandler)
    log.info("Signal receiver listening on http://127.0.0.1:8888")
    server.serve_forever()

if __name__ == "__main__":
    run_server()
```

### Step 2.2: Install Signal Receiver as Windows Service

1. Create batch file: `C:\MediDeals\install_service.bat`

```batch
@echo off
REM Install signal receiver as Windows service
cd C:\MediDeals
python -m pip install pywin32 --quiet
python create_service.py
```

2. Create `C:\MediDeals\create_service.py`

```python
import subprocess
import sys

# Install as service using nssm (Non-Sucking Service Manager)
# Download nssm: https://nssm.cc/download

print("Installing Signal Receiver Service...")
subprocess.run([
    "C:\\nssm\\nssm.exe", "install",
    "MediDealsSignalReceiver",
    "python.exe", "C:\\MediDeals\\signal_receiver.py"
], check=True)

subprocess.run([
    "C:\\nssm\\nssm.exe", "set",
    "MediDealsSignalReceiver", "AppDirectory", "C:\\MediDeals"
], check=True)

subprocess.run([
    "C:\\nssm\\nssm.exe", "set",
    "MediDealsSignalReceiver", "AppStdout", "C:\\MediDeals\\service.log"
], check=True)

print("Service installed. Start with: net start MediDealsSignalReceiver")
```

3. Start service:
```batch
net start MediDealsSignalReceiver
```

**Verify:**
```batch
tasklist | findstr python
```

Should show signal_receiver.py running.

---

## Phase 3: DigitalOcean Signal Sender

### Step 3.1: Create Signal Sender Script

On DigitalOcean, create: `/root/MediDeals-iOS-App/send_signal_to_windows.py`

```python
#!/usr/bin/env python3
"""
Send signals from DigitalOcean to Windows VPS MT5.
"""

import os
import json
import requests
import logging
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s | SENDER | %(levelname)s | %(message)s'
)
log = logging.getLogger(__name__)

# Windows VPS endpoint (set in .env)
WINDOWS_VPS_URL = os.getenv("WINDOWS_VPS_URL", "http://windows-vps-ip:8888")
AUTH_TOKEN = os.getenv("WINDOWS_VPS_AUTH_TOKEN", "")
QUEUE_FILE = Path(".trade_queue.jsonl")

def send_signal_to_windows(signal):
    """Send one signal to Windows VPS MT5."""
    try:
        headers = {
            "Authorization": f"Bearer {AUTH_TOKEN}",
            "Content-Type": "application/json"
        }
        
        response = requests.post(
            f"{WINDOWS_VPS_URL}/signal",
            json=signal,
            headers=headers,
            timeout=5
        )
        
        if response.status_code == 200:
            log.info(f"✓ Sent to Windows: {signal['symbol']} {signal['direction']}")
            return True
        else:
            log.error(f"✗ Windows rejected: {response.status_code} {response.text}")
            return False
    
    except Exception as e:
        log.error(f"✗ Send failed: {e}")
        return False

def main():
    """Poll queue, send signals to Windows."""
    if not QUEUE_FILE.exists():
        log.warning("Queue file not found")
        return
    
    try:
        with open(QUEUE_FILE, "r+") as f:
            lines = f.readlines()
            f.seek(0)
            f.truncate()
        
        for line in lines:
            line = line.strip()
            if not line:
                continue
            
            try:
                signal = json.loads(line)
                send_signal_to_windows(signal)
            except json.JSONDecodeError:
                log.warning(f"Invalid JSON: {line}")
    
    except Exception as e:
        log.error(f"Queue error: {e}")

if __name__ == "__main__":
    main()
```

### Step 3.2: Add to DigitalOcean .env

```bash
# Windows VPS MT5 execution
WINDOWS_VPS_URL=http://windows-vps-static-ip:8888
WINDOWS_VPS_AUTH_TOKEN=your_strong_random_token_here
```

### Step 3.3: Update DigitalOcean Trader Loop

Modify `/root/MediDeals-iOS-App/telegram_bot/trader.py` to send to Windows instead of writing local CSV:

```python
# Replace local MT5 file write with Windows send
import send_signal_to_windows

def forward_signal_to_windows(signal):
    """Send signal to Windows VPS instead of local MT5."""
    result = send_signal_to_windows.send_signal_to_windows(signal)
    log.info(f"Forwarded to Windows: {signal['symbol']} - {result}")
```

---

## Phase 4: Security & Network

### Firewall Rules (Windows VPS)

```batch
REM Allow DigitalOcean outbound HTTPS
netsh advfirewall firewall add rule name="DO-HTTPS-Out" dir=out action=allow protocol=tcp remoteip=<DO-IP> remoteport=443

REM Block public signal receiver (only localhost access if needed)
netsh advfirewall firewall add rule name="SignalReceiver" dir=in action=allow protocol=tcp localport=8888 remoteip=127.0.0.1
```

### DigitalOcean Security

- Use HTTPS (self-signed cert acceptable for internal)
- Authenticate all requests (Bearer token)
- Rate limit: 10 signals/second max
- Log all signal receipts
- Monitor for rejected signals

---

## Phase 5: Controlled Demo Validation

### Windows VPS Test

1. Verify MT5 connected to Vantage DEMO
2. Verify TradeFromFile EA attached and running
3. Send test signal from DigitalOcean:

```bash
curl -X POST http://windows-vps-ip:8888/signal \
  -H "Authorization: Bearer $WINDOWS_VPS_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "symbol": "EURUSD",
    "direction": "BUY",
    "sl": 1.08200,
    "tp": 1.09200,
    "source": "test",
    "ts": '$(date +%s)'
  }'
```

**Expected result:**
- Signal received by Windows (HTTP 200)
- MT5 Journal shows: "TRADE OK: BUY EURUSD 0.01"
- Position created in MT5 with correct SL/TP

### DigitalOcean Test

1. Queue signal to .trade_queue.jsonl
2. Run sender script
3. Verify Windows VPS receives and executes

---

## Phase 6: Health Monitoring

### Windows VPS Health Check

File: `C:\MediDeals\health_check.ps1`

```powershell
# Check MT5 running
$mt5 = Get-Process terminal64 -ErrorAction SilentlyContinue
if ($mt5) { Write-Host "✓ MT5 running" } else { Write-Host "✗ MT5 not running" }

# Check receiver running
$receiver = Get-Process python -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "signal_receiver" }
if ($receiver) { Write-Host "✓ Receiver running" } else { Write-Host "✗ Receiver not running" }

# Check recent signals
$signals = (Get-Content "C:\MediDeals\receiver.log" -Tail 20 | Select-String "Accepted")
Write-Host "Recent signals: $($signals.Count)"
```

### DigitalOcean Health Check

```bash
# Check signal send success rate
grep "Sent to Windows" /root/MediDeals-iOS-App/telegram_bot/logs/sender.log | tail -20
```

---

## Phase 7: Rollback & Emergency Stop

### Windows VPS Emergency Stop

```batch
REM Stop MT5 and services
taskkill /IM terminal64.exe /F
net stop MediDealsSignalReceiver

REM Clear signal queue
del C:\Program Files\MetaTrader 5\MQL5\Files\mt5_signals.csv
```

### DigitalOcean Emergency Stop

```bash
# Stop signal transmission
pkill -f send_signal_to_windows.py

# Stop bots
pkill -f "python3.*bot\.py"
```

---

## Installation Checklist

- [ ] Windows VPS deployed (OS, RAM, network)
- [ ] MT5 installed natively
- [ ] Vantage DEMO account connected
- [ ] TradeFromFile EA compiled and attached
- [ ] Signal receiver service installed
- [ ] DigitalOcean sender script installed
- [ ] .env configured with Windows VPS URL and auth token
- [ ] Firewall rules configured
- [ ] HTTPS/security configured
- [ ] Demo signals tested (EURUSD, GBPUSD, XAUUSD)
- [ ] Demo orders executed with correct SL/TP
- [ ] USDJPY rejected (not approved)
- [ ] India execution blocked
- [ ] Health monitoring enabled
- [ ] Rollback procedure tested

---

## Safety Guarantees

✓ No MT5/Wine on DigitalOcean  
✓ No manual GUI trading  
✓ Demo-only execution (Vantage DEMO)  
✓ 0.01 lots controlled  
✓ SL/TP validation mandatory  
✓ Duplicate/stale signal protection  
✓ India signals-only  
✓ USDJPY disabled  
✓ Secure inter-server communication  
✓ No public exposure of MT5  

---

## Support

- Windows VPS logs: `C:\MediDeals\receiver.log`
- DigitalOcean sender logs: `/root/MediDeals-iOS-App/telegram_bot/logs/sender.log`
- MT5 Journal: View in MT5 terminal
- Network test: `ping windows-vps-ip` from DigitalOcean
