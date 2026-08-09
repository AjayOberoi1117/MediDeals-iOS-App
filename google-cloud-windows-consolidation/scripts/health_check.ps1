# ─────────────────────────────────────────────────────────────────────────────
# Trading Stack Health Check
# ─────────────────────────────────────────────────────────────────────────────
# Purpose: Comprehensive status report of all trading components
# Output: Human-readable status with timestamps and diagnostics
#
# Usage: .\health_check.ps1
# ─────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = "SilentlyContinue"

$TRADING_BOTS_ROOT = "C:\TradingBots"
$LOGS_DIR = Join-Path $TRADING_BOTS_ROOT "logs"
$STATE_DIR = Join-Path $TRADING_BOTS_ROOT "state"
$QUEUE_FILE = Join-Path $STATE_DIR ".trade_queue.jsonl"
$HISTORY_FILE = Join-Path $STATE_DIR ".trade_history.jsonl"

# ─── Formatting ────────────────────────────────────────────────────────────
function Write-Status {
    param(
        [string]$Component,
        [string]$Status,
        [string]$Details = "",
        [string]$Color = "Gray"
    )

    $status_symbol = switch ($Status) {
        "RUNNING" { "✓ " }
        "DOWN" { "✗ " }
        "IDLE" { "◯ " }
        "PASS" { "✓ " }
        "FAIL" { "✗ " }
        "UNKNOWN" { "? " }
        default { "• " }
    }

    if ($Details) {
        Write-Host "  $status_symbol$Component`: $Status | $Details" -ForegroundColor $Color
    } else {
        Write-Host "  $status_symbol$Component`: $Status" -ForegroundColor $Color
    }
}

function Get-ProcessStatus {
    param([string]$ProcessName)

    $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if ($null -ne $process) {
        return "RUNNING"
    }
    return "DOWN"
}

function Get-LastLogLine {
    param([string]$LogPath)

    if (-not (Test-Path $LogPath)) {
        return $null
    }

    try {
        $content = Get-Content -Path $LogPath -Tail 1 -ErrorAction SilentlyContinue
        if ($content) {
            # Extract timestamp if available (format: YYYY-MM-DD HH:MM:SS)
            if ($content -match "(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})") {
                return $matches[1]
            }
        }
    } catch {
        return $null
    }

    return $null
}

function Get-QueuePending {
    if (-not (Test-Path $QUEUE_FILE)) {
        return 0
    }

    try {
        $lines = @(Get-Content -Path $QUEUE_FILE 2>$null)
        return $lines.Count
    } catch {
        return 0
    }
}

function Get-LastSignal {
    if (-not (Test-Path $HISTORY_FILE)) {
        return $null
    }

    try {
        $content = Get-Content -Path $HISTORY_FILE -Tail 1 -ErrorAction SilentlyContinue
        if ($content) {
            return $content
        }
    } catch {
        return $null
    }

    return $null
}

function Get-SystemResources {
    $cpu_usage = 0
    try {
        $cpu_counter = Get-Counter "\Processor(_Total)\% Processor Time" -ErrorAction SilentlyContinue
        $cpu_usage = [math]::Round($cpu_counter.CounterSamples[0].CookedValue, 1)
    } catch {
        $cpu_usage = "N/A"
    }

    $ram_total = 0
    $ram_free = 0
    try {
        $ram_total = (Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory / 1GB
        $ram_free = (Get-CimInstance -ClassName Win32_OperatingSystem).FreePhysicalMemory / 1MB
        $ram_total = [math]::Round($ram_total, 1)
        $ram_free = [math]::Round($ram_free, 1)
    } catch {
        $ram_total = "N/A"
        $ram_free = "N/A"
    }

    $disk_free = 0
    try {
        $disk_c = Get-PSDrive -Name C -ErrorAction SilentlyContinue
        $disk_free = [math]::Round($disk_c.Free / 1GB, 1)
    } catch {
        $disk_free = "N/A"
    }

    return @{
        CPU = $cpu_usage
        RAM_Total = $ram_total
        RAM_Free = $ram_free
        Disk_Free = $disk_free
    }
}

function Get-TelegramStatus {
    $env_file = Join-Path $TRADING_BOTS_ROOT ".env"
    if (-not (Test-Path $env_file)) {
        return "UNCONFIGURED"
    }

    try {
        $content = Get-Content -Path $env_file
        $has_token = $content | Select-String -Pattern "TELEGRAM_BOT_TOKEN=" | Where-Object { $_ -notmatch "^#" -and $_ -notmatch "=$" }
        $has_chat = $content | Select-String -Pattern "TELEGRAM_CHAT_ID=" | Where-Object { $_ -notmatch "^#" -and $_ -notmatch "=$" }

        if ($null -ne $has_token -and $null -ne $has_chat) {
            return "CONFIGURED"
        }
    } catch {
        return "UNKNOWN"
    }

    return "UNCONFIGURED"
}

function Get-ExecutionMode {
    $env_file = Join-Path $TRADING_BOTS_ROOT ".env"
    if (-not (Test-Path $env_file)) {
        return "unknown"
    }

    try {
        $content = Get-Content -Path $env_file
        $mode = $content | Select-String -Pattern "BOT_EXECUTION_MODE=" | Select-Object -First 1
        if ($mode -match "=(.+)") {
            return $matches[1].Trim().ToLower()
        }
    } catch {
        return "unknown"
    }

    return "unknown"
}

function Test-IsWeekend {
    $now = Get-Date
    $ist_tz = [TimeZoneInfo]::FindSystemTimeZoneById("India Standard Time")
    $ist_time = [TimeZoneInfo]::ConvertTime($now, $ist_tz)

    return $ist_time.DayOfWeek -ge [DayOfWeek]::Saturday
}

# ─── Main Health Check ─────────────────────────────────────────────────────
function Main {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║             TRADING STACK HEALTH CHECK                        ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host "Root: $TRADING_BOTS_ROOT" -ForegroundColor Gray
    Write-Host ""

    # ─── MT5 Status ────────────────────────────────────────────────────────
    Write-Host "MT5 TERMINAL" -ForegroundColor Cyan
    $mt5_status = Get-ProcessStatus "terminal64"
    Write-Status "Process" $mt5_status "" $(if ($mt5_status -eq "RUNNING") { "Green" } else { "Red" })

    # Try to verify MT5 connection
    $executor_dir = Join-Path $TRADING_BOTS_ROOT "executor"
    $verify_script = Join-Path $executor_dir "verify_mt5_connection.py"
    if (Test-Path $verify_script) {
        $verify_result = & python $verify_script 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Status "Connection" "PASS" "" "Green"
            Write-Status "Account" "ACCESSIBLE" "" "Green"
        } else {
            Write-Status "Connection" "FAIL" "Verify manually or check .env" "Red"
            Write-Status "Account" "INACCESSIBLE" "" "Red"
        }
    }
    Write-Host ""

    # ─── BTC Bot ────────────────────────────────────────────────────────────
    Write-Host "BTC BOT (BTCUSD 1H)" -ForegroundColor Cyan
    $btc_status = Get-ProcessStatus "python"
    $btc_log = Join-Path $LOGS_DIR "btc_bot.log"
    $btc_ts = Get-LastLogLine $btc_log
    Write-Status "Process" $btc_status "" $(if ($btc_status -eq "RUNNING") { "Green" } else { "Yellow" })
    if ($btc_ts) {
        Write-Status "Last Activity" "OK" $btc_ts "Gray"
    } else {
        Write-Status "Last Activity" "UNKNOWN" "No logs yet" "Gray"
    }
    Write-Host ""

    # ─── GOLD Bot ───────────────────────────────────────────────────────────
    Write-Host "GOLD BOT (XAUUSD 1H)" -ForegroundColor Cyan
    $gold_status = Get-ProcessStatus "python"
    $gold_log = Join-Path $LOGS_DIR "gold_bot.log"
    $gold_ts = Get-LastLogLine $gold_log
    Write-Status "Process" $gold_status "" $(if ($gold_status -eq "RUNNING") { "Green" } else { "Yellow" })
    if ($gold_ts) {
        Write-Status "Last Activity" "OK" $gold_ts "Gray"
    } else {
        Write-Status "Last Activity" "UNKNOWN" "No logs yet" "Gray"
    }
    Write-Host ""

    # ─── Forex Scalper ──────────────────────────────────────────────────────
    Write-Host "FOREX SCALPER (EUR/GBP 15m)" -ForegroundColor Cyan
    $forex_status = Get-ProcessStatus "python"
    $is_weekend = Test-IsWeekend
    if ($is_weekend) {
        $forex_display = "WEEKEND-IDLE"
        $forex_color = "Yellow"
    } else {
        $forex_display = $forex_status
        $forex_color = $(if ($forex_status -eq "RUNNING") { "Green" } else { "Red" })
    }
    Write-Status "Process" $forex_display "" $forex_color
    $forex_log = Join-Path $LOGS_DIR "forex_scalper.log"
    $forex_ts = Get-LastLogLine $forex_log
    if ($forex_ts) {
        Write-Status "Last Activity" "OK" $forex_ts "Gray"
    } else {
        Write-Status "Last Activity" "UNKNOWN" "No logs yet" "Gray"
    }
    Write-Host ""

    # ─── Executor ───────────────────────────────────────────────────────────
    Write-Host "MT5 EXECUTOR" -ForegroundColor Cyan
    $executor_status = Get-ProcessStatus "python"
    Write-Status "Process" $executor_status "" $(if ($executor_status -eq "RUNNING") { "Green" } else { "Yellow" })
    $executor_log = Join-Path $LOGS_DIR "mt5_executor.log"
    $executor_ts = Get-LastLogLine $executor_log
    if ($executor_ts) {
        Write-Status "Last Activity" "OK" $executor_ts "Gray"
    } else {
        Write-Status "Last Activity" "UNKNOWN" "No logs yet" "Gray"
    }
    Write-Host ""

    # ─── Trade Queue ────────────────────────────────────────────────────────
    Write-Host "TRADE QUEUE" -ForegroundColor Cyan
    Write-Status "Path" "OK" $QUEUE_FILE "Gray"
    $pending = Get-QueuePending
    Write-Status "Pending" "OK" "$pending signals in queue" $(if ($pending -gt 0) { "Yellow" } else { "Green" })
    Write-Host ""

    # ─── Configuration ──────────────────────────────────────────────────────
    Write-Host "CONFIGURATION" -ForegroundColor Cyan
    $mode = Get-ExecutionMode
    $mode_color = switch ($mode) {
        "production" { "Red" }
        "signal_only" { "Green" }
        "dry_run" { "Yellow" }
        default { "Gray" }
    }
    Write-Status "Execution Mode" $mode "" $mode_color
    $tg_status = Get-TelegramStatus
    Write-Status "Telegram" $tg_status "" $(if ($tg_status -eq "CONFIGURED") { "Green" } else { "Yellow" })
    Write-Host ""

    # ─── System Resources ───────────────────────────────────────────────────
    Write-Host "SYSTEM RESOURCES" -ForegroundColor Cyan
    $resources = Get-SystemResources
    $cpu_color = if ($resources.CPU -gt 80) { "Red" } elseif ($resources.CPU -gt 50) { "Yellow" } else { "Green" }
    $ram_color = if ($resources.RAM_Free -lt 1) { "Red" } elseif ($resources.RAM_Free -lt 2) { "Yellow" } else { "Green" }
    $disk_color = if ($resources.Disk_Free -lt 2) { "Red" } elseif ($resources.Disk_Free -lt 5) { "Yellow" } else { "Green" }

    Write-Status "CPU Usage" "$($resources.CPU)%" "" $cpu_color
    Write-Status "RAM" "$($resources.RAM_Free)GB free / $($resources.RAM_Total)GB total" "" $ram_color
    Write-Status "Disk C:" "$($resources.Disk_Free)GB free" "" $disk_color
    Write-Host ""

    # ─── Commands Reference ─────────────────────────────────────────────────
    Write-Host "COMMANDS" -ForegroundColor Cyan
    Write-Host "  Startup:   .\startup_with_executor.ps1" -ForegroundColor Gray
    Write-Host "  Stop:      .\stop_all.ps1" -ForegroundColor Gray
    Write-Host "  Restart:   .\restart_all.ps1" -ForegroundColor Gray
    Write-Host "  Status:    .\status_all.ps1" -ForegroundColor Gray
    Write-Host "  Health:    .\health_check.ps1 (this script)" -ForegroundColor Gray
    Write-Host "  View logs: Get-Content $LOGS_DIR\*.log -Wait" -ForegroundColor Gray
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
}

Main
