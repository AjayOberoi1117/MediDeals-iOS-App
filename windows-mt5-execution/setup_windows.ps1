# Windows MT5 Execution Environment Setup
# Run this in PowerShell as Administrator

Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║        Windows MT5 Execution Environment Setup                  ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check Python installation
Write-Host "Checking Python installation..." -ForegroundColor Yellow
$python = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $python) {
    Write-Host "ERROR: Python not found in PATH" -ForegroundColor Red
    Write-Host "Please install Python 3.9+ from https://www.python.org/" -ForegroundColor Red
    exit 1
}

$pythonVersion = & python --version
Write-Host "✅ Found: $pythonVersion" -ForegroundColor Green
Write-Host ""

# Check for 64-bit Python (required for MetaTrader5)
$pythonExe = (Get-Command python).Source
$pythonArchitecture = & python -c "import struct; print('64-bit' if struct.calcsize('P') == 8 else '32-bit')"
Write-Host "   Architecture: $pythonArchitecture" -ForegroundColor Green
if ($pythonArchitecture -ne "64-bit") {
    Write-Host "   WARNING: MetaTrader5 requires 64-bit Python" -ForegroundColor Yellow
}
Write-Host ""

# Create virtual environment
Write-Host "Creating Python virtual environment..." -ForegroundColor Yellow
if (Test-Path "venv") {
    Write-Host "Virtual environment already exists" -ForegroundColor Cyan
} else {
    & python -m venv venv
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Virtual environment created" -ForegroundColor Green
    } else {
        Write-Host "ERROR: Failed to create virtual environment" -ForegroundColor Red
        exit 1
    }
}
Write-Host ""

# Activate virtual environment
Write-Host "Activating virtual environment..." -ForegroundColor Yellow
& ".\venv\Scripts\Activate.ps1"
Write-Host "✅ Virtual environment activated" -ForegroundColor Green
Write-Host ""

# Install dependencies
Write-Host "Installing required packages..." -ForegroundColor Yellow
& pip install --upgrade pip setuptools wheel
& pip install -r requirements-windows.txt
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Packages installed successfully" -ForegroundColor Green
} else {
    Write-Host "ERROR: Failed to install packages" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Verify MetaTrader5 installation
Write-Host "Verifying MetaTrader5 package..." -ForegroundColor Yellow
& python -c "import MetaTrader5; print(f'MetaTrader5 version: {MetaTrader5.__version__}')" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ MetaTrader5 package verified" -ForegroundColor Green
} else {
    Write-Host "WARNING: Could not verify MetaTrader5 (may require MT5 terminal installed)" -ForegroundColor Yellow
}
Write-Host ""

# Check for .env file
Write-Host "Checking configuration..." -ForegroundColor Yellow
if (Test-Path ".env") {
    Write-Host "✅ .env file exists" -ForegroundColor Green
} else {
    Write-Host "⚠️  .env file not found" -ForegroundColor Yellow
    Write-Host "   Creating .env from .env.example..." -ForegroundColor Cyan
    Copy-Item ".env.example" ".env"
    Write-Host "✅ .env created (edit with your credentials)" -ForegroundColor Green
}
Write-Host ""

Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                    Setup Complete!                              ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Edit .env file with your MT5 credentials:" -ForegroundColor White
Write-Host "   notepad .env" -ForegroundColor Cyan
Write-Host ""
Write-Host "2. Verify MT5 connection:" -ForegroundColor White
Write-Host "   python verify_mt5_connection.py" -ForegroundColor Cyan
Write-Host ""
Write-Host "3. Verify symbol availability:" -ForegroundColor White
Write-Host "   python verify_symbol_specs.py" -ForegroundColor Cyan
Write-Host ""
Write-Host "4. Test order preflight:" -ForegroundColor White
Write-Host "   python verify_order_check.py" -ForegroundColor Cyan
Write-Host ""
Write-Host "5. Start executor (signal-only mode by default):" -ForegroundColor White
Write-Host "   python windows_mt5_executor.py" -ForegroundColor Cyan
Write-Host ""
Write-Host "⚠️  IMPORTANT:" -ForegroundColor Yellow
Write-Host "   - Default mode is 'signal_only' (no orders placed)" -ForegroundColor White
Write-Host "   - Production trading requires both:" -ForegroundColor White
Write-Host "     • BOT_EXECUTION_MODE=production in .env" -ForegroundColor Cyan
Write-Host "     • LIVE_TRADING_CONFIRMED=YES in .env" -ForegroundColor Cyan
Write-Host ""
