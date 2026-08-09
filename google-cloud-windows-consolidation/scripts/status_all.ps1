# Check status of all trading bots
# Run from: C:\TradingBots\scripts\

$ErrorActionPreference = "Continue"
$TRADING_ROOT = "C:\TradingBots"
$LOGS_DIR = "$TRADING_ROOT\logs"

# Color output
function Write-Online { Write-Host $args[0] -ForegroundColor Green }
function Write-Offline { Write-Host $args[0] -ForegroundColor Red }
function Write-Info { Write-Host $args[0] -ForegroundColor Cyan }

Write-Info "=== Trading Bots Status ==="
Write-Info ""

# Bots to check
$Bots = @(
    @{ Name = "BTC Bot"; Script = "btc_bot_windows.py"; Log = "$LOGS_DIR\btc_bot.log" },
    @{ Name = "GOLD Bot"; Script = "gold_bot_windows.py"; Log = "$LOGS_DIR\gold_bot.log" },
    @{ Name = "Forex Scalper"; Script = "forex_scalper_windows.py"; Log = "$LOGS_DIR\forex_scalper.log" }
)

$RunningCount = 0

foreach ($Bot in $Bots) {
    $Process = Get-Process python -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*$($Bot.Script)*" }

    if ($Process) {
        Write-Online "✓ $($Bot.Name) - RUNNING (PID: $($Process.Id))"
        $RunningCount++

        # Show last log line
        if (Test-Path $Bot.Log) {
            $LastLine = Get-Content $Bot.Log -Tail 1
            Write-Info "  Last log: $LastLine"
        }
    } else {
        Write-Offline "✗ $($Bot.Name) - STOPPED"
    }

    Write-Info ""
}

Write-Info "=== Summary ==="
Write-Info "Running: $RunningCount / 3 bots"
Write-Info ""
Write-Info "Log directory: $LOGS_DIR"
Write-Info "View logs with: Get-Content <logfile> -Tail 20 -Wait"
