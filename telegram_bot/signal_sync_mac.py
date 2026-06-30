"""
signal_sync_mac.py — Run this on your Mac (native Python, no Wine needed)
Polls the GCP signal server every 30 seconds and writes mt5_signals.csv
into MT5's MQL5/Files folder so the TradeFromFile EA can place trades.

Install: pip3 install requests
Run:     python3 signal_sync_mac.py

MT5 must be open. The EA (TradeFromFile.mq5) must be attached to a chart.
"""

import os
import time
import glob
import requests

GCP_SIGNAL_URL = "http://34.47.230.185:8080/signal"
POLL_SECS      = 30
SIGNAL_FILE    = "mt5_signals.csv"

# Auto-detect MT5 MQL5/Files path (XM Mac installs Wine internally)
MT5_SEARCH_PATHS = [
    # XM MT5 for Mac (Wine-based)
    os.path.expanduser("~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/*/AppData/Roaming/MetaQuotes/Terminal/*/MQL5/Files/"),
    # Generic Wine prefix
    os.path.expanduser("~/.wine/drive_c/users/*/AppData/Roaming/MetaQuotes/Terminal/*/MQL5/Files/"),
    # Common XM path variation
    os.path.expanduser("~/Library/Application Support/MetaTrader 5/MQL5/Files/"),
]


def find_mt5_files_dir():
    for pattern in MT5_SEARCH_PATHS:
        matches = glob.glob(pattern)
        if matches:
            return matches[0]
    return None


def sync():
    try:
        r = requests.get(GCP_SIGNAL_URL, timeout=10)
        if r.status_code != 200 or not r.text.strip():
            return   # no signal pending

        signal_csv = r.text.strip()
        mt5_dir    = find_mt5_files_dir()

        if not mt5_dir:
            print("❌ MT5 Files folder not found. Open MT5, go to File → Open Data Folder, "
                  "and copy the MQL5/Files path here.")
            return

        out_path = os.path.join(mt5_dir, SIGNAL_FILE)
        with open(out_path, "w") as f:
            f.write(signal_csv + "\n")

        print(f"[{time.strftime('%H:%M:%S')}] ✅ Signal written → {out_path}")
        for line in signal_csv.splitlines():
            print(f"  {line}")

    except requests.exceptions.ConnectionError:
        print(f"[{time.strftime('%H:%M:%S')}] GCP unreachable — will retry in {POLL_SECS}s")
    except Exception as exc:
        print(f"[{time.strftime('%H:%M:%S')}] Error: {exc}")


def main():
    mt5_dir = find_mt5_files_dir()
    if mt5_dir:
        print(f"✅ MT5 Files folder found:\n   {mt5_dir}")
    else:
        print("⚠️  MT5 Files folder not found yet.")
        print("   Open MT5 → File → Open Data Folder, then paste the MQL5/Files path.")
        print("   Continuing anyway — will retry each poll.\n")

    print(f"Polling GCP signal server every {POLL_SECS}s...")
    print(f"URL: {GCP_SIGNAL_URL}\n")

    while True:
        sync()
        time.sleep(POLL_SECS)


if __name__ == "__main__":
    main()
