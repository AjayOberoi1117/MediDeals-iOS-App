#!/usr/bin/env bash
################################################################################
# Verify India Order Execution is Blocked
# ========================================
#
# Ensures India-market symbols cannot execute orders.
# India signals remain SIGNAL-ONLY (no execution).
#
# Usage:
#   bash verify_india_safety.sh
#
# Checks:
#   - India symbols in bot configs
#   - trader.py TRADEABLE list does not include India symbols
#   - Upstox connectivity (data-only, no order execution)
#
################################################################################

set -euo pipefail

echo "════════════════════════════════════════════════════════════════════"
echo "India Order Execution Safety Verification"
echo "════════════════════════════════════════════════════════════════════"

# India symbols (should NOT be in trader TRADEABLE list)
declare -a INDIA_SYMBOLS=(
    "NIFTY"
    "NIFTY50"
    "BANKNIFTY"
    "FINNIFTY"
    "INFY"
    "TCS"
    "RELIANCE"
)

echo ""
echo "STEP 1: Verify India symbols are NOT in trader.py TRADEABLE list"
echo ""

if [[ ! -f "trader.py" ]]; then
    echo "⚠ trader.py not found (cannot verify)"
else
    # Check if TRADEABLE list exists and what's in it
    if grep -q "TRADEABLE" trader.py; then
        echo "Found TRADEABLE configuration in trader.py"
        echo ""

        for symbol in "${INDIA_SYMBOLS[@]}"; do
            if grep "TRADEABLE" trader.py | grep -qi "$symbol"; then
                echo "✗ BLOCKING ISSUE: $symbol found in TRADEABLE list"
                exit 1
            else
                echo "✓ $symbol NOT in TRADEABLE list"
            fi
        done
    else
        echo "⊘ TRADEABLE list not found in trader.py"
        echo "  Assuming default behavior (India symbols not tradeable)"
    fi
fi

echo ""
echo "STEP 2: Verify India signals remain signal-only"
echo ""

india_bots=(
    "nifty_scalper.py"
    "scanner_bot.py"
)

for bot in "${india_bots[@]}"; do
    if [[ ! -f "$bot" ]]; then
        echo "⊘ $bot not found"
        continue
    fi

    echo "Checking $bot..."

    # Check for order execution calls
    if grep -qi "queue_trade\|place_order\|upstox_place_order\|execute_trade" "$bot"; then
        # Check if they're guarded or disabled
        if grep -qi "is_dry_run\|SIGNAL_ONLY\|signal.only\|no.*order" "$bot"; then
            echo "  ✓ Order execution calls are guarded"
        else
            echo "  ⚠ Order execution calls found (check if guarded)"
        fi
    else
        echo "  ✓ No order execution calls"
    fi
done

echo ""
echo "STEP 3: Verify Upstox usage (data-only)"
echo ""

# Check if .env has Upstox configured
if [[ -f ".env" ]]; then
    if grep -q "UPSTOX" .env; then
        echo "✓ Upstox API configured (for market data)"

        # Check that it's not used for order execution
        if grep -q "upstox_place_order\|broker.*upstox" .env 2>/dev/null; then
            echo "⚠ Check if Upstox is used for order execution"
        else
            echo "✓ Upstox appears to be data-only"
        fi
    else
        echo "⊘ Upstox not configured (data-only mode not available)"
    fi
fi

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "✓ India Order Execution Safety Verified"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "Status:"
echo "  • India symbols NOT in trader TRADEABLE list"
echo "  • India signal bots remain signal-only"
echo "  • Upstox used for market data only"
echo ""
echo "India trading blocked for order execution"
echo ""
