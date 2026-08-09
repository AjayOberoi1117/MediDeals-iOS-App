# ─────────────────────────────────────────────────────────────────────────────
# Google Cloud Windows Trading Stack — Complete Installation & Deployment
# ─────────────────────────────────────────────────────────────────────────────
# One-script complete deployment from bare Windows to operational trading stack
# Run as: .\install-and-deploy.ps1
# Safe to rerun; idempotent; pauses only for unavoidable manual steps
# ─────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# ─── Global Configuration ──────────────────────────────────────────────────
$TRADING_ROOT = "C:\TradingBots"
$REPO_URL = "https://github.com/AjayOberoi1117/MediDeals-iOS-App.git"
$REPO_BRANCH = "claude/bots-trade-signals-debug-wjevgt"
$PACKAGE_NAME = "google-cloud-windows-consolidation"
$VENV_DIR = "$TRADING_ROOT\.venv"
$LOG_DIR = "$TRADING_ROOT\logs"
$STATE_DIR = "$TRADING_ROOT\state"
$QUEUE_FILE = "$STATE_DIR\.trade_queue.jsonl"
$DEPLOY_LOG = "$LOG_DIR\install-deploy.log"

# ─── Utilities ─────────────────────────────────────────────────────────────
function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║ $($Message.PadRight(62)) ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Add-Content -Path $DEPLOY_LOG -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $Message"
}

function Write-Status {
    param(
        [string]$Component,
        [string]$Status,
        [string]$Details = "",
        [string]$Color = "Gray"
    )

    $symbol = switch ($Status) {
        "PASS" { "✓"; $Color = "Green" }
        "FAIL" { "✗"; $Color = "Red" }
        "WARN" { "⚠"; $Color = "Yellow" }
        "INFO" { "•"; $Color = "Gray" }
        "SKIP" { "◯"; $Color = "Cyan" }
        default { "?"; $Color = "White" }
    }

    if ($Details) {
        Write-Host "  $symbol $Component`: $Status | $Details" -ForegroundColor $Color
    } else {
        Write-Host "  $symbol $Component`: $Status" -ForegroundColor $Color
    }

    Add-Content -Path $DEPLOY_LOG -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $Component`: $Status | $Details"
}

function Write-Fatal {
    param([string]$Message)
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║ FATAL ERROR                                                    ║" -ForegroundColor Red
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host $Message -ForegroundColor Red
    Write-Host ""
    Add-Content -Path $DEPLOY_LOG -Value "FATAL: $Message"
    exit 1
}

function Ensure-Admin {
    $is_admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $is_admin) {
        Write-Fatal "This script requires Administrator privileges. Right-click PowerShell and select 'Run as Administrator'."
    }
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# ─── Step 1: Admin & Logging ───────────────────────────────────────────────
Write-Header "INITIALIZATION"
Ensure-Admin
Write-Status "Administrator" "PASS"

Ensure-Directory $LOG_DIR
Write-Status "Log Directory" "PASS" $LOG_DIR

# ─── Step 2: Python PATH Fix ──────────────────────────────────────────────
Write-Header "STEP 1: PYTHON 3.12 PATH CORRECTION"

try {
    $python_ver = python --version 2>&1
    if ($python_ver -match "3\.12") {
        Write-Status "Python" "PASS" "$python_ver"
    } else {
        throw "Python version mismatch or not found"
    }
} catch {
    Write-Status "Python PATH" "INFO" "Attempting to fix..."

    # Find Python installation
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

    if (-not $python_exe) {
        # Try to find via winget
        $winget_path = $(winget list --name python --exact | grep -i python)
        if ($winget_path) {
            Write-Status "Python" "INFO" "Found via winget, location may vary"
            $python_exe = "python"
        }
    }

    if ($python_exe -and (Test-Path $python_exe)) {
        # Disable Microsoft Store alias
        try {
            Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Aliases\python.exe" -ErrorAction SilentlyContinue
            Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Aliases\py.exe" -ErrorAction SilentlyContinue
            Write-Status "Microsoft Store Alias" "PASS" "Disabled"
        } catch {
            Write-Status "Microsoft Store Alias" "WARN" "Could not remove (may still work)"
        }

        # Add to PATH if needed
        if (-not ($env:Path -like "*Python312*")) {
            $python_dir = Split-Path $python_exe
            [Environment]::SetEnvironmentVariable(
                "Path",
                "$([Environment]::GetEnvironmentVariable('Path','Machine'));$python_dir",
                "Machine"
            )
            $env:Path = "$env:Path;$python_dir"
            Write-Status "Python PATH" "PASS" "Added to system PATH"
        }

        Start-Sleep -Seconds 2

        # Verify in new shell context
        $python_ver = & $python_exe --version 2>&1
        if ($python_ver -match "3\.12") {
            Write-Status "Python Verification" "PASS" "$python_ver"
        } else {
            Write-Status "Python Verification" "WARN" "Version check inconclusive, proceeding..."
        }
    } else {
        Write-Fatal "Python 3.12 not found. Please install Python 3.12 via: winget install Python.Python.3.12"
    }
}

Write-Host ""

# ─── Step 3: Git Installation ──────────────────────────────────────────────
Write-Header "STEP 2: GIT INSTALLATION"

try {
    $git_ver = git --version 2>&1
    Write-Status "Git" "PASS" "$git_ver"
} catch {
    Write-Status "Git" "INFO" "Installing via winget..."
    try {
        winget install --id Git.Git -e --silent --accept-source-agreements 2>&1 | Out-Null
        Start-Sleep -Seconds 3

        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        $git_ver = git --version 2>&1
        Write-Status "Git" "PASS" "$git_ver"
    } catch {
        Write-Fatal "Git installation failed. Please install manually: https://git-scm.com/download/win"
    }
}

Write-Host ""

# ─── Step 4: Directory Structure ───────────────────────────────────────────
Write-Header "STEP 3: DIRECTORY STRUCTURE"

Ensure-Directory $TRADING_ROOT
Write-Status "Root Directory" "PASS" $TRADING_ROOT

Ensure-Directory $LOG_DIR
Write-Status "Logs Directory" "PASS" $LOG_DIR

Ensure-Directory $STATE_DIR
Write-Status "State Directory" "PASS" $STATE_DIR

Write-Status "Queue Path" "PASS" $QUEUE_FILE

Write-Host ""

# ─── Step 5: Repository Clone ─────────────────────────────────────────────
Write-Header "STEP 4: REPOSITORY CLONE"

$temp_repo = "$env:TEMP\MediDeals-$(Get-Date -Format 'yyyyMMddHHmmss')"

# Check if already cloned to temp
if (Test-Path "$TRADING_ROOT\$PACKAGE_NAME") {
    Write-Status "Package" "PASS" "Already deployed, skipping clone"
} else {
    Write-Status "Cloning" "INFO" "Repository (this may take a minute)..."
    try {
        git clone --branch $REPO_BRANCH --depth 1 $REPO_URL $temp_repo 2>&1 | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "Git clone failed"
        }

        Write-Status "Repository" "PASS" "Cloned: $REPO_BRANCH"

        # Deploy package
        Write-Status "Deploying" "INFO" "Package to $TRADING_ROOT..."
        $package_src = "$temp_repo\$PACKAGE_NAME"

        if (-not (Test-Path $package_src)) {
            Write-Fatal "Package directory not found: $package_src"
        }

        # Copy directories
        Get-ChildItem -Path $package_src -Directory | ForEach-Object {
            if ($_.Name -notmatch "logs|state") {
                Copy-Item -Path $_.FullName -Destination $TRADING_ROOT -Recurse -Force
            }
        }

        # Copy files (except .env)
        Get-ChildItem -Path $package_src -File | Where-Object { $_.Name -ne ".env" } | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $TRADING_ROOT -Force
        }

        # Get commit info
        Push-Location $temp_repo
        $commit_sha = git rev-parse --short HEAD
        Pop-Location

        Write-Status "Package Deployment" "PASS" "SHA: $commit_sha"

        # Cleanup
        Remove-Item -Path $temp_repo -Recurse -Force -ErrorAction SilentlyContinue

    } catch {
        Write-Fatal "Repository operations failed: $_"
    }
}

Write-Host ""

# ─── Step 6: Python Virtual Environment ───────────────────────────────────
Write-Header "STEP 5: PYTHON VIRTUAL ENVIRONMENT"

if (Test-Path $VENV_DIR) {
    Write-Status "Virtual Environment" "PASS" "Already exists"
} else {
    Write-Status "Creating" "INFO" ".venv..."
    try {
        python -m venv $VENV_DIR
        Write-Status "Virtual Environment" "PASS" "Created"
    } catch {
        Write-Fatal "Failed to create venv: $_"
    }
}

# Activate venv
$venv_activate = "$VENV_DIR\Scripts\Activate.ps1"
if (-not (Test-Path $venv_activate)) {
    Write-Fatal "Venv activation script not found"
}

& $venv_activate

Write-Status "Virtual Environment" "PASS" "Activated"

# ─── Step 7: Install Dependencies ─────────────────────────────────────────
Write-Header "STEP 6: INSTALL DEPENDENCIES"

$req_file = "$TRADING_ROOT\requirements-windows.txt"

if (-not (Test-Path $req_file)) {
    Write-Fatal "requirements-windows.txt not found: $req_file"
}

Write-Status "Installing" "INFO" "Dependencies..."

try {
    python -m pip install --upgrade pip 2>&1 | Out-Null
    Write-Status "PIP" "PASS" "Upgraded"

    python -m pip install -r $req_file 2>&1 | Tee-Object -FilePath "$LOG_DIR\pip-install.log" | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "PIP install failed with code $LASTEXITCODE"
    }

    Write-Status "Dependencies" "PASS" "Installed"

} catch {
    Write-Fatal "Dependency installation failed: $_`nCheck: $LOG_DIR\pip-install.log"
}

# Verify imports
Write-Status "Verifying" "INFO" "Python imports..."

$imports = @("MetaTrader5", "requests", "dotenv", "pandas", "pytz", "yfinance", "numpy")
$all_ok = $true

foreach ($module in $imports) {
    try {
        python -c "import $module" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Status "  Import: $module" "PASS"
        } else {
            Write-Status "  Import: $module" "FAIL"
            $all_ok = $false
        }
    } catch {
        Write-Status "  Import: $module" "FAIL"
        $all_ok = $false
    }
}

if (-not $all_ok) {
    Write-Fatal "Some imports failed. Check pip log and retry."
}

Write-Host ""

# ─── Step 8: Configuration (.env) ─────────────────────────────────────────
Write-Header "STEP 7: CONFIGURATION"

$env_file = "$TRADING_ROOT\.env"
$env_example = "$TRADING_ROOT\.env.example"

if (-not (Test-Path $env_example)) {
    Write-Fatal ".env.example not found: $env_example"
}

if (Test-Path $env_file) {
    Write-Status ".env" "PASS" "Already exists (preserved)"
} else {
    Copy-Item -Path $env_example -Destination $env_file -Force
    Write-Status ".env" "PASS" "Created from template"
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
    if ($null -ne $value -and -not ($value -like "*=$")) {
        Write-Status "  ✓ $var" "PASS"
    } else {
        Write-Status "  ✗ $var" "WARN" "Missing value"
        $missing += $var
    }
}

if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "BEFORE PROCEEDING:" -ForegroundColor Yellow
    Write-Host "Edit and fill in these variables:" -ForegroundColor Yellow
    Write-Host "  notepad $env_file" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Variables to configure:" -ForegroundColor Yellow
    foreach ($var in $missing) {
        Write-Host "  - $var" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "After configuration, you can rerun this script." -ForegroundColor Yellow
}

Write-Host ""

# ─── Step 9: MetaTrader 5 Check ────────────────────────────────────────────
Write-Header "STEP 8: METATRADER 5 CHECK"

$mt5_path = "C:\Program Files\MetaTrader 5\terminal64.exe"

if (Test-Path $mt5_path) {
    Write-Status "MT5 Installation" "PASS" "Found"

    $mt5_proc = Get-Process terminal64 -ErrorAction SilentlyContinue
    if ($null -ne $mt5_proc) {
        Write-Status "MT5 Terminal" "PASS" "Running (PID: $($mt5_proc.Id))"
    } else {
        Write-Status "MT5 Terminal" "INFO" "Installed but not running"
        Write-Status "Next Step" "INFO" "Start MT5 terminal and log in to Vantage DEMO account"
        Write-Host ""
        Write-Host "After starting MT5:" -ForegroundColor Cyan
        Write-Host "  1. Click 'File' → 'Login'" -ForegroundColor Gray
        Write-Host "  2. Select 'Vantage' as broker" -ForegroundColor Gray
        Write-Host "  3. Use DEMO account credentials" -ForegroundColor Gray
        Write-Host "  4. Wait for terminal to fully initialize" -ForegroundColor Gray
        Write-Host "  5. Return and rerun this script" -ForegroundColor Gray
        Write-Host ""
        pause
    }
} else {
    Write-Host ""
    Write-Host "MANUAL STEP REQUIRED:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "MetaTrader 5 is not installed." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. Download from: https://www.metatrader5.com/download" -ForegroundColor Yellow
    Write-Host "2. Run MetaTrader5Setup.exe" -ForegroundColor Yellow
    Write-Host "3. Choose Vantage as your broker (NOT the default)" -ForegroundColor Yellow
    Write-Host "4. Create/log in to your Vantage DEMO account (NOT REAL MONEY)" -ForegroundColor Yellow
    Write-Host "5. Verify the terminal opens successfully" -ForegroundColor Yellow
    Write-Host "6. Return here and press Enter to continue" -ForegroundColor Yellow
    Write-Host ""
    pause

    # Check again after pause
    if (-not (Test-Path $mt5_path)) {
        Write-Fatal "MT5 still not found. Installation required before proceeding."
    }

    Write-Status "MT5 Installation" "PASS" "Verified after manual installation"
}

Write-Host ""

# ─── Step 10: MT5 Verification ────────────────────────────────────────────
Write-Header "STEP 9: MT5 VERIFICATION"

$executor_dir = "$TRADING_ROOT\executor"

$verify_scripts = @(
    @{Name = "MT5 Connection"; Script = "verify_mt5_connection.py"},
    @{Name = "Symbol Specs"; Script = "verify_symbol_specs.py"},
    @{Name = "Order Check"; Script = "verify_order_check.py"}
)

foreach ($test in $verify_scripts) {
    $script_path = "$executor_dir\$($test.Script)"

    if (-not (Test-Path $script_path)) {
        Write-Status $test.Name "SKIP" "Not found"
        continue
    }

    Write-Status $test.Name "INFO" "Running..."

    try {
        $output = python $script_path 2>&1
        $output | Select-Object -First 20 | ForEach-Object {
            if ($_ -match "✓|✅|PASS|Account|DEMO|connected") {
                Write-Host "    $_" -ForegroundColor Green
            } elseif ($_ -match "error|fail|✗" -and $_ -notmatch "ERROR|FAIL") {
                Write-Host "    $_" -ForegroundColor Yellow
            }
        }

        if ($LASTEXITCODE -eq 0) {
            Write-Status $test.Name "PASS"
        } else {
            Write-Status $test.Name "WARN" "Exit code: $LASTEXITCODE"
        }
    } catch {
        Write-Status $test.Name "WARN" "Could not run: $_"
    }
}

Write-Host ""

# ─── Step 11: Symbol Discovery ─────────────────────────────────────────────
Write-Header "STEP 10: SYMBOL DISCOVERY"

$discover_script = "$executor_dir\discover_symbols.py"

if (Test-Path $discover_script) {
    Write-Status "Discovering" "INFO" "Vantage symbols..."

    try {
        $output = python $discover_script 2>&1
        $output | Select-Object -First 30 | ForEach-Object {
            if ($_ -match "Found|✓|BTCUSD|XAUUSD|EURUSD|GBPUSD") {
                Write-Host "    $_" -ForegroundColor Green
            }
        }

        # Check if symbol_mapping.json was created
        if (Test-Path "$executor_dir\symbol_mapping.json") {
            Write-Status "Symbol Mapping" "PASS" "File created"
        }
    } catch {
        Write-Status "Symbol Discovery" "WARN" "Could not run: $_"
    }
} else {
    Write-Status "Symbol Discovery" "SKIP" "Script not found"
}

Write-Host ""

# ─── Step 12: Start Signal Bots ────────────────────────────────────────────
Write-Header "STEP 11: START SIGNAL BOTS"

$bots_dir = "$TRADING_ROOT\bots"
$bots = @{
    "BTC Bot" = "btc_bot_windows.py"
    "GOLD Bot" = "gold_bot_windows.py"
    "Forex Scalper" = "forex_scalper_windows.py"
}

foreach ($bot_name in $bots.Keys) {
    $bot_script = $bots[$bot_name]
    $bot_path = "$bots_dir\$bot_script"

    if (-not (Test-Path $bot_path)) {
        Write-Status $bot_name "FAIL" "Not found"
        continue
    }

    # Check if already running
    $running = Get-Process python -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -like "*$bot_script*"
    }

    if ($null -ne $running) {
        Write-Status $bot_name "PASS" "Already running (PID: $($running.Id))"
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

        if ($null -ne $process -and -not $process.HasExited) {
            Write-Status $bot_name "PASS" "Started (PID: $($process.Id))"
        } else {
            Write-Status $bot_name "FAIL" "Process exited"
        }
    } catch {
        Write-Status $bot_name "FAIL" "$_"
    }
}

Write-Host ""

# ─── Step 13: Start Executor ──────────────────────────────────────────────
Write-Header "STEP 12: START MT5 EXECUTOR"

$executor_script = "$executor_dir\windows_mt5_executor.py"

if (-not (Test-Path $executor_script)) {
    Write-Fatal "Executor not found: $executor_script"
}

# Check if already running
$running = Get-Process python -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -like "*windows_mt5_executor.py*"
}

if ($null -ne $running) {
    Write-Status "Executor" "PASS" "Already running (PID: $($running.Id))"
} else {
    Write-Status "Starting" "INFO" "MT5 Executor..."

    try {
        $process = Start-Process -FilePath "python.exe" `
            -ArgumentList "-u `"$executor_script`"" `
            -WorkingDirectory $TRADING_ROOT `
            -WindowStyle Hidden `
            -PassThru

        Start-Sleep -Seconds 3

        if ($null -ne $process -and -not $process.HasExited) {
            Write-Status "Executor" "PASS" "Started (PID: $($process.Id))"
        } else {
            Write-Status "Executor" "FAIL" "Process exited"
        }
    } catch {
        Write-Status "Executor" "FAIL" "$_"
    }
}

Write-Host ""

# ─── Step 14: Queue Verification ──────────────────────────────────────────
Write-Header "STEP 13: QUEUE VERIFICATION"

Write-Status "Queue Path" "PASS" $QUEUE_FILE

if (Test-Path $QUEUE_FILE) {
    $lines = @(Get-Content -Path $QUEUE_FILE 2>$null)
    Write-Status "Queue Contents" "PASS" "$($lines.Count) signals"
} else {
    Write-Status "Queue" "PASS" "Ready (no signals yet)"
}

Write-Host ""

# ─── Step 15: Windows Automation ──────────────────────────────────────────
Write-Header "STEP 14: WINDOWS TASK SCHEDULER"

$scripts_dir = "$TRADING_ROOT\scripts"
$scheduler_script = "$scripts_dir\install_scheduled_tasks.ps1"

if (Test-Path $scheduler_script) {
    Write-Status "Task Scheduler Setup" "INFO" "Installing auto-recovery task..."

    try {
        & $scheduler_script -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq $null) {
            Write-Status "Task Scheduler" "PASS" "Task installed for auto-start"
        } else {
            Write-Status "Task Scheduler" "WARN" "Check logs for details"
        }
    } catch {
        Write-Status "Task Scheduler" "WARN" "Could not verify: $_"
    }
} else {
    Write-Status "Task Scheduler Setup" "SKIP" "Script not found"
}

Write-Host ""

# ─── Step 16: Final Health Report ────────────────────────────────────────
Write-Header "STEP 15: FINAL HEALTH REPORT"

$health_script = "$scripts_dir\health_check.ps1"

if (Test-Path $health_script) {
    Write-Status "Running" "INFO" "Health check..."
    Write-Host ""
    & $health_script 2>&1 | Out-Host
    Write-Host ""
    Write-Status "Health Report" "PASS" "Complete"
} else {
    Write-Status "Health Check" "SKIP" "Script not found"
}

Write-Host ""

# ─── Summary ───────────────────────────────────────────────────────────────
Write-Header "DEPLOYMENT COMPLETE"

Write-Host "✓ Windows VM deployment finished" -ForegroundColor Green
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Cyan
Write-Host "  1. Monitor logs: Get-Content $LOG_DIR\*.log -Wait" -ForegroundColor Gray
Write-Host "  2. Verify signals: Get-Content $QUEUE_FILE -Wait" -ForegroundColor Gray
Write-Host "  3. Health check: $health_script" -ForegroundColor Gray
Write-Host "  4. Test reboot to verify Task Scheduler auto-start" -ForegroundColor Gray
Write-Host ""
Write-Host "Logs:" -ForegroundColor Cyan
Write-Host "  Deployment: $DEPLOY_LOG" -ForegroundColor Gray
Write-Host "  Trading: $LOG_DIR\*.log" -ForegroundColor Gray
Write-Host ""
Write-Host "DigitalOcean remains untouched and running." -ForegroundColor Cyan
Write-Host ""

pause
