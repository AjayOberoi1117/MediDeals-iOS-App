# Start all trading bots and MT5 executor
# Run from: C:\TradingBots\scripts\

$ErrorActionPreference = "Continue"
$TRADING_ROOT = "C:\TradingBots"
$BOTS_DIR = "$TRADING_ROOT\bots"
$LOGS_DIR = "$TRADING_ROOT\logs"
$VENV = "$TRADING_ROOT\venv\Scripts\python.exe"

# Ensure directories exist
New-Item -ItemType Directory -Path $LOGS_DIR -Force | Out-Null

# Color output
function Write-Success { Write-Host $args[0] -ForegroundColor Green }
function Write-Error-Red { Write-Host $args[0] -ForegroundColor Red }
function Write-Info { Write-Host $args[0] -ForegroundColor Cyan }

Write-Info "=== Trading Bots Startup ==="
Write-Info "Python: $VENV"
Write-Info "Logs: $LOGS_DIR"
Write-Info ""

# Function to start a bot
function Start-Bot {
    param(
        [string]$BotScript,
        [string]$BotName,
        [string]$LogFile
    )

    if (-not (Test-Path $BotScript)) {
        Write-Error-Red "ERROR: $BotScript not found"
        return $false
    }

    Write-Info "Starting $BotName..."
    $FullLogPath = "$LogFile"

    # Start bot in background using pythonw.exe (no console window)
    $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
    $ProcessInfo.FileName = $VENV
    $ProcessInfo.Arguments = "`"$BotScript`""
    $ProcessInfo.RedirectStandardOutput = $false
    $ProcessInfo.RedirectStandardError = $false
    $ProcessInfo.UseShellExecute = $false
    $ProcessInfo.CreateNoWindow = $true
    $ProcessInfo.WorkingDirectory = $TRADING_ROOT

    try {
        $Process = [System.Diagnostics.Process]::Start($ProcessInfo)
        Start-Sleep -Milliseconds 500

        if ($null -eq $Process -or $Process.HasExited) {
            Write-Error-Red "  ✗ Failed to start $BotName"
            return $false
        } else {
            Write-Success "  ✓ $BotName started (PID: $($Process.Id))"
            return $true
        }
    }
    catch {
        Write-Error-Red "  ✗ Error starting $BotName : $_"
        return $false
    }
}

# Start all bots
$Results = @()
$Results += Start-Bot "$BOTS_DIR\btc_bot_windows.py" "BTC Bot" "$LOGS_DIR\btc_bot.log"
Start-Sleep -Seconds 2

$Results += Start-Bot "$BOTS_DIR\gold_bot_windows.py" "GOLD Bot" "$LOGS_DIR\gold_bot.log"
Start-Sleep -Seconds 2

$Results += Start-Bot "$BOTS_DIR\forex_scalper_windows.py" "Forex Scalper" "$LOGS_DIR\forex_scalper.log"
Start-Sleep -Seconds 2

# Summary
Write-Info ""
Write-Info "=== Startup Summary ==="
$SuccessCount = ($Results | Where-Object { $_ -eq $true }).Count
Write-Info "Started: $SuccessCount / 3 bots"

if ($SuccessCount -eq 3) {
    Write-Success "✓ All bots started successfully"
} else {
    Write-Error-Red "✗ Some bots failed to start. Check logs in $LOGS_DIR"
}

Write-Info ""
Write-Info "Log files:"
Write-Info "  - $LOGS_DIR\btc_bot.log"
Write-Info "  - $LOGS_DIR\gold_bot.log"
Write-Info "  - $LOGS_DIR\forex_scalper.log"
Write-Info ""
Write-Info "To view logs: Get-Content <logfile> -Wait"
