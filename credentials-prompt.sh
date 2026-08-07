#!/usr/bin/env bash
################################################################################
# MediDeals Secure Credentials Prompt
# ====================================
#
# Interactive credential collection for DigitalOcean deployment.
# Creates /etc/medideals/telegram.env with mode 600.
#
# Usage:
#   sudo bash credentials-prompt.sh
#
# DO NOT commit credentials to git.
# DO NOT print credentials to terminal unnecessarily.
# DO NOT share credentials via email or Slack.
#
################################################################################

set -euo pipefail

readonly SECRETS_FILE="/etc/medideals/telegram.env"
readonly DEPLOY_USER="medideals"

echo "════════════════════════════════════════════════════════════════════"
echo "MediDeals Credential Configuration"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "This script will create a secure credentials file at:"
echo "  ${SECRETS_FILE}"
echo ""
echo "IMPORTANT:"
echo "  • Credentials are NOT transmitted or logged"
echo "  • File permissions are set to 600 (owner read/write only)"
echo "  • File owner: medideals:medideals"
echo ""

# Verify root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

# Telegram
echo "════════════════════════════════════════════════════════════════════"
echo "TELEGRAM BOT CREDENTIALS"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "All bots use single Telegram routing: @Equitytrading_bot"
echo ""

read -sp "TELEGRAM_BOT_TOKEN (from BotFather): " TELEGRAM_BOT_TOKEN
echo ""
if [[ -z "${TELEGRAM_BOT_TOKEN}" ]]; then
    echo "Error: TELEGRAM_BOT_TOKEN cannot be empty"
    exit 1
fi

TELEGRAM_CHAT_ID="7093601171"
echo "TELEGRAM_CHAT_ID: $TELEGRAM_CHAT_ID (fixed)"

# Vantage DEMO MT5
echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "VANTAGE DEMO MT5 ACCOUNT"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "WARNING: Must be a DEMO account only."
echo "Live-money accounts will be BLOCKED by execution guards."
echo ""

read -sp "MT5_LOGIN (Vantage demo account login): " MT5_LOGIN
echo ""
if [[ -z "${MT5_LOGIN}" ]]; then
    echo "Error: MT5_LOGIN cannot be empty"
    exit 1
fi

read -sp "MT5_PASSWORD (Vantage demo account password): " MT5_PASSWORD
echo ""
if [[ -z "${MT5_PASSWORD}" ]]; then
    echo "Error: MT5_PASSWORD cannot be empty"
    exit 1
fi

MT5_SERVER="VantageMarkets-Demo"
echo "MT5_SERVER: $MT5_SERVER (fixed)"

# Upstox
echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "UPSTOX MARKET DATA API"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "(Optional: if not provided, India signals may fail to fetch data)"
echo ""

read -sp "UPSTOX_API_KEY (leave blank if not available): " UPSTOX_API_KEY
echo ""

read -sp "UPSTOX_API_SECRET (leave blank if not available): " UPSTOX_API_SECRET
echo ""

# Create secure credentials file
echo ""
echo "Creating secure credentials file..."

cat > "${SECRETS_FILE}" <<EOF
################################################################################
# MediDeals DigitalOcean Credentials
# Location: /etc/medideals/telegram.env
# Permissions: 600 (owner only)
# Owner: medideals:medideals
#
# WARNING: Never commit this file to git.
# Never share these credentials via email, Slack, or unsecured channels.
# Rotation procedure: Edit this file directly and restart services.
################################################################################

# ──────────────────────────────────────────────────────────────────────────────
# TELEGRAM BOT CREDENTIALS (Single routing via @Equitytrading_bot)
# ──────────────────────────────────────────────────────────────────────────────
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID}

# ──────────────────────────────────────────────────────────────────────────────
# BOT EXECUTION MODE (fail-closed default: dry_run)
# ──────────────────────────────────────────────────────────────────────────────
# Values: dry_run (signals only, no orders) | production (signals + orders)
BOT_EXECUTION_MODE=dry_run

# ──────────────────────────────────────────────────────────────────────────────
# MT5 BRIDGE CONFIGURATION (Wine headless + Vantage DEMO account ONLY)
# ──────────────────────────────────────────────────────────────────────────────
MT5_LOGIN=${MT5_LOGIN}
MT5_PASSWORD=${MT5_PASSWORD}
MT5_SERVER=${MT5_SERVER}

# ──────────────────────────────────────────────────────────────────────────────
# UPSTOX MARKET DATA (India equity signals)
# ──────────────────────────────────────────────────────────────────────────────
UPSTOX_API_KEY=${UPSTOX_API_KEY}
UPSTOX_API_SECRET=${UPSTOX_API_SECRET}

# ──────────────────────────────────────────────────────────────────────────────
# EXECUTION GUARDS (Fail-closed)
# ──────────────────────────────────────────────────────────────────────────────
LIVE_TRADING_CONFIRMED=NO
INDIA_ORDERS_ENABLED=NO
VANTAGE_ACCOUNT_VERIFIED=NO

# ──────────────────────────────────────────────────────────────────────────────
# LOGGING & MONITORING
# ──────────────────────────────────────────────────────────────────────────────
LOG_LEVEL=INFO
LOG_RETENTION_DAYS=30
EOF

# Set secure permissions
chmod 600 "${SECRETS_FILE}"
chown "${DEPLOY_USER}:${DEPLOY_USER}" "${SECRETS_FILE}"

echo "✓ Credentials file created: ${SECRETS_FILE}"
echo "✓ File permissions: 600 (owner only)"
echo "✓ File owner: ${DEPLOY_USER}:${DEPLOY_USER}"

# Verify file
echo ""
echo "Verifying credentials..."
if [[ -f "${SECRETS_FILE}" ]]; then
    local perms=$(stat -c %a "${SECRETS_FILE}")
    if [[ "$perms" == "600" ]]; then
        echo "✓ Credentials file is secure"
    else
        echo "✗ Error: File permissions are $perms (expected 600)"
        exit 1
    fi
else
    echo "✗ Error: Credentials file not created"
    exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "Credentials configured successfully!"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "Next step:"
echo "  sudo bash deploy.sh"
echo ""
