#!/usr/bin/env bash
# setup_vps.sh — One-command setup for all 6 trading bots on a fresh Ubuntu VPS
set -e
export DEBIAN_FRONTEND=noninteractive

echo "============================================"
echo "  Trading Bots VPS Setup"
echo "============================================"
echo ""

# 1 — Update system
echo "[1/6] Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq -o Dpkg::Options::="--force-confold"
echo "      Done."

# 2 — Install dependencies
echo "[2/6] Installing Python3, pip, git, screen..."
apt-get install -y -qq -o Dpkg::Options::="--force-confold" python3 python3-pip git screen
echo "      Done."

# 3 — Clone repo
echo "[3/6] Cloning bot repository from GitHub..."
cd /root
if [ -d "MediDeals-iOS-App" ]; then
    cd MediDeals-iOS-App
    git fetch origin
    git checkout claude/bots-trade-signals-debug-wjevgt
    git pull origin claude/bots-trade-signals-debug-wjevgt
    cd ..
else
    git clone https://github.com/AjayOberoi1117/MediDeals-iOS-App.git
    cd MediDeals-iOS-App
    git checkout claude/bots-trade-signals-debug-wjevgt
    cd ..
fi
echo "      Done."

# 4 — Install Python packages
echo "[4/6] Installing Python packages..."
pip3 install requests python-dotenv yfinance pandas --break-system-packages --quiet
echo "      Done."

# 5 — Cron jobs (9 AM start Mon-Fri, midnight stop)
echo "[5/6] Setting up cron schedule..."
mkdir -p /root/MediDeals-iOS-App/telegram_bot/logs
chmod +x /root/MediDeals-iOS-App/telegram_bot/start_bots.sh
chmod +x /root/MediDeals-iOS-App/telegram_bot/stop_bots.sh
(crontab -l 2>/dev/null | grep -v "telegram_bot" | grep -v "start_bots" | grep -v "stop_bots"
 echo "# Trading bots — auto start/stop"
 echo "0 9 * * 1-5 bash /root/MediDeals-iOS-App/telegram_bot/start_bots.sh >> /root/MediDeals-iOS-App/telegram_bot/logs/cron.log 2>&1"
 echo "0 0 * * 2-6 bash /root/MediDeals-iOS-App/telegram_bot/stop_bots.sh >> /root/MediDeals-iOS-App/telegram_bot/logs/cron.log 2>&1") | crontab -
echo "      Done. (start: 9AM Mon-Fri | stop: midnight)"

# 6 — Start all bots now
echo "[6/6] Starting all 6 bots..."
cd /root/MediDeals-iOS-App/telegram_bot
bash start_bots.sh

echo ""
echo "============================================"
echo "  ALL DONE! VPS is fully set up."
echo ""
echo "  6 bots are now running 24/7."
echo "  Auto-start : 9:00 AM Mon-Fri"
echo "  Auto-stop  : 12:00 AM (midnight)"
echo ""
echo "  Check logs:"
echo "  tail -f /root/MediDeals-iOS-App/telegram_bot/logs/gold.log"
echo "  tail -f /root/MediDeals-iOS-App/telegram_bot/logs/nifty.log"
echo "============================================"
