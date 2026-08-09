# Stop all trading bots
# Run from: C:\TradingBots\scripts\

$ErrorActionPreference = "Continue"

# Color output
function Write-Success { Write-Host $args[0] -ForegroundColor Green }
function Write-Error-Red { Write-Host $args[0] -ForegroundColor Red }
function Write-Info { Write-Host $args[0] -ForegroundColor Cyan }

Write-Info "=== Stopping Trading Bots ==="
Write-Info ""

# Bots to stop
$BotPatterns = @(
    "btc_bot_windows.py",
    "gold_bot_windows.py",
    "forex_scalper_windows.py"
)

foreach ($Pattern in $BotPatterns) {
    $Processes = Get-Process python -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*$Pattern*" }

    if ($Processes) {
        foreach ($Process in $Processes) {
            Write-Info "Stopping: $Pattern (PID: $($Process.Id))"
            try {
                Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
                Write-Success "  ✓ Stopped"
            }
            catch {
                Write-Error-Red "  ✗ Error stopping: $_"
            }
        }
    } else {
        Write-Info "$Pattern: not running"
    }
}

Write-Info ""
Write-Info "=== All bots stopped ==="
