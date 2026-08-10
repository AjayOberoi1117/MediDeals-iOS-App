# Google Cloud Windows Trading Stack - Complete Installation and Deployment
# Purpose: Deploy trading bot stack from scratch on Windows Server 2025
# Compatibility: Windows PowerShell 5.1+ (ASCII-only, no Unicode)
# Usage: .\install-and-deploy.ps1

param(
    [switch]$EnableSignalBots,
    [switch]$EnableExecutor,
    [switch]$InstallStartupTask
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# Global Configuration
$TRADING_ROOT = "C:\TradingBots"
$REPO_URL = "https://github.com/AjayOberoi1117/MediDeals-iOS-App.git"
$REPO_BRANCH = "claude/bots-trade-signals-debug-wjevgt"
$PACKAGE_NAME = "google-cloud-windows-consolidation"
$VENV_DIR = "$TRADING_ROOT\.venv"
$LOG_DIR = "$TRADING_ROOT\logs"
$STATE_DIR = "$TRADING_ROOT\state"
$QUEUE_FILE = "$STATE_DIR\.trade_queue.jsonl"
$DEPLOY_LOG = "$LOG_DIR\install-deploy.log"
. "$PSScriptRoot\scripts\mt5_paths.ps1"

# Utility Functions
function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "=============================================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "=============================================================" -ForegroundColor Cyan
    if (Test-Path $LOG_DIR) {
        Add-Content -Path $DEPLOY_LOG -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $Message"
    }
}

function Write-Status {
    param(
        [string]$Component,
        [string]$Status,
        [string]$Details = ""
    )

    $status_color = "White"
    $status_symbol = "?"

    if ($Status -eq "PASS") {
        $status_color = "Green"
        $status_symbol = "[PASS]"
    }
    elseif ($Status -eq "FAIL") {
        $status_color = "Red"
        $status_symbol = "[FAIL]"
    }
    elseif ($Status -eq "WARN") {
        $status_color = "Yellow"
        $status_symbol = "[WARN]"
    }
    elseif ($Status -eq "INFO") {
        $status_color = "Gray"
        $status_symbol = "[INFO]"
    }
    elseif ($Status -eq "SKIP") {
        $status_color = "Cyan"
        $status_symbol = "[SKIP]"
    }

    if ($Details) {
        Write-Host "  $status_symbol $Component`: $Details" -ForegroundColor $status_color
    } else {
        Write-Host "  $status_symbol $Component" -ForegroundColor $status_color
    }

    if (Test-Path $LOG_DIR) {
        Add-Content -Path $DEPLOY_LOG -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $Component`: $Status | $Details"
    }
}

function Write-Fatal {
    param([string]$Message)
    Write-Host ""
    Write-Host "=============================================================" -ForegroundColor Red
    Write-Host "FATAL ERROR" -ForegroundColor Red
    Write-Host "=============================================================" -ForegroundColor Red
    Write-Host $Message -ForegroundColor Red
    Write-Host ""
    exit 1
}

function Ensure-Admin {
    $is_admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($is_admin -eq $false) {
        Write-Fatal "This script requires Administrator privileges. Right-click PowerShell and select Run as Administrator."
    }
}

function Ensure-Directory {
    param([string]$Path)
    if ((Test-Path $Path) -eq $false) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# Step 1: Admin and Logging
Write-Header "INITIALIZATION"
Ensure-Admin
Write-Status "Administrator" "PASS"

Ensure-Directory $LOG_DIR
Write-Status "Log Directory" "PASS" $LOG_DIR

# Step 2: Python PATH Fix
Write-Header "STEP 1: PYTHON 3.12 PATH CORRECTION"

$python_works = $false
try {
    $python_ver = python --version 2>&1
    if ($python_ver -like "*3.12*") {
        Write-Status "Python" "PASS" $python_ver
        $python_works = $true
    }
}
catch {
    Write-Status "Python" "WARN" "Attempting to fix PATH"
}

if ($python_works -eq $false) {
    $possible_paths = @(
        "C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python312",
        "C:\Program Files\Python312",
        "C:\Program Files (x86)\Python312"
    )

    $python_exe = $null
    foreach ($path in $possible_paths) {
        if (Test-Path "$path\python.exe") {
            $python_exe = "$path\python.exe"
            break
        }
    }

    if ($python_exe) {
        # Disable Microsoft Store alias
        try {
            Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Aliases\python.exe" -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Aliases\py.exe" -Force -ErrorAction SilentlyContinue
            Write-Status "Microsoft Store Alias" "PASS" "Disabled"
        }
        catch {
        }

        # Add to PATH
        $python_dir = Split-Path $python_exe
        $current_path = [Environment]::GetEnvironmentVariable("Path", "Machine")
        if ($current_path -notlike "*$python_dir*") {
            [Environment]::SetEnvironmentVariable("Path", "$current_path;$python_dir", "Machine")
            $env:Path = "$env:Path;$python_dir"
            Write-Status "Python PATH" "PASS" "Added to system PATH"
        }

        Start-Sleep -Seconds 2
        $python_ver = & $python_exe --version 2>&1
        if ($python_ver -like "*3.12*") {
            Write-Status "Python Verification" "PASS" $python_ver
            $python_works = $true
        }
    }
    else {
        Write-Fatal "Python 3.12 not found. Install via: winget install Python.Python.3.12"
    }
}

Write-Host ""

# Step 3: Git Installation
Write-Header "STEP 2: GIT INSTALLATION"

$git_works = $false
try {
    $git_ver = git --version 2>&1
    Write-Status "Git" "PASS" $git_ver
    $git_works = $true
}
catch {
    Write-Status "Git" "INFO" "Installing via winget"
    try {
        winget install --id Git.Git -e --silent --accept-source-agreements 2>&1 | Out-Null
        Start-Sleep -Seconds 3

        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

        $git_ver = git --version 2>&1
        Write-Status "Git" "PASS" $git_ver
        $git_works = $true
    }
    catch {
        Write-Fatal "Git installation failed. Manual install: https://git-scm.com/download/win"
    }
}

Write-Host ""

# Step 4: Directory Structure
Write-Header "STEP 3: DIRECTORY STRUCTURE"

Ensure-Directory $TRADING_ROOT
Write-Status "Root Directory" "PASS" $TRADING_ROOT

Ensure-Directory $LOG_DIR
Write-Status "Logs Directory" "PASS" $LOG_DIR

Ensure-Directory $STATE_DIR
Write-Status "State Directory" "PASS" $STATE_DIR

Write-Status "Queue Path" "PASS" $QUEUE_FILE

Write-Host ""

# Step 5: Repository Clone
Write-Header "STEP 4: REPOSITORY CLONE"

$temp_repo = "$env:TEMP\MediDeals-$(Get-Date -Format 'yyyyMMddHHmmss')"

if (Test-Path "$TRADING_ROOT\$PACKAGE_NAME") {
    Write-Status "Package" "INFO" "Existing deployment will be updated; .env, logs, and state are preserved"
}

Write-Status "Cloning" "INFO" "Repository from GitHub"
try {
        git clone --branch $REPO_BRANCH --depth 1 $REPO_URL $temp_repo 2>&1 | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "Git clone failed"
        }

        Write-Status "Repository" "PASS" "Cloned: $REPO_BRANCH"

        Write-Status "Deploying" "INFO" "Package to $TRADING_ROOT"
        $package_src = "$temp_repo\$PACKAGE_NAME"

        if ((Test-Path $package_src) -eq $false) {
            Write-Fatal "Package directory not found: $package_src"
        }

        # Copy directories
        Get-ChildItem -Path $package_src -Directory | ForEach-Object {
            if ($_.Name -notmatch "logs|state") {
                Copy-Item -Path $_.FullName -Destination $TRADING_ROOT -Recurse -Force
            }
        }

        # Copy files except .env
        Get-ChildItem -Path $package_src -File | Where-Object { $_.Name -ne ".env" } | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $TRADING_ROOT -Force
        }

        Write-Status "Package Deployment" "PASS" "Deployed to $TRADING_ROOT"

        Remove-Item -Path $temp_repo -Recurse -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Fatal "Repository operations failed: $_"
}

Write-Host ""

# Step 6: Python Virtual Environment
Write-Header "STEP 5: PYTHON VIRTUAL ENVIRONMENT"

if (Test-Path $VENV_DIR) {
    Write-Status "Virtual Environment" "PASS" "Already exists"
}
else {
    Write-Status "Creating" "INFO" ".venv"
    try {
        python -m venv $VENV_DIR
        Write-Status "Virtual Environment" "PASS" "Created"
    }
    catch {
        Write-Fatal "Failed to create venv: $_"
    }
}

# Activate venv
$venv_activate = "$VENV_DIR\Scripts\Activate.ps1"
if ((Test-Path $venv_activate) -eq $false) {
    Write-Fatal "Venv activation script not found"
}

& $venv_activate

Write-Status "Virtual Environment" "PASS" "Activated"

# Step 7: Install Dependencies
Write-Header "STEP 6: INSTALL DEPENDENCIES"

$req_file = "$TRADING_ROOT\requirements-windows.txt"

if ((Test-Path $req_file) -eq $false) {
    Write-Fatal "requirements-windows.txt not found: $req_file"
}

Write-Status "Installing" "INFO" "Dependencies"

try {
    python -m pip install --upgrade pip 2>&1 | Out-Null
    Write-Status "PIP" "PASS" "Upgraded"

    python -m pip install -r $req_file 2>&1 | Tee-Object -FilePath "$LOG_DIR\pip-install.log" | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "PIP install failed"
    }

    Write-Status "Dependencies" "PASS" "Installed"
}
catch {
    Write-Fatal "Dependency installation failed: $_"
}

# Verify imports
Write-Status "Verifying" "INFO" "Python imports"

$imports = @("MetaTrader5", "requests", "dotenv", "pandas", "pytz", "yfinance", "numpy")
$all_ok = $true

foreach ($module in $imports) {
    try {
        python -c "import $module" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Status "  Import: $module" "PASS"
        }
        else {
            Write-Status "  Import: $module" "FAIL"
            $all_ok = $false
        }
    }
    catch {
        Write-Status "  Import: $module" "FAIL"
        $all_ok = $false
    }
}

if ($all_ok -eq $false) {
    Write-Fatal "Some imports failed. Check pip log and retry."
}

Write-Host ""

# Step 8: Configuration
Write-Header "STEP 7: CONFIGURATION"

$env_file = "$TRADING_ROOT\.env"
$env_example = "$TRADING_ROOT\.env.example"

if ((Test-Path $env_example) -eq $false) {
    Write-Fatal ".env.example not found: $env_example"
}

if (Test-Path $env_file) {
    Write-Status ".env" "PASS" "Already exists (preserved)"
}
else {
    Copy-Item -Path $env_example -Destination $env_file -Force
    Write-Status ".env" "PASS" "Created from template"
}

# Fail closed on every installation. Connectivity never opts in to execution.
$env_content = Get-Content -Path $env_file -ErrorAction SilentlyContinue
if ($env_content -notmatch '^BOT_EXECUTION_MODE=') {
    Add-Content -Path $env_file -Value "BOT_EXECUTION_MODE=signal_only"
    Write-Status "Execution Mode" "PASS" "Added signal_only default"
}
if ($env_content -notmatch '^LIVE_TRADING_CONFIRMED=') {
    Add-Content -Path $env_file -Value "LIVE_TRADING_CONFIRMED=NO"
    Write-Status "Live Trading Gate" "PASS" "Added NO default"
}

# Check required variables
$required_vars = @(
    "TWELVE_DATA_KEY",
    "TELEGRAM_BOT_TOKEN",
    "TELEGRAM_CHAT_ID",
    "MT5_LOGIN",
    "MT5_PASSWORD",
    "MT5_SERVER"
)

Write-Host "  Configuration Variables:" -ForegroundColor Cyan
$missing = @()
foreach ($var in $required_vars) {
    $value = (Select-String -Path $env_file -Pattern "^$var=" -ErrorAction SilentlyContinue)
    if ($null -ne $value -and $value -notlike "*=$") {
        Write-Status "  OK: $var" "PASS"
    }
    else {
        Write-Status "  OK: $var" "WARN" "Missing value"
        $missing += $var
    }
}

if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "BEFORE PROCEEDING: Edit and fill in missing variables:" -ForegroundColor Yellow
    Write-Host "  notepad $env_file" -ForegroundColor Yellow
    Write-Host ""
    foreach ($var in $missing) {
        Write-Host "  - $var" -ForegroundColor Yellow
    }
    Write-Host ""
}

Write-Host ""

# Step 9: MetaTrader 5 Check
Write-Header "STEP 8: METATRADER 5 CHECK"

$mt5_path = Find-MT5Terminal

if ($mt5_path) {
    Write-Status "MT5 Installation" "PASS" "Found at $mt5_path"

    $mt5_proc = Get-Process terminal64 -ErrorAction SilentlyContinue
    if ($null -ne $mt5_proc) {
        Write-Status "MT5 Terminal" "PASS" "Running"
    }
    else {
        Write-Status "MT5 Terminal" "INFO" "Installed but not running - start MT5 and log in to Vantage DEMO"
    }
}
else {
    Write-Host ""
    Write-Host "MANUAL STEP REQUIRED: MetaTrader 5 is not installed" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. Download from: https://www.metatrader5.com/download" -ForegroundColor Yellow
    Write-Host "2. Run MetaTrader5Setup.exe" -ForegroundColor Yellow
    Write-Host "3. Choose Vantage as your broker" -ForegroundColor Yellow
    Write-Host "4. Log in to Vantage DEMO account" -ForegroundColor Yellow
    Write-Host "5. Verify terminal opens successfully" -ForegroundColor Yellow
    Write-Host "6. Press Enter to continue" -ForegroundColor Yellow
    Write-Host ""
    pause

    $mt5_path = Find-MT5Terminal
    if (-not $mt5_path) {
        Write-Fatal "MT5 still not found. Installation required."
    }

    Write-Status "MT5 Installation" "PASS" "Verified after manual installation"
}

Write-Host ""

# Step 10: MT5 Verification
Write-Header "STEP 9: MT5 VERIFICATION"

$executor_dir = "$TRADING_ROOT\executor"

$verify_scripts = @(
    @{Name = "MT5 Read-Only Connection"; Script = "verify_mt5_connection.py"}
)

foreach ($test in $verify_scripts) {
    $script_path = "$executor_dir\$($test.Script)"

    if ((Test-Path $script_path) -eq $false) {
        Write-Status $test.Name "SKIP" "Not found"
        continue
    }

    Write-Status $test.Name "INFO" "Running"

    try {
        $output = python $script_path 2>&1
        $output | Out-Host
        if ($LASTEXITCODE -eq 0) {
            Write-Status $test.Name "PASS"
        }
        else {
            Write-Status $test.Name "WARN" "Check logs"
        }
    }
    catch {
        Write-Status $test.Name "WARN" "Could not run"
    }
}

Write-Host ""

# Step 11: Start Signal Bots
Write-Header "STEP 10: START SIGNAL BOTS"

$bots_dir = "$TRADING_ROOT\bots"
$bots = @{
    "BTC Bot" = "btc_bot_windows.py";
    "GOLD Bot" = "gold_bot_windows.py";
    "Forex Scalper" = "forex_scalper_windows.py"
}

if (-not $EnableSignalBots) {
    Write-Status "Signal Bots" "SKIP" "Not started (use -EnableSignalBots to opt in)"
    $bots = @{}
}

foreach ($bot_name in $bots.Keys) {
    $bot_script = $bots[$bot_name]
    $bot_path = "$bots_dir\$bot_script"

    if ((Test-Path $bot_path) -eq $false) {
        Write-Status $bot_name "FAIL" "Not found"
        continue
    }

    # Check if already running
    $running = Get-Process python -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -like "*$bot_script*"
    }

    if ($null -ne $running) {
        Write-Status $bot_name "PASS" "Already running"
        continue
    }

    # Start bot
    try {
        $process = Start-Process -FilePath "python.exe" `
            -ArgumentList "-u `"$bot_path`"" `
            -WorkingDirectory $TRADING_ROOT `
            -WindowStyle Hidden `
            -PassThru

        Start-Sleep -Seconds 2

        if ($null -ne $process -and $process.HasExited -eq $false) {
            Write-Status $bot_name "PASS" "Started"
        }
        else {
            Write-Status $bot_name "FAIL" "Process exited"
        }
    }
    catch {
        Write-Status $bot_name "FAIL" $_
    }
}

Write-Host ""

# Step 12: Start Executor
Write-Header "STEP 11: MT5 EXECUTOR"

$executor_script = "$executor_dir\windows_mt5_executor.py"

if (-not $EnableExecutor) {
    Write-Status "Executor" "SKIP" "Not started (use -EnableExecutor to opt in)"
}
elseif ((Test-Path $executor_script) -eq $false) {
    Write-Fatal "Executor not found: $executor_script"
}
else {
    # Check if already running
    $running = Get-Process python -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -like "*windows_mt5_executor.py*"
    }

    if ($null -ne $running) {
        Write-Status "Executor" "PASS" "Already running"
    }
    else {
        Write-Status "Starting" "INFO" "MT5 Executor"

        try {
            $process = Start-Process -FilePath "python.exe" `
                -ArgumentList "-u `"$executor_script`"" `
                -WorkingDirectory $TRADING_ROOT `
                -WindowStyle Hidden `
                -PassThru

            Start-Sleep -Seconds 3

            if ($null -ne $process -and $process.HasExited -eq $false) {
                Write-Status "Executor" "PASS" "Started"
            }
            else {
                Write-Status "Executor" "FAIL" "Process exited"
            }
        }
        catch {
            Write-Status "Executor" "FAIL" $_
        }
    }
}

Write-Host ""

# Step 13: Queue Verification
Write-Header "STEP 12: QUEUE VERIFICATION"

Write-Status "Queue Path" "PASS" $QUEUE_FILE

if (Test-Path $QUEUE_FILE) {
    $lines = @(Get-Content -Path $QUEUE_FILE 2>$null)
    Write-Status "Queue Contents" "PASS" "$($lines.Count) signals"
}
else {
    Write-Status "Queue" "PASS" "Ready"
}

Write-Host ""

# Step 14: Windows Task Scheduler
Write-Header "STEP 13: WINDOWS TASK SCHEDULER"

$scripts_dir = "$TRADING_ROOT\scripts"
$scheduler_script = "$scripts_dir\install_scheduled_tasks.ps1"

if (-not $InstallStartupTask) {
    Write-Status "Task Scheduler Setup" "SKIP" "Not installed (use -InstallStartupTask to opt in)"
}
elseif (Test-Path $scheduler_script) {
    Write-Status "Task Scheduler Setup" "INFO" "Installing auto-recovery task"

    try {
        & $scheduler_script -ErrorAction SilentlyContinue
        Write-Status "Task Scheduler" "PASS" "Task installed"
    }
    catch {
        Write-Status "Task Scheduler" "WARN" "Could not verify"
    }
}
else {
    Write-Status "Task Scheduler Setup" "SKIP" "Script not found"
}

Write-Host ""

# Step 15: Final Health Report
Write-Header "STEP 14: FINAL HEALTH REPORT"

$health_script = "$scripts_dir\health_check.ps1"

if (Test-Path $health_script) {
    Write-Status "Running" "INFO" "Health check"
    Write-Host ""
    & $health_script 2>&1 | Out-Host
    Write-Host ""
}
else {
    Write-Status "Health Check" "SKIP" "Script not found"
}

Write-Host ""

# Summary
Write-Header "DEPLOYMENT COMPLETE"

Write-Host "Windows VM deployment finished" -ForegroundColor Green
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Cyan
Write-Host "  1. Monitor logs: Get-Content $LOG_DIR\*.log -Wait" -ForegroundColor Gray
Write-Host "  2. Health check: $health_script" -ForegroundColor Gray
Write-Host "  3. Test reboot to verify Task Scheduler auto-start" -ForegroundColor Gray
Write-Host ""
Write-Host "Logs: $DEPLOY_LOG" -ForegroundColor Gray
Write-Host ""
Write-Host "DigitalOcean remains untouched and running." -ForegroundColor Cyan
Write-Host ""

pause
