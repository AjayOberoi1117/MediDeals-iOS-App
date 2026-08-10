#!/usr/bin/env bash
################################################################################
# MediDeals DigitalOcean Recovery Diagnostic
# ==========================================
#
# Diagnose and recover existing trading bot deployment.
# Runs on the existing DigitalOcean droplet (non-destructive).
#
# Usage:
#   sudo bash recovery-diagnostic.sh
#
# Does NOT:
#   - Reprovision droplet
#   - Reinstall OS
#   - Rebuild infrastructure
#   - Overwrite credentials
#   - Enable live-money trading
#
# Does:
#   - Diagnose exact root cause
#   - Auto-recover where safe
#   - Report final status
#
################################################################################

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ──────────────────────────────────────────────────────────────────────────────

readonly TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
readonly LOG_FILE="/tmp/recovery-diagnostic-${TIMESTAMP//[: -]/_}.log"
readonly SECRETS_FILE="/etc/medideals/telegram.env"
readonly DEPLOY_USER="medideals"
readonly DEPLOY_HOME="/home/${DEPLOY_USER}"
readonly WINE_PREFIX="${DEPLOY_HOME}/.wine_mt5"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# State tracking
ROOT_CAUSE=""
RECOVERY_ACTIONS=""
FINAL_STATUS="UNKNOWN"

# ──────────────────────────────────────────────────────────────────────────────
# LOGGING
# ──────────────────────────────────────────────────────────────────────────────

log() {
    echo "[${TIMESTAMP}] $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}✗${NC} $*" | tee -a "${LOG_FILE}"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $*" | tee -a "${LOG_FILE}"
}

# ──────────────────────────────────────────────────────────────────────────────
# PHASE 1: SERVER STATE DIAGNOSIS
# ──────────────────────────────────────────────────────────────────────────────

phase_1_server_state() {
    log_info "════════════════════════════════════════════════════════════════════"
    log_info "PHASE 1: Server State Diagnosis"
    log_info "════════════════════════════════════════════════════════════════════"

    log "Hostname: $(hostname)"
    log "Uptime: $(uptime)"
    log ""

    log "Disk usage:"
    df -h | tee -a "${LOG_FILE}"
    log ""

    log "Memory usage:"
    free -h | tee -a "${LOG_FILE}"
    log ""

    log "Failed systemd units:"
    systemctl --failed 2>/dev/null | tee -a "${LOG_FILE}" || log "No failed units (or systemctl not available)"
    log ""

    log "MediDeals-related services:"
    systemctl list-units --type=service --all 2>/dev/null | grep -iE 'medideals|mt5|gold|forex|btc|nifty|india|options' | tee -a "${LOG_FILE}" || log "No matching services found"
    log ""
}

# ──────────────────────────────────────────────────────────────────────────────
# PHASE 2: SERVICE STATUS INSPECTION
# ──────────────────────────────────────────────────────────────────────────────

phase_2_service_status() {
    log_info "════════════════════════════════════════════════════════════════════"
    log_info "PHASE 2: Service Status Inspection"
    log_info "════════════════════════════════════════════════════════════════════"

    local services=(
        "medideals-mt5-bridge"
        "medideals-gold-bot"
        "medideals-forex-scalper"
        "medideals-btc-bot"
        "medideals-nifty-scalper"
        "medideals-options-scalper"
        "medideals-india-scalper"
    )

    for svc in "${services[@]}"; do
        log ""
        log "Service: ${svc}.service"

        # Check if service exists
        if systemctl list-unit-files 2>/dev/null | grep -q "${svc}.service"; then
            log_success "Service exists"

            # Get status
            local loaded=$(systemctl show -p LoadState "${svc}.service" --value 2>/dev/null)
            local enabled=$(systemctl is-enabled "${svc}.service" 2>/dev/null || echo "unknown")
            local active=$(systemctl is-active "${svc}.service" 2>/dev/null || echo "unknown")

            log "  Loaded: $loaded"
            log "  Enabled: $enabled"
            log "  Active: $active"

            # Get last exit status
            if [[ "$active" == "inactive" ]] || [[ "$active" == "failed" ]]; then
                local exit_code=$(systemctl show -p ExecMainStatus "${svc}.service" --value 2>/dev/null || echo "unknown")
                local exit_time=$(systemctl show -p ExecMainExitTimestamp "${svc}.service" --value 2>/dev/null || echo "unknown")
                log "  Last exit code: $exit_code"
                log "  Last exit time: $exit_time"
            fi

            # Get recent journal errors
            log "  Recent errors (last 10):"
            journalctl -u "${svc}.service" -n 10 --no-pager 2>/dev/null | grep -iE "error|failed|exception" | sed 's/^/    /' | tee -a "${LOG_FILE}" || log "    (no errors found)"
        else
            log_error "Service not found"
        fi
    done

    log ""
}

# ──────────────────────────────────────────────────────────────────────────────
# PHASE 3: PROCESS & BRIDGE CHECK
# ──────────────────────────────────────────────────────────────────────────────

phase_3_process_check() {
    log_info "════════════════════════════════════════════════════════════════════"
    log_info "PHASE 3: Process & Bridge Check"
    log_info "════════════════════════════════════════════════════════════════════"

    log "Python bot processes:"
    ps aux 2>/dev/null | grep -E 'gold_bot|forex_scalper|btc_bot|nifty_scalper|india_scalper|options_scalper|wine_server' | grep -v grep | tee -a "${LOG_FILE}" || log "  (no processes found)"
    log ""

    log "Wine/MT5 processes:"
    ps aux 2>/dev/null | grep -E 'wine|metatrader|terminal64' | grep -v grep | tee -a "${LOG_FILE}" || log "  (no processes found)"
    log ""

    log "Display/Xvfb:"
    ps aux 2>/dev/null | grep -E 'Xvfb|x11vnc' | grep -v grep | tee -a "${LOG_FILE}" || log "  (Xvfb not running)"
    log ""

    log "MT5 Wine bridge connectivity (localhost:18812):"
    if timeout 2 bash -c "</dev/tcp/localhost/18812" 2>/dev/null; then
        log_success "Bridge port 18812 is listening"
    else
        log_error "Bridge port 18812 NOT responding"
        ROOT_CAUSE="MT5 Wine bridge not listening on port 18812"
    fi
    log ""
}

# ──────────────────────────────────────────────────────────────────────────────
# PHASE 4: CREDENTIALS & ENVIRONMENT CHECK
# ──────────────────────────────────────────────────────────────────────────────

phase_4_credentials_check() {
    log_info "════════════════════════════════════════════════════════════════════"
    log_info "PHASE 4: Credentials & Environment Check"
    log_info "════════════════════════════════════════════════════════════════════"

    if [[ ! -f "${SECRETS_FILE}" ]]; then
        log_error "Secrets file not found: ${SECRETS_FILE}"
        ROOT_CAUSE="Missing credentials file at ${SECRETS_FILE}"
        return 1
    fi

    log_success "Credentials file exists"

    # Check permissions
    local perms=$(stat -c %a "${SECRETS_FILE}" 2>/dev/null || echo "unknown")
    if [[ "$perms" == "600" ]]; then
        log_success "Credentials file permissions: 600 (secure)"
    else
        log_error "Credentials file permissions: $perms (expected 600)"
        ROOT_CAUSE="Credentials file permissions incorrect: $perms"
    fi

    # Check essential variables exist (without printing values)
    log "Checking required environment variables..."

    local required_vars=(
        "TELEGRAM_BOT_TOKEN"
        "TELEGRAM_CHAT_ID"
        "BOT_EXECUTION_MODE"
        "MT5_LOGIN"
        "MT5_PASSWORD"
        "MT5_SERVER"
    )

    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if grep -q "^${var}=" "${SECRETS_FILE}"; then
            local value=$(grep "^${var}=" "${SECRETS_FILE}" | cut -d'=' -f2)
            if [[ -z "$value" ]]; then
                missing_vars+=("$var (empty)")
            else
                log "  ✓ $var (configured)"
            fi
        else
            missing_vars+=("$var (missing)")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing or empty variables: ${missing_vars[*]}"
        ROOT_CAUSE="Missing credentials: ${missing_vars[*]}"
    else
        log_success "All required credentials are configured"
    fi

    log ""
}

# ──────────────────────────────────────────────────────────────────────────────
# PHASE 5: ROOT CAUSE DIAGNOSIS
# ──────────────────────────────────────────────────────────────────────────────

phase_5_root_cause() {
    log_info "════════════════════════════════════════════════════════════════════"
    log_info "PHASE 5: Root Cause Diagnosis"
    log_info "════════════════════════════════════════════════════════════════════"

    # Check if services are disabled
    local disabled_count=0
    for svc in medideals-{mt5-bridge,gold-bot,forex-scalper,btc-bot,nifty-scalper,options-scalper,india-scalper}; do
        if ! systemctl is-enabled "${svc}.service" 2>/dev/null | grep -q "enabled"; then
            ((disabled_count++))
        fi
    done

    if [[ $disabled_count -gt 0 ]]; then
        log_error "$disabled_count services are disabled"
        ROOT_CAUSE="Services disabled (need systemctl enable)"
    fi

    # Check for crash loops
    log "Checking for crash loops..."
    local crash_loop_count=$(systemctl list-units --type=service --all 2>/dev/null | grep medideals | grep -i "activating\|failed" | wc -l)
    if [[ $crash_loop_count -gt 0 ]]; then
        log_error "$crash_loop_count services in crash loop"
        ROOT_CAUSE="Services in crash loop: see journal logs"
    fi

    # Check for disk space
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 90 ]]; then
        log_error "Disk usage critically high: ${disk_usage}%"
        ROOT_CAUSE="Disk space critical (${disk_usage}%)"
    elif [[ $disk_usage -gt 80 ]]; then
        log_warn "Disk usage high: ${disk_usage}%"
    fi

    # Check for OOM
    local oom_count=$(journalctl --since "24 hours ago" 2>/dev/null | grep -i "out of memory" | wc -l)
    if [[ $oom_count -gt 0 ]]; then
        log_error "Out of memory errors detected ($oom_count incidents)"
        ROOT_CAUSE="Out of memory"
    fi

    # Check DNS
    log "Checking DNS resolution..."
    if ! timeout 2 nslookup google.com >/dev/null 2>&1; then
        log_error "DNS resolution failed"
        ROOT_CAUSE="DNS failure (cannot resolve addresses)"
    else
        log_success "DNS is working"
    fi

    # Check network
    log "Checking network connectivity..."
    if ! timeout 2 curl -s https://api.telegram.org/test >/dev/null 2>&1; then
        log_warn "Telegram API not reachable (may be network issue)"
    else
        log_success "Network connectivity OK"
    fi

    if [[ -z "$ROOT_CAUSE" ]]; then
        log_info "No obvious root cause found — attempting standard recovery"
        ROOT_CAUSE="Services stopped (cause unknown, attempting restart)"
    fi

    log ""
    log "ROOT CAUSE IDENTIFIED: $ROOT_CAUSE"
    log ""
}

# ──────────────────────────────────────────────────────────────────────────────
# PHASE 6: AUTO-RECOVERY
# ──────────────────────────────────────────────────────────────────────────────

phase_6_auto_recovery() {
    log_info "════════════════════════════════════════════════════════════════════"
    log_info "PHASE 6: Auto-Recovery"
    log_info "════════════════════════════════════════════════════════════════════"

    # Step 1: Start Xvfb if not running
    log "Step 1: Verify Xvfb virtual display..."
    if ! pgrep -x Xvfb >/dev/null 2>&1; then
        log_info "Starting Xvfb virtual display..."
        sudo -u "${DEPLOY_USER}" bash -c "Xvfb :99 -screen 0 1024x768x24 &" 2>/dev/null || true
        sleep 3
        RECOVERY_ACTIONS="${RECOVERY_ACTIONS}• Started Xvfb :99\n"
    else
        log_success "Xvfb already running"
    fi

    # Step 2: Enable and start MT5 bridge
    log "Step 2: Enable and start MT5 Wine bridge..."
    if ! systemctl is-enabled medideals-mt5-bridge.service 2>/dev/null | grep -q "enabled"; then
        log_info "Enabling medideals-mt5-bridge.service..."
        systemctl enable medideals-mt5-bridge.service
        RECOVERY_ACTIONS="${RECOVERY_ACTIONS}• Enabled medideals-mt5-bridge.service\n"
    fi

    if ! systemctl is-active medideals-mt5-bridge.service >/dev/null 2>&1; then
        log_info "Starting medideals-mt5-bridge.service..."
        systemctl restart medideals-mt5-bridge.service
        sleep 10
        RECOVERY_ACTIONS="${RECOVERY_ACTIONS}• Started medideals-mt5-bridge.service\n"

        # Verify bridge is listening
        if timeout 5 bash -c "</dev/tcp/localhost/18812" 2>/dev/null; then
            log_success "MT5 bridge is now listening on port 18812"
        else
            log_error "MT5 bridge still not listening"
            return 1
        fi
    else
        log_success "MT5 bridge already running"
    fi

    # Step 3: Enable and start Gold bot
    log "Step 3: Enable and start Gold trading bot..."
    if ! systemctl is-enabled medideals-gold-bot.service 2>/dev/null | grep -q "enabled"; then
        systemctl enable medideals-gold-bot.service
        RECOVERY_ACTIONS="${RECOVERY_ACTIONS}• Enabled medideals-gold-bot.service\n"
    fi

    if ! systemctl is-active medideals-gold-bot.service >/dev/null 2>&1; then
        log_info "Starting medideals-gold-bot.service..."
        systemctl restart medideals-gold-bot.service
        sleep 5
        RECOVERY_ACTIONS="${RECOVERY_ACTIONS}• Started medideals-gold-bot.service\n"
    else
        log_success "Gold bot already running"
    fi

    # Step 4: Enable and start Forex scalper
    log "Step 4: Enable and start Forex scalper..."
    if ! systemctl is-enabled medideals-forex-scalper.service 2>/dev/null | grep -q "enabled"; then
        systemctl enable medideals-forex-scalper.service
        RECOVERY_ACTIONS="${RECOVERY_ACTIONS}• Enabled medideals-forex-scalper.service\n"
    fi

    if ! systemctl is-active medideals-forex-scalper.service >/dev/null 2>&1; then
        log_info "Starting medideals-forex-scalper.service..."
        systemctl restart medideals-forex-scalper.service
        sleep 5
        RECOVERY_ACTIONS="${RECOVERY_ACTIONS}• Started medideals-forex-scalper.service\n"
    else
        log_success "Forex scalper already running"
    fi

    # Step 5: Enable and start BTC bot
    log "Step 5: Enable and start BTC bot..."
    if ! systemctl is-enabled medideals-btc-bot.service 2>/dev/null | grep -q "enabled"; then
        systemctl enable medideals-btc-bot.service
        RECOVERY_ACTIONS="${RECOVERY_ACTIONS}• Enabled medideals-btc-bot.service\n"
    fi

    if ! systemctl is-active medideals-btc-bot.service >/dev/null 2>&1; then
        log_info "Starting medideals-btc-bot.service..."
        systemctl restart medideals-btc-bot.service
        sleep 5
        RECOVERY_ACTIONS="${RECOVERY_ACTIONS}• Started medideals-btc-bot.service\n"
    else
        log_success "BTC bot already running"
    fi

    # Step 6: Enable and start Nifty scalper (signal owner)
    log "Step 6: Enable and start Nifty scalper..."
    if ! systemctl is-enabled medideals-nifty-scalper.service 2>/dev/null | grep -q "enabled"; then
        systemctl enable medideals-nifty-scalper.service
        RECOVERY_ACTIONS="${RECOVERY_ACTIONS}• Enabled medideals-nifty-scalper.service\n"
    fi

    if ! systemctl is-active medideals-nifty-scalper.service >/dev/null 2>&1; then
        log_info "Starting medideals-nifty-scalper.service..."
        systemctl restart medideals-nifty-scalper.service
        sleep 5
        RECOVERY_ACTIONS="${RECOVERY_ACTIONS}• Started medideals-nifty-scalper.service\n"
    else
        log_success "Nifty scalper already running"
    fi

    # Step 7: Enable and start Options scalper (downstream of Nifty)
    log "Step 7: Enable and start Options scalper..."
    if ! systemctl is-enabled medideals-options-scalper.service 2>/dev/null | grep -q "enabled"; then
        systemctl enable medideals-options-scalper.service
        RECOVERY_ACTIONS="${RECOVERY_ACTIONS}• Enabled medideals-options-scalper.service\n"
    fi

    if ! systemctl is-active medideals-options-scalper.service >/dev/null 2>&1; then
        log_info "Starting medideals-options-scalper.service..."
        systemctl restart medideals-options-scalper.service
        sleep 5
        RECOVERY_ACTIONS="${RECOVERY_ACTIONS}• Started medideals-options-scalper.service\n"
    else
        log_success "Options scalper already running"
    fi

    # Step 8: Enable and start India scalper (signal-only)
    log "Step 8: Enable and start India scalper..."
    if ! systemctl is-enabled medideals-india-scalper.service 2>/dev/null | grep -q "enabled"; then
        systemctl enable medideals-india-scalper.service
        RECOVERY_ACTIONS="${RECOVERY_ACTIONS}• Enabled medideals-india-scalper.service\n"
    fi

    if ! systemctl is-active medideals-india-scalper.service >/dev/null 2>&1; then
        log_info "Starting medideals-india-scalper.service..."
        systemctl restart medideals-india-scalper.service
        sleep 5
        RECOVERY_ACTIONS="${RECOVERY_ACTIONS}• Started medideals-india-scalper.service\n"
    else
        log_success "India scalper already running"
    fi

    log ""
}

# ──────────────────────────────────────────────────────────────────────────────
# PHASE 7: VERIFY RECOVERY
# ──────────────────────────────────────────────────────────────────────────────

phase_7_verify() {
    log_info "════════════════════════════════════════════════════════════════════"
    log_info "PHASE 7: Verify Recovery"
    log_info "════════════════════════════════════════════════════════════════════"

    local services=(
        "medideals-mt5-bridge"
        "medideals-gold-bot"
        "medideals-forex-scalper"
        "medideals-btc-bot"
        "medideals-nifty-scalper"
        "medideals-options-scalper"
        "medideals-india-scalper"
    )

    local running_count=0
    local failed_services=""

    for svc in "${services[@]}"; do
        if systemctl is-active "${svc}.service" >/dev/null 2>&1; then
            log_success "${svc} is running"
            ((running_count++))
        else
            log_error "${svc} is NOT running"
            failed_services="${failed_services}${svc} "
        fi
    done

    log ""
    log "Running services: $running_count/7"

    if [[ $running_count -eq 7 ]]; then
        log_success "All 7 trading bots are running!"
        FINAL_STATUS="TRADING BOTS RESTORED"
    elif [[ $running_count -gt 0 ]]; then
        log_warn "Partial recovery: $running_count/7 bots running"
        log_warn "Failed services: $failed_services"
        FINAL_STATUS="PARTIAL RECOVERY — $running_count/7 bots running"
    else
        log_error "No services running"
        FINAL_STATUS="RECOVERY FAILED — No services running"
        return 1
    fi

    # Check for crash loops
    log ""
    log "Checking for crash loops (30-second observation)..."
    sleep 30

    local crash_loop_count=0
    for svc in "${services[@]}"; do
        local restarts=$(systemctl show "${svc}.service" -p NRestarts --value 2>/dev/null || echo "0")
        if [[ $restarts -gt 2 ]]; then
            log_warn "${svc} restarted $restarts times (possible crash loop)"
            ((crash_loop_count++))
        fi
    done

    if [[ $crash_loop_count -gt 0 ]]; then
        log_error "Crash loop detected in $crash_loop_count services"
        FINAL_STATUS="BLOCKED — Services in crash loop (see logs)"
        return 1
    fi

    log_success "No crash loops detected"
    log ""
}

# ──────────────────────────────────────────────────────────────────────────────
# FINAL REPORT
# ──────────────────────────────────────────────────────────────────────────────

final_report() {
    log_info "════════════════════════════════════════════════════════════════════"
    log_info "RECOVERY COMPLETE"
    log_info "════════════════════════════════════════════════════════════════════"
    log ""

    log "ROOT CAUSE IDENTIFIED:"
    log "  $ROOT_CAUSE"
    log ""

    if [[ -n "$RECOVERY_ACTIONS" ]]; then
        log "RECOVERY ACTIONS TAKEN:"
        echo -e "  $RECOVERY_ACTIONS" | tee -a "${LOG_FILE}"
    else
        log "RECOVERY ACTIONS: (none needed)"
    fi

    log ""
    log "════════════════════════════════════════════════════════════════════"
    if [[ "$FINAL_STATUS" == "TRADING BOTS RESTORED" ]]; then
        echo -e "${GREEN}${FINAL_STATUS}${NC}" | tee -a "${LOG_FILE}"
    else
        echo -e "${RED}${FINAL_STATUS}${NC}" | tee -a "${LOG_FILE}"
    fi
    log "════════════════════════════════════════════════════════════════════"
    log ""

    log "Log file: ${LOG_FILE}"
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ──────────────────────────────────────────────────────────────────────────────

main() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root"
        exit 1
    fi

    log "MediDeals Recovery Diagnostic Starting"
    log "Timestamp: $TIMESTAMP"
    log ""

    phase_1_server_state
    phase_2_service_status
    phase_3_process_check
    phase_4_credentials_check || true
    phase_5_root_cause
    phase_6_auto_recovery || true
    phase_7_verify || true
    final_report

    # Return appropriate exit code
    if [[ "$FINAL_STATUS" == "TRADING BOTS RESTORED" ]]; then
        exit 0
    else
        exit 1
    fi
}

# Run main
main "$@"
