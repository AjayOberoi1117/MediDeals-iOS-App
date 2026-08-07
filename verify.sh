#!/usr/bin/env bash
################################################################################
# MediDeals Deployment Verification
# ==================================
#
# Verify that deployment is operational and healthy.
#
# Usage:
#   bash verify.sh
#
# Exit codes:
#   0 = all checks pass
#   1 = some checks failed (see output for details)
#
################################################################################

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

check_pass() {
    echo -e "${GREEN}✓${NC} $*"
    ((PASS_COUNT++))
}

check_fail() {
    echo -e "${RED}✗${NC} $*"
    ((FAIL_COUNT++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
    ((WARN_COUNT++))
}

echo "════════════════════════════════════════════════════════════════════"
echo "MediDeals Deployment Verification"
echo "════════════════════════════════════════════════════════════════════"
echo ""

# Check services
echo "Checking service status..."

for svc in medideals-mt5-bridge medideals-gold-bot medideals-forex-scalper medideals-btc-bot medideals-nifty-scalper medideals-options-scalper medideals-india-scalper; do
    if systemctl is-active --quiet "${svc}.service" 2>/dev/null; then
        check_pass "${svc} is running"
    else
        check_fail "${svc} is not running"
    fi
done

echo ""
echo "Checking credentials..."

if [[ -f /etc/medideals/telegram.env ]]; then
    check_pass "Credentials file exists"

    local perms=$(stat -c %a /etc/medideals/telegram.env 2>/dev/null || echo "unknown")
    if [[ "$perms" == "600" ]]; then
        check_pass "Credentials file permissions are 600 (secure)"
    else
        check_fail "Credentials file permissions are $perms (expected 600)"
    fi
else
    check_fail "Credentials file not found"
fi

# Check execution mode
echo ""
echo "Checking execution guards..."

if grep -q "BOT_EXECUTION_MODE=dry_run" /etc/medideals/telegram.env 2>/dev/null; then
    check_pass "BOT_EXECUTION_MODE=dry_run (orders blocked)"
else
    check_warn "BOT_EXECUTION_MODE not set to dry_run"
fi

if grep -q "INDIA_ORDERS_ENABLED=NO" /etc/medideals/telegram.env 2>/dev/null; then
    check_pass "India order execution blocked"
else
    check_warn "India order execution not explicitly blocked"
fi

# Check systemd boot persistence
echo ""
echo "Checking boot persistence..."

if systemctl is-enabled medideals-bots.target 2>/dev/null; then
    check_pass "Services enabled for auto-start at boot"
else
    check_warn "Services not enabled for boot"
fi

# Check MT5 bridge
echo ""
echo "Checking MT5 bridge..."

if timeout 3 bash -c "</dev/tcp/localhost/18812" 2>/dev/null; then
    check_pass "MT5 Wine bridge port 18812 is listening"
else
    check_warn "MT5 Wine bridge port 18812 not responding"
fi

# Check logs
echo ""
echo "Checking for recent errors in logs..."

local error_count=$(journalctl -u medideals-bots.target --since "1 hour ago" | grep -ic "error\|failed\|exception" || echo "0")
if [[ $error_count -eq 0 ]]; then
    check_pass "No errors in logs (last hour)"
else
    check_warn "$error_count error messages found in logs (last hour)"
fi

# Check disk space
echo ""
echo "Checking disk space..."

local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [[ $disk_usage -lt 80 ]]; then
    check_pass "Disk usage: ${disk_usage}% (adequate)"
else
    check_warn "Disk usage: ${disk_usage}% (high)"
fi

# Check memory
echo ""
echo "Checking memory..."

local mem_avail=$(free -h | grep Mem | awk '{print $7}')
check_pass "Available memory: ${mem_avail}"

# Summary
echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "Summary"
echo "════════════════════════════════════════════════════════════════════"
echo -e "Passed: ${GREEN}${PASS_COUNT}${NC} | Failed: ${RED}${FAIL_COUNT}${NC} | Warnings: ${YELLOW}${WARN_COUNT}${NC}"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}✓ All critical checks passed${NC}"
    exit 0
else
    echo -e "${RED}✗ Some checks failed — review above${NC}"
    exit 1
fi
