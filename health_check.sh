#!/usr/bin/env bash
################################################################################
# MediDeals Health Check
# =====================
#
# Continuous health monitoring for DigitalOcean deployment.
#
# Usage:
#   bash health_check.sh              # Single check
#   watch -n 60 bash health_check.sh  # Every 60 seconds
#
# For cron (every 5 minutes):
#   */5 * * * * /path/to/health_check.sh >> /var/log/medideals/health.log 2>&1
#
################################################################################

set -euo pipefail

readonly TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
readonly LOG_FILE="/var/log/medideals/health.log"

mkdir -p /var/log/medideals

log() {
    echo "[${TIMESTAMP}] $*" | tee -a "${LOG_FILE}"
}

# Service status
log "════ Service Health Check ════"

for svc in medideals-mt5-bridge medideals-gold-bot medideals-forex-scalper medideals-btc-bot medideals-nifty-scalper medideals-options-scalper medideals-india-scalper; do
    local status=$(systemctl is-active "${svc}.service" 2>/dev/null || echo "unknown")
    log "  ${svc}: ${status}"

    # If service is failed, attempt to restart
    if [[ "$status" == "failed" ]]; then
        log "  → Restarting ${svc}..."
        systemctl restart "${svc}.service" 2>/dev/null || log "  → Failed to restart"
    fi
done

# Process count
log "════ Process Count ════"
local bot_processes=$(pgrep -f "python3.*bot\.py|python3.*scalper\.py" | wc -l || echo "0")
log "  Trading bot processes: $bot_processes"

# Memory usage
log "════ Memory Usage ════"
free -h | grep Mem | awk '{log("  Total: " $2 ", Used: " $3 ", Available: " $7)}' | while read line; do echo "$line" | tee -a "${LOG_FILE}"; done

# Disk usage
log "════ Disk Usage ════"
df -h / | tail -1 | awk '{log("  Root: " $5 " used (" $4 " available)")}' | while read line; do echo "$line" | tee -a "${LOG_FILE}"; done

# MT5 bridge connectivity
log "════ MT5 Bridge ════"
if timeout 2 bash -c "</dev/tcp/localhost/18812" 2>/dev/null; then
    log "  Port 18812: listening"
else
    log "  Port 18812: not responding"
fi

# Recent error count
log "════ Recent Errors (last hour) ════"
local errors=$(journalctl -u medideals-bots.target --since "1 hour ago" | grep -ic "error\|failed\|exception" || echo "0")
log "  Errors: $errors"

log "════════════════════════════════════════════════════════════════════"
echo ""
