# Restart all trading bots
# Run from: C:\TradingBots\scripts\

$ErrorActionPreference = "Continue"
$ScriptsDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=== Restarting Trading Bots ===" -ForegroundColor Cyan
Write-Host ""

# Stop all bots
Write-Host "Stopping all bots..." -ForegroundColor Yellow
& "$ScriptsDir\stop_all.ps1"

Start-Sleep -Seconds 3

# Start all bots
Write-Host ""
Write-Host "Starting all bots..." -ForegroundColor Yellow
& "$ScriptsDir\start_all.ps1"

Write-Host ""
Write-Host "=== Restart Complete ===" -ForegroundColor Cyan
