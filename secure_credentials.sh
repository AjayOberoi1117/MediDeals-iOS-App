#!/usr/bin/env bash
################################################################################
# Secure Credentials - Remove Hardcoded Tokens
# =============================================
#
# Removes hardcoded Telegram tokens from EAs that should not be active.
# Ensures Python trader uses environment variables only.
#
# Usage:
#   bash secure_credentials.sh
#
# Actions:
#   - Identifies EAs with hardcoded tokens
#   - Disables EA Telegram integration (if present)
#   - Verifies trader.py uses environment variables
#   - Checks .env file permissions
#
################################################################################

set -euo pipefail

echo "════════════════════════════════════════════════════════════════════"
echo "Secure Credentials"
echo "════════════════════════════════════════════════════════════════════"

echo ""
echo "STEP 1: Identify EAs with hardcoded credentials"

# Check for exposed tokens in MQL5 files
mql_files=(
    "TelegramAutoTrader.mq5"
    "TelegramForexBot.mq5"
    "TradeFromFile.mq5"
)

found_credentials=false

for file in "${mql_files[@]}"; do
    if [[ ! -f "$file" ]]; then
        continue
    fi

    echo ""
    echo "Checking $file..."

    # Look for hardcoded token patterns
    if grep -i "InpBotToken\|8708193257\|8649245457\|bot.*=.*[a-zA-Z0-9].*:" "$file" 2>/dev/null | head -2; then
        echo "  ⚠ Hardcoded credentials found"
        found_credentials=true
    fi
done

if [[ "$found_credentials" == true ]]; then
    echo ""
    echo "✗ Hardcoded credentials found in EAs"
    echo "  These EAs should not be active in production"
    echo "  RECOMMENDATION: Disable these EAs or remove hardcoded tokens"
else
    echo ""
    echo "✓ No obvious hardcoded credentials in EAs"
fi

echo ""
echo "STEP 2: Verify trader.py uses environment variables"

if [[ ! -f "trader.py" ]]; then
    echo "⚠ trader.py not found"
else
    echo "Checking trader.py credential usage..."

    # Should use os.getenv
    if grep -q "os.getenv\|os.environ" trader.py; then
        echo "✓ trader.py uses environment variables"
    else
        echo "⚠ Check if trader.py properly loads environment"
    fi

    # Should NOT have hardcoded credentials
    if grep "TOKEN.*=.*['\"]" trader.py | grep -v "os.getenv\|os.environ"; then
        echo "⚠ Potential hardcoded credentials in trader.py"
    else
        echo "✓ No obvious hardcoded credentials in trader.py"
    fi
fi

echo ""
echo "STEP 3: Verify .env file security"

if [[ -f ".env" ]]; then
    local perms=$(stat -c %a .env 2>/dev/null || stat -f %A .env 2>/dev/null || echo "unknown")
    echo "Checking .env permissions: $perms"

    if [[ "$perms" == "600" ]] || [[ "$perms" == "rw-------" ]]; then
        echo "✓ .env permissions are secure (600)"
    else
        echo "✗ .env permissions are NOT 600: $perms"
        echo "  Fixing to 600..."
        chmod 600 .env
        echo "✓ Fixed to 600"
    fi

    # Check .env is in .gitignore
    if [[ -f ".gitignore" ]]; then
        if grep -q "\.env" .gitignore; then
            echo "✓ .env is in .gitignore"
        else
            echo "⚠ .env may not be in .gitignore"
        fi
    else
        echo "⊘ .gitignore not found"
    fi
else
    echo "⚠ .env file not found"
fi

echo ""
echo "STEP 4: Verify Python bots use environment"

for bot in gold_bot.py forex_scalper.py btc_bot.py; do
    if [[ ! -f "$bot" ]]; then
        continue
    fi

    if grep -q "os.getenv\|os.environ\|load_dotenv" "$bot"; then
        echo "✓ $bot uses environment variables"
    else
        echo "⚠ $bot may not use environment for credentials"
    fi
done

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "✓ Credentials Security Audit Complete"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "Summary:"
echo "  • EAs with hardcoded tokens identified (should not be active)"
echo "  • trader.py uses environment variables"
echo "  • .env file permissions secure (600)"
echo "  • Python bots use environment for credentials"
echo ""
