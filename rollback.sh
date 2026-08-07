#!/usr/bin/env bash
################################################################################
# MediDeals Rollback Script
# ========================
#
# Safely rollback DigitalOcean deployment.
#
# Usage:
#   sudo bash rollback.sh
#
# WARNING: This will stop all bots and disable services.
# Credentials file is preserved (can be redeployed).
#
################################################################################

set -euo pipefail

readonly DEPLOY_USER="medideals"
readonly DEPLOY_HOME="/home/${DEPLOY_USER}"
readonly DEPLOY_REPO="${DEPLOY_HOME}/MediDeals-iOS-App"

echo "════════════════════════════════════════════════════════════════════"
echo "MediDeals Deployment Rollback"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "WARNING: This will:"
echo "  • Stop all trading bots"
echo "  • Disable systemd services"
echo "  • Delete deployed code"
echo "  • PRESERVE credentials (can redeploy)"
echo ""

read -p "Continue with rollback? (type 'yes' to confirm): " confirm
if [[ "${confirm}" != "yes" ]]; then
    echo "Rollback cancelled"
    exit 0
fi

# Verify root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root"
    exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "Step 1: Stop all services"
echo "════════════════════════════════════════════════════════════════════"

systemctl stop medideals-bots.target || true
systemctl disable medideals-bots.target || true

for svc in medideals-mt5-bridge medideals-gold-bot medideals-forex-scalper medideals-btc-bot medideals-nifty-scalper medideals-options-scalper medideals-india-scalper; do
    systemctl disable "${svc}.service" || true
    systemctl stop "${svc}.service" || true
done

echo "✓ Services stopped and disabled"

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "Step 2: Remove systemd unit files"
echo "════════════════════════════════════════════════════════════════════"

rm -f /etc/systemd/system/medideals-*.service
rm -f /etc/systemd/system/medideals-*.target
systemctl daemon-reload

echo "✓ Systemd unit files removed"

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "Step 3: Remove deployed code"
echo "════════════════════════════════════════════════════════════════════"

if [[ -d "${DEPLOY_REPO}" ]]; then
    rm -rf "${DEPLOY_REPO}"
    echo "✓ Repository deleted"
else
    echo "⊘ Repository not found (already deleted?)"
fi

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "Step 4: Stop Wine/MT5"
echo "════════════════════════════════════════════════════════════════════"

pkill -f "Xvfb" || true
pkill -f "wine_server" || true
pkill -f "x11vnc" || true
pkill -f "terminal64.exe" || true

echo "✓ Wine processes stopped"

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "Step 5: Preserve credentials"
echo "════════════════════════════════════════════════════════════════════"

if [[ -f "/etc/medideals/telegram.env" ]]; then
    echo "✓ Credentials preserved at /etc/medideals/telegram.env"
    echo "  (can be reused for redeployment)"
else
    echo "⊘ No credentials file found"
fi

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "Rollback Complete"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "To redeploy, run:"
echo "  sudo bash deploy.sh"
echo ""
