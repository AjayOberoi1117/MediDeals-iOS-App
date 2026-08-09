# ─────────────────────────────────────────────────────────────────────────────
# Windows MT5 Trading Stack Startup with Executor
# ─────────────────────────────────────────────────────────────────────────────
# Purpose: Safe orchestrated startup of all trading components
# 1. Verify directory structure
# 2. Prevent duplicate processes
# 3. Start MT5 terminal
# 4. Verify MT5 readiness
# 5. Start all 3 bots + executor
# 6. Log startup results
#
# Usage: .\startup_with_executor.ps1 [MT5_TERMINAL_PATH]
# ─────────────────────────────────────────────────────────────────────────────

param(
    [string]$MT5TerminalPath = "C:\Program Files\MetaTrader 5\terminal64.exe"
)

$ErrorActionPreference = "Continue"

$TRADING_BOTS_ROOT = "C:\TradingBots"
$LOGS_DIR = Join-Path $TRADING_BOTS_ROOT "logs"
$STATE_DIR = Join-Path $TRADING_BOTS_ROOT "state"
$BOTS_DIR = Join-Path $TRADING_BOTS_ROOT "bots"
$EXECUTOR_DIR = Join-Path $TRADING_BOTS_ROOT "executor"
$STARTUP_LOG = Join-Path $LOGS_DIR "startup.log"

$TIMEOUT_SECONDS = 60
$MT5_READY_TIMEOUT = 30

# ─── Logging ───────────────────────────────────────────────────────────────
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp | $Level | $Message"
    Write-Host $logEntry
    Add-Content -Path $STARTUP_LOG -Value $logEntry -ErrorAction SilentlyContinue
}

# ─── Directory Setup ───────────────────────────────────────────────────────
function Initialize-Directories {
    Write-Log "Initializing directories..."

    try {
        if (-not (Test-Path $LOGS_DIR)) {
            New-Item -ItemType Directory -Path $LOGS_DIR -Force | Out-Null
            Write-Log "Created logs directory: $LOGS_DIR" "INFO"
        }

        if (-not (Test-Path $STATE_DIR)) {
            New-Item -ItemType Directory -Path $STATE_DIR -Force | Out-Null
            Write-Log "Created state directory: $STATE_DIR" "INFO"
        }

        return $true
    } catch {
        Write-Log "Directory initialization failed: $_" "ERROR"
        return $false
    }
}

# ─── Duplicate Process Detection ───────────────────────────────────────────
function Stop-DuplicateProcesses {
    Write-Log "Checking for duplicate processes..."

    $python_procs = Get-Process python -ErrorAction SilentlyContinue
    if ($null -eq $python_procs) {
        Write-Log "No existing Python processes found" "INFO"
        return $true
    }

    if ($python_procs -is [array]) {
        Write-Log "Found $($python_procs.Count) Python processes running" "WARNING"
        Write-Log "Stopping existing bot processes..."
        try {
            Stop-Process -InputObject $python_procs -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Write-Log "Existing processes stopped" "INFO"
        } catch {
            Write-Log "Error stopping existing processes: $_" "WARNING"
        }
    }

    return $true
}

# ─── MT5 Terminal Startup ──────────────────────────────────────────────────
function Start-MT5Terminal {
    Write-Log "Starting MetaTrader 5 terminal..."

    if (-not (Test-Path $MT5TerminalPath)) {
        Write-Log "MT5 terminal not found at: $MT5TerminalPath" "ERROR"
        Write-Log "Expected path: $MT5TerminalPath" "INFO"
        Write-Log "If MT5 is installed elsewhere, pass path: .\startup_with_executor.ps1 'C:\Path\To\terminal64.exe'" "INFO"
        return $false
    }

    $mt5_procs = Get-Process terminal64 -ErrorAction SilentlyContinue
    if ($null -ne $mt5_procs) {
        Write-Log "MT5 terminal already running (PID: $($mt5_procs.Id))" "INFO"
        return $true
    }

    try {
        $process = Start-Process -FilePath $MT5TerminalPath -WindowStyle Minimized -PassThru
        Write-Log "MT5 terminal started (PID: $($process.Id))" "INFO"
        Start-Sleep -Seconds 5
        return $true
    } catch {
        Write-Log "Failed to start MT5 terminal: $_" "ERROR"
        return $false
    }
}

# ─── MT5 Readiness Verification ────────────────────────────────────────────
function Wait-ForMT5Ready {
    Write-Log "Waiting for MT5 to become ready (timeout: ${MT5_READY_TIMEOUT}s)..."

    $verifier = Join-Path $EXECUTOR_DIR "verify_mt5_connection.py"
    if (-not (Test-Path $verifier)) {
        Write-Log "MT5 verifier not found: $verifier" "WARNING"
        Write-Log "Assuming MT5 ready (cannot verify in sandbox)" "INFO"
        return $true
    }

    $start_time = Get-Date
    $max_wait = $start_time.AddSeconds($MT5_READY_TIMEOUT)

    while ((Get-Date) -lt $max_wait) {
        try {
            $output = python $verifier 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "MT5 verification passed" "INFO"
                return $true
            }
        } catch {
            # Continue waiting
        }

        Start-Sleep -Seconds 3
        Write-Log "MT5 not yet ready, waiting..." "INFO"
    }

    Write-Log "MT5 readiness timeout after ${MT5_READY_TIMEOUT}s" "WARNING"
    Write-Log "Proceeding with caution - verify manually if needed" "WARNING"
    return $false
}

# ─── Bot Startup ───────────────────────────────────────────────────────────
function Start-Bot {
    param(
        [string]$BotName,
        [string]$BotScript
    )

    $bot_path = Join-Path $BOTS_DIR $BotScript
    if (-not (Test-Path $bot_path)) {
        Write-Log "Bot not found: $bot_path" "ERROR"
        return $null
    }

    try {
        Write-Log "Starting $BotName..."
        $process = Start-Process -FilePath "python.exe" -ArgumentList "-u `"$bot_path`"" `
            -WorkingDirectory $TRADING_BOTS_ROOT `
            -WindowStyle Hidden `
            -PassThru `
            -ErrorAction Stop

        Write-Log "$BotName started (PID: $($process.Id))" "INFO"
        Start-Sleep -Seconds 1
        return $process.Id
    } catch {
        Write-Log "Failed to start $BotName`: $_" "ERROR"
        return $null
    }
}

# ─── Executor Startup ──────────────────────────────────────────────────────
function Start-Executor {
    $executor_path = Join-Path $EXECUTOR_DIR "windows_mt5_executor.py"
    if (-not (Test-Path $executor_path)) {
        Write-Log "Executor not found: $executor_path" "ERROR"
        return $null
    }

    try {
        Write-Log "Starting MT5 Executor..."
        $process = Start-Process -FilePath "python.exe" -ArgumentList "-u `"$executor_path`"" `
            -WorkingDirectory $TRADING_BOTS_ROOT `
            -WindowStyle Hidden `
            -PassThru `
            -ErrorAction Stop

        Write-Log "Executor started (PID: $($process.Id))" "INFO"
        Start-Sleep -Seconds 1
        return $process.Id
    } catch {
        Write-Log "Failed to start Executor: $_" "ERROR"
        return $null
    }
}

# ─── Main Startup Sequence ─────────────────────────────────────────────────
function Main {
    Write-Log "═══════════════════════════════════════════════════════════════" "INFO"
    Write-Log "TRADING STACK STARTUP WITH EXECUTOR" "INFO"
    Write-Log "═══════════════════════════════════════════════════════════════" "INFO"
    Write-Log "Root: $TRADING_BOTS_ROOT" "INFO"
    Write-Log "MT5 Terminal: $MT5TerminalPath" "INFO"

    # Initialize
    if (-not (Initialize-Directories)) {
        Write-Log "Directory initialization failed" "ERROR"
        exit 1
    }

    # Cleanup
    if (-not (Stop-DuplicateProcesses)) {
        Write-Log "Failed to stop duplicate processes" "ERROR"
        exit 1
    }

    # Start MT5
    if (-not (Start-MT5Terminal)) {
        Write-Log "Failed to start MT5 terminal" "ERROR"
        exit 1
    }

    # Verify MT5
    if (-not (Wait-ForMT5Ready)) {
        Write-Log "MT5 readiness verification inconclusive" "WARNING"
    }

    # Start bots
    $btc_pid = Start-Bot "BTC Bot" "btc_bot_windows.py"
    if ($null -eq $btc_pid) {
        Write-Log "Failed to start BTC bot" "ERROR"
        exit 1
    }

    $gold_pid = Start-Bot "GOLD Bot" "gold_bot_windows.py"
    if ($null -eq $gold_pid) {
        Write-Log "Failed to start GOLD bot" "ERROR"
        exit 1
    }

    $forex_pid = Start-Bot "Forex Scalper" "forex_scalper_windows.py"
    if ($null -eq $forex_pid) {
        Write-Log "Failed to start Forex scalper" "ERROR"
        exit 1
    }

    # Start executor
    $executor_pid = Start-Executor
    if ($null -eq $executor_pid) {
        Write-Log "Failed to start executor" "ERROR"
        exit 1
    }

    # Summary
    Write-Log "═══════════════════════════════════════════════════════════════" "INFO"
    Write-Log "STARTUP COMPLETE" "INFO"
    Write-Log "═══════════════════════════════════════════════════════════════" "INFO"
    Write-Log "BTC Bot: PID $btc_pid | Log: $LOGS_DIR\btc_bot.log" "INFO"
    Write-Log "GOLD Bot: PID $gold_pid | Log: $LOGS_DIR\gold_bot.log" "INFO"
    Write-Log "Forex Scalper: PID $forex_pid | Log: $LOGS_DIR\forex_scalper.log" "INFO"
    Write-Log "Executor: PID $executor_pid | Log: $LOGS_DIR\mt5_executor.log" "INFO"
    Write-Log "" "INFO"
    Write-Log "Monitor logs: Get-Content $LOGS_DIR\*.log -Wait" "INFO"
    Write-Log "Health check: .\status_all.ps1" "INFO"
    Write-Log "Stop all: .\stop_all.ps1" "INFO"

    exit 0
}

Main
