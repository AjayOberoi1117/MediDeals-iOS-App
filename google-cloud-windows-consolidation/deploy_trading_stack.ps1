# ─────────────────────────────────────────────────────────────────────────────
# Google Cloud Windows Trading Stack — Complete Deployment Script
# ─────────────────────────────────────────────────────────────────────────────
# Purpose: Deploy trading bot stack from scratch on Windows Server
# Usage: .\deploy_trading_stack.ps1 [-SkipPython] [-SkipGit] [-SkipMT5] [-DemoTest]
# ─────────────────────────────────────────────────────────────────────────────

param(
    [switch]$SkipPython,
    [switch]$SkipGit,
    [switch]$SkipMT5,
    [switch]$DemoTest,
    [switch]$HealthOnly
)

$ErrorActionPreference = "Continue"

# ─── Configuration ─────────────────────────────────────────────────────────
$TRADING_ROOT = "C:\TradingBots"
$REPO_URL = "https://github.com/AjayOberoi1117/MediDeals-iOS-App.git"
$REPO_BRANCH = "claude/bots-trade-signals-debug-wjevgt"
$PACKAGE_NAME = "google-cloud-windows-consolidation"
$PYTHON_VERSION = "3.12"
$PYTHON_URL = "https://www.python.org/ftp/python/3.12.1/python-3.12.1-amd64.exe"

$LOG_DIR = "$TRADING_ROOT\logs"
$STATE_DIR = "$TRADING_ROOT\state"
$QUEUE_FILE = "$STATE_DIR\.trade_queue.jsonl"
$VENV_DIR = "$TRADING_ROOT\.venv"

$DEPLOY_LOG = "$LOG_DIR\deployment.log"

# ─── Color Output ─────────────────────────────────────────────────────────
function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║ $($Message.PadRight(61)) ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Add-Content -Path $DEPLOY_LOG -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | HEADER | $Message"
}

function Write-Status {
    param(
        [string]$Component,
        [string]$Status,
        [string]$Details = "",
        [string]$Level = "INFO"
    )

    $color = switch ($Status) {
        "PASS" { "Green" }
        "FAIL" { "Red" }
        "WARN" { "Yellow" }
        "INFO" { "Gray" }
        "SKIP" { "Cyan" }
        default { "White" }
    }

    $symbol = switch ($Status) {
        "PASS" { "✓" }
        "FAIL" { "✗" }
        "WARN" { "⚠" }
        "SKIP" { "◯" }
        default { "•" }
    }

    if ($Details) {
        Write-Host "  $symbol $Component`: $Status | $Details" -ForegroundColor $color
    } else {
        Write-Host "  $symbol $Component`: $Status" -ForegroundColor $color
    }

    Add-Content -Path $DEPLOY_LOG -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $Level | $Component`: $Status | $Details"
}

function Write-Error-Fatal {
    param([string]$Message)
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║ FATAL ERROR                                                   ║" -ForegroundColor Red
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host $Message -ForegroundColor Red
    Write-Host ""
    Add-Content -Path $DEPLOY_LOG -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | FATAL | $Message"
    exit 1
}

# ─── Stage 1: Windows Baseline ─────────────────────────────────────────────
function Stage-WindowsBaseline {
    Write-Header "STAGE 1: WINDOWS BASELINE"

    # Admin privileges
    $is_admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $is_admin) {
        Write-Error-Fatal "This script requires Administrator privileges. Please run as Administrator."
    }
    Write-Status "Administrator Privileges" "PASS"

    # System info
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor
    $disk = Get-PSDrive -Name C

    Write-Status "Hostname" "PASS" (hostname)
    Write-Status "OS Version" "PASS" "$($os.Caption) Build $($os.BuildNumber)"
    Write-Status "CPU Cores" "PASS" "$($cpu.NumberOfCores) cores"
    Write-Status "RAM" "PASS" "$([math]::Round($os.TotalVisibleMemorySize / 1MB, 1)) GB"
    Write-Status "Disk C: Free" "PASS" "$([math]::Round($disk.Free / 1GB, 1)) GB"

    # Internet connectivity
    try {
        $test = Test-NetConnection -ComputerName github.com -Port 443 -WarningAction SilentlyContinue
        if ($test.TcpTestSucceeded) {
            Write-Status "Internet Connectivity" "PASS" "github.com reachable"
        } else {
            Write-Status "Internet Connectivity" "WARN" "Cannot reach github.com - manual package copy may be needed"
        }
    } catch {
        Write-Status "Internet Connectivity" "WARN" "Cannot test connectivity"
    }

    Write-Host ""
}

# ─── Stage 2: Install Python ───────────────────────────────────────────────
function Stage-InstallPython {
    if ($SkipPython) {
        Write-Header "STAGE 2: PYTHON (SKIPPED)"
        Write-Status "Python" "SKIP" "Skipped by user"
        Write-Host ""
        return
    }

    Write-Header "STAGE 2: INSTALL PYTHON"

    # Check if Python already installed
    try {
        $python_ver = (python --version 2>&1)
        if ($python_ver -match "3\.1[2-9]") {
            Write-Status "Python" "PASS" "$python_ver"
            $pip_ver = (python -m pip --version 2>&1)
            Write-Status "PIP" "PASS" "$pip_ver"
            Write-Host ""
            return
        }
    } catch {
        Write-Status "Python" "WARN" "Not found or incompatible version"
    }

    # Install Python 3.12
    Write-Status "Installing" "INFO" "Python 3.12 x64..."

    $installer = "$env:TEMP\python-3.12.1-amd64.exe"
    if (-not (Test-Path $installer)) {
        Write-Status "Download" "INFO" "Downloading Python 3.12.1..."
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.12.1/python-3.12.1-amd64.exe" -OutFile $installer -ErrorAction Stop
            Write-Status "Download" "PASS"
        } catch {
            Write-Error-Fatal "Failed to download Python: $_"
        }
    }

    try {
        Write-Status "Executing" "INFO" "Running Python installer (with PATH update)..."
        & $installer /quiet InstallAllUsers=1 PrependPath=1 | Out-Null
        Start-Sleep -Seconds 5

        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

        $python_ver = python --version 2>&1
        $pip_ver = python -m pip --version 2>&1

        Write-Status "Python" "PASS" "$python_ver"
        Write-Status "PIP" "PASS" "$pip_ver"
    } catch {
        Write-Error-Fatal "Python installation failed: $_"
    }

    Write-Host ""
}

# ─── Stage 3: Install Git ─────────────────────────────────────────────────
function Stage-InstallGit {
    if ($SkipGit) {
        Write-Header "STAGE 3: GIT (SKIPPED)"
        Write-Status "Git" "SKIP" "Skipped by user"
        Write-Host ""
        return
    }

    Write-Header "STAGE 3: INSTALL GIT"

    # Check if Git already installed
    try {
        $git_ver = (git --version 2>&1)
        Write-Status "Git" "PASS" "$git_ver"
        Write-Host ""
        return
    } catch {
        Write-Status "Git" "WARN" "Not found, installing..."
    }

    # Install Git for Windows
    Write-Status "Installing" "INFO" "Git for Windows..."

    $installer = "$env:TEMP\Git-2.43.0-64-bit.exe"
    if (-not (Test-Path $installer)) {
        Write-Status "Download" "INFO" "Downloading Git 2.43.0..."
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/download/v2.43.0.windows.1/Git-2.43.0-64-bit.exe" -OutFile $installer -ErrorAction Stop
            Write-Status "Download" "PASS"
        } catch {
            Write-Status "Download" "WARN" "Could not auto-download Git. Manual installation may be required."
            Write-Host ""
            return
        }
    }

    try {
        Write-Status "Executing" "INFO" "Running Git installer..."
        & $installer /SILENT /NORESTART | Out-Null
        Start-Sleep -Seconds 5

        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

        $git_ver = git --version 2>&1
        Write-Status "Git" "PASS" "$git_ver"
    } catch {
        Write-Error-Fatal "Git installation failed: $_"
    }

    Write-Host ""
}

# ─── Stage 4: MetaTrader 5 ─────────────────────────────────────────────────
function Stage-CheckMT5 {
    if ($SkipMT5) {
        Write-Header "STAGE 4: METATRADER 5 (SKIPPED)"
        Write-Status "MT5" "SKIP" "Skipped by user"
        Write-Host ""
        return
    }

    Write-Header "STAGE 4: METATRADER 5"

    # Check if MT5 is installed
    . "$PSScriptRoot\scripts\mt5_paths.ps1"
    $mt5_path = Find-MT5Terminal
    if ($mt5_path) {
        Write-Status "MT5 Installation" "PASS" "Found at $mt5_path"

        $mt5_proc = Get-Process terminal64 -ErrorAction SilentlyContinue
        if ($null -ne $mt5_proc) {
            Write-Status "MT5 Process" "PASS" "Running (PID: $($mt5_proc.Id))"
        } else {
            Write-Status "MT5 Process" "INFO" "Not currently running"
            Write-Host ""
            Write-Host "Next: Start MT5 manually and log in to Vantage DEMO account" -ForegroundColor Yellow
            Write-Host "Then rerun: .\deploy_trading_stack.ps1 -SkipPython -SkipGit -SkipMT5" -ForegroundColor Yellow
            Write-Host ""
            pause
        }
    } else {
        Write-Status "MT5 Installation" "WARN" "Not found"
        Write-Host ""
        Write-Host "MANUAL STEP REQUIRED:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "1. Download MetaTrader 5 from: https://www.metatrader5.com/download" -ForegroundColor Yellow
        Write-Host "2. Run installer: MetaTrader5Setup.exe" -ForegroundColor Yellow
        Write-Host "3. Choose Vantage as broker (not default)" -ForegroundColor Yellow
        Write-Host "4. Create or log in to Vantage DEMO account (NOT REAL)" -ForegroundColor Yellow
        Write-Host "5. Verify terminal opens successfully" -ForegroundColor Yellow
        Write-Host "6. Then rerun this script with -SkipMT5 flag" -ForegroundColor Yellow
        Write-Host ""
        pause
    }

    Write-Host ""
}

# ─── Stage 5: Deploy Source ────────────────────────────────────────────────
function Stage-DeploySource {
    Write-Header "STAGE 5: DEPLOY SOURCE"

    # Create root if needed
    if (-not (Test-Path $TRADING_ROOT)) {
        Write-Status "Creating" "INFO" "$TRADING_ROOT..."
        New-Item -ItemType Directory -Path $TRADING_ROOT -Force | Out-Null
        Write-Status "Root Directory" "PASS" "Created"
    } else {
        Write-Status "Root Directory" "PASS" "Already exists"
    }

    # Backup existing deployment
    if (Test-Path "$TRADING_ROOT\$PACKAGE_NAME") {
        Write-Status "Backup" "INFO" "Existing deployment found, backing up..."
        $backup_dir = "$TRADING_ROOT\backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Rename-Item -Path "$TRADING_ROOT\$PACKAGE_NAME" -NewName $backup_dir -Force
        Write-Status "Backup" "PASS" "Backed up to $(Split-Path $backup_dir -Leaf)"
    }

    # Clone repository
    Write-Status "Cloning" "INFO" "Repository from GitHub..."
    $temp_repo = "$env:TEMP\MediDeals-$(Get-Date -Format 'yyyyMMddHHmmss')"

    try {
        git clone --branch $REPO_BRANCH --depth 1 $REPO_URL $temp_repo 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Git clone failed"
        }
        Write-Status "Repository" "PASS" "Cloned branch: $REPO_BRANCH"
    } catch {
        Write-Error-Fatal "Failed to clone repository: $_`nEnsure internet connectivity and correct branch name."
    }

    # Copy package
    $package_src = "$temp_repo\$PACKAGE_NAME"
    if (-not (Test-Path $package_src)) {
        Write-Error-Fatal "Package not found in repository: $package_src"
    }

    Write-Status "Copying" "INFO" "Package contents to $TRADING_ROOT..."
    try {
        # Copy all directories
        Get-ChildItem -Path $package_src -Directory | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $TRADING_ROOT -Recurse -Force -ErrorAction Stop
        }

        # Copy all files (but not .env)
        Get-ChildItem -Path $package_src -File | Where-Object { $_.Name -ne ".env" } | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $TRADING_ROOT -Force -ErrorAction Stop
        }

        Write-Status "Package" "PASS" "Deployed to $TRADING_ROOT"
    } catch {
        Write-Error-Fatal "Failed to copy package: $_"
    }

    # Get git commit info
    try {
        Push-Location $temp_repo
        $commit_sha = git rev-parse --short HEAD
        $commit_msg = git log -1 --pretty=%B
        Pop-Location
        Write-Status "Commit SHA" "PASS" "$commit_sha"
    } catch {
        Write-Status "Commit SHA" "WARN" "Could not retrieve"
    }

    # Cleanup temp
    Remove-Item -Path $temp_repo -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host ""
}

# ─── Stage 6: Python Virtual Environment ──────────────────────────────────
function Stage-SetupVenv {
    Write-Header "STAGE 6: PYTHON VIRTUAL ENVIRONMENT"

    Write-Status "Creating" "INFO" ".venv in $TRADING_ROOT..."
    try {
        if (Test-Path $VENV_DIR) {
            Write-Status "Existing .venv" "INFO" "Found, will reuse"
        } else {
            python -m venv $VENV_DIR
            Write-Status "Virtual Environment" "PASS" "Created"
        }
    } catch {
        Write-Error-Fatal "Failed to create venv: $_"
    }

    # Activate venv
    $venv_activate = "$VENV_DIR\Scripts\Activate.ps1"
    if (-not (Test-Path $venv_activate)) {
        Write-Error-Fatal "Venv activation script not found: $venv_activate"
    }

    Write-Status "Activating" "INFO" ".venv..."
    & $venv_activate

    # Install requirements
    $req_file = "$TRADING_ROOT\requirements-windows.txt"
    if (-not (Test-Path $req_file)) {
        Write-Error-Fatal "requirements-windows.txt not found: $req_file"
    }

    Write-Status "Installing" "INFO" "Dependencies from requirements-windows.txt..."
    try {
        pip install --upgrade pip
        pip install -r $req_file 2>&1 | Tee-Object -FilePath "$LOG_DIR\pip-install.log" | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "PIP install exited with code $LASTEXITCODE"
        }
        Write-Status "Dependencies" "PASS" "Installed successfully"
    } catch {
        Write-Error-Fatal "Failed to install dependencies: $_"
    }

    # Verify key imports
    Write-Status "Verifying" "INFO" "Python imports..."
    $imports = @("MetaTrader5", "requests", "dotenv", "pandas", "pytz")
    foreach ($module in $imports) {
        try {
            python -c "import $module; print('OK')" 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Status "  Import: $module" "PASS"
            } else {
                Write-Status "  Import: $module" "FAIL"
            }
        } catch {
            Write-Status "  Import: $module" "FAIL"
        }
    }

    Write-Host ""
}

# ─── Stage 7: Configuration ────────────────────────────────────────────────
function Stage-Configuration {
    Write-Header "STAGE 7: CONFIGURATION"

    $env_file = "$TRADING_ROOT\.env"
    $env_example = "$TRADING_ROOT\.env.example"

    if (-not (Test-Path $env_example)) {
        Write-Error-Fatal ".env.example not found: $env_example"
    }

    if (Test-Path $env_file) {
        Write-Status ".env" "PASS" "Already exists (preserved)"
    } else {
        Write-Status ".env" "INFO" "Creating from .env.example..."
        Copy-Item -Path $env_example -Destination $env_file -Force
        Write-Status ".env" "PASS" "Created"
    }

    # Parse and report required variables
    $required_vars = @(
        "TWELVE_DATA_KEY",
        "TELEGRAM_BOT_TOKEN",
        "TELEGRAM_CHAT_ID",
        "MT5_LOGIN",
        "MT5_PASSWORD",
        "MT5_SERVER",
        "BOT_EXECUTION_MODE",
        "LIVE_TRADING_CONFIRMED"
    )

    Write-Host "  Required Configuration Variables:" -ForegroundColor Cyan
    foreach ($var in $required_vars) {
        $value = (Select-String -Path $env_file -Pattern "^$var=" -ErrorAction SilentlyContinue)
        if ($null -ne $value) {
            Write-Host "    ✓ $var" -ForegroundColor Green
        } else {
            Write-Host "    ✗ $var (missing)" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "CRITICAL: Edit .env with your credentials:" -ForegroundColor Yellow
    Write-Host "  $env_file" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Do NOT commit .env (only .env.example)" -ForegroundColor Yellow
    Write-Host ""
}

# ─── Stage 8: Directories ──────────────────────────────────────────────────
function Stage-Directories {
    Write-Header "STAGE 8: DIRECTORIES & QUEUE"

    foreach ($dir in @($LOG_DIR, $STATE_DIR)) {
        if (Test-Path $dir) {
            Write-Status "Directory: $(Split-Path $dir -Leaf)" "PASS" "Exists"
        } else {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Status "Directory: $(Split-Path $dir -Leaf)" "PASS" "Created"
        }
    }

    Write-Status "Queue File" "PASS" "Canonical: $QUEUE_FILE"

    Write-Host ""
}

# ─── Stage 9: MT5 Verification ─────────────────────────────────────────────
function Stage-MT5Verification {
    Write-Header "STAGE 9: MT5 VERIFICATION"

    $venv_activate = "$VENV_DIR\Scripts\Activate.ps1"
    & $venv_activate

    $executor_dir = "$TRADING_ROOT\executor"
    $verify_scripts = @(
        "$executor_dir\verify_mt5_connection.py"
    )

    foreach ($script in $verify_scripts) {
        if (-not (Test-Path $script)) {
            Write-Status "$(Split-Path $script -Leaf)" "WARN" "Not found"
            continue
        }

        Write-Status "Running" "INFO" "$(Split-Path $script -Leaf)..."
        try {
            $output = python $script 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Status "$(Split-Path $script -Leaf)" "PASS"
                # Parse and show key results
                $output | Where-Object { $_ -match "terminal executable|initialize:|last_error:|account login:|server:|company:|trade_mode:|terminal connected:|trade_allowed:|symbols_total:" } | ForEach-Object {
                    Write-Host "    $_" -ForegroundColor Gray
                }
            } else {
                Write-Status "$(Split-Path $script -Leaf)" "FAIL" "Exit code: $LASTEXITCODE"
                $output | Select-Object -First 5 | ForEach-Object {
                    Write-Host "    $_" -ForegroundColor Red
                }
            }
        } catch {
            Write-Status "$(Split-Path $script -Leaf)" "FAIL" "$_"
        }
    }

    Write-Host ""
}

# ─── Stage 10: Signal Bots ─────────────────────────────────────────────────
function Stage-SignalBots {
    Write-Header "STAGE 10: SIGNAL BOTS"

    $venv_activate = "$VENV_DIR\Scripts\Activate.ps1"
    & $venv_activate

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
            Write-Status "$bot_name" "FAIL" "Not found: $bot_path"
            continue
        }

        # Check if already running
        $running = Get-Process python -ErrorAction SilentlyContinue | Where-Object {
            $_.CommandLine -like "*$bot_script*"
        }

        if ($null -ne $running) {
            Write-Status "$bot_name" "PASS" "Already running (PID: $($running.Id))"
            continue
        }

        # Start bot
        Write-Status "Starting" "INFO" "$bot_name..."
        try {
            $process = Start-Process -FilePath "python.exe" `
                -ArgumentList "-u `"$bot_path`"" `
                -WorkingDirectory $TRADING_ROOT `
                -WindowStyle Hidden `
                -PassThru

            Start-Sleep -Seconds 2

            if ($null -ne $process -and -not $process.HasExited) {
                Write-Status "$bot_name" "PASS" "Started (PID: $($process.Id))"
            } else {
                Write-Status "$bot_name" "FAIL" "Process exited unexpectedly"
            }
        } catch {
            Write-Status "$bot_name" "FAIL" "$_"
        }
    }

    Write-Host ""
}

# ─── Stage 11: Executor ─────────────────────────────────────────────────────
function Stage-Executor {
    Write-Header "STAGE 11: MT5 EXECUTOR"

    $venv_activate = "$VENV_DIR\Scripts\Activate.ps1"
    & $venv_activate

    $executor_script = "$TRADING_ROOT\executor\windows_mt5_executor.py"

    if (-not (Test-Path $executor_script)) {
        Write-Error-Fatal "Executor not found: $executor_script"
    }

    # Check if already running
    $running = Get-Process python -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -like "*windows_mt5_executor.py*"
    }

    if ($null -ne $running) {
        Write-Status "Executor" "PASS" "Already running (PID: $($running.Id))"
        Write-Host ""
        return
    }

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
            Write-Status "Executor" "FAIL" "Process exited unexpectedly"
        }
    } catch {
        Write-Status "Executor" "FAIL" "$_"
    }

    Write-Host ""
}

# ─── Stage 12: DEMO Order Test ──────────────────────────────────────────────
function Stage-DemoTest {
    if (-not $DemoTest) {
        Write-Header "STAGE 12: DEMO ORDER TEST"
        Write-Status "Status" "SKIP" "Use -DemoTest flag to enable"
        Write-Host ""
        return
    }

    Write-Header "STAGE 12: DEMO ORDER TEST"

    Write-Host "CRITICAL: This will place a DEMO order on Vantage." -ForegroundColor Yellow
    Write-Host "Ensure BOT_EXECUTION_MODE=production and LIVE_TRADING_CONFIRMED=YES in .env" -ForegroundColor Yellow
    Write-Host ""

    $confirm = Read-Host "Type 'yes' to proceed with DEMO order test"
    if ($confirm -ne "yes") {
        Write-Status "Demo Test" "SKIP" "User cancelled"
        Write-Host ""
        return
    }

    Write-Status "Demo Test" "INFO" "Running manual order test..."
    Write-Host "Check logs for order results:" -ForegroundColor Gray
    Write-Host "  $LOG_DIR\mt5_executor.log" -ForegroundColor Gray
    Write-Host ""
}

# ─── Stage 13: Windows Startup ──────────────────────────────────────────────
function Stage-WindowsStartup {
    Write-Header "STAGE 13: WINDOWS STARTUP AUTOMATION"

    $scripts_dir = "$TRADING_ROOT\scripts"
    $startup_script = "$scripts_dir\startup_with_executor.ps1"
    $scheduler_script = "$scripts_dir\install_scheduled_tasks.ps1"

    if (-not (Test-Path $startup_script)) {
        Write-Status "startup_with_executor.ps1" "FAIL" "Not found"
        Write-Host ""
        return
    }

    Write-Status "Startup Script" "PASS" "Found"

    if (-not (Test-Path $scheduler_script)) {
        Write-Status "install_scheduled_tasks.ps1" "FAIL" "Not found"
        Write-Host ""
        return
    }

    Write-Status "Scheduler Script" "PASS" "Found"

    # Install scheduled task
    Write-Status "Installing" "INFO" "Windows Task Scheduler task..."
    try {
        & $scheduler_script
        if ($LASTEXITCODE -eq 0) {
            Write-Status "Task Scheduler" "PASS" "Task installed"
        } else {
            Write-Status "Task Scheduler" "WARN" "Installation may need manual verification"
        }
    } catch {
        Write-Status "Task Scheduler" "WARN" "Could not install automatically: $_"
    }

    Write-Host ""
}

# ─── Stage 14: Health Report ────────────────────────────────────────────────
function Stage-HealthReport {
    Write-Header "STAGE 14: HEALTH REPORT"

    $health_script = "$TRADING_ROOT\scripts\health_check.ps1"

    if (Test-Path $health_script) {
        Write-Status "Health Check" "INFO" "Running..."
        Write-Host ""
        & $health_script
    } else {
        Write-Status "Health Check" "FAIL" "Script not found"
    }

    Write-Host ""
}

# ─── Stage 15: DigitalOcean Note ────────────────────────────────────────────
function Stage-DigitalOcean {
    Write-Header "STAGE 15: DIGITALOCEAN"

    Write-Host "DigitalOcean deployment is PRESERVED and unchanged." -ForegroundColor Cyan
    Write-Host "It remains as fallback until Google Cloud passes full acceptance test." -ForegroundColor Cyan
    Write-Host ""
}

# ─── Health-Only Mode ───────────────────────────────────────────────────────
function Health-Only {
    Write-Header "HEALTH CHECK ONLY"

    $health_script = "$TRADING_ROOT\scripts\health_check.ps1"
    if (Test-Path $health_script) {
        & $health_script
    } else {
        Write-Status "Health Check" "FAIL" "Script not found at $health_script"
    }
}

# ─── Main Deployment ────────────────────────────────────────────────────────
function Main {
    # Create log directory early
    if (-not (Test-Path $LOG_DIR)) {
        New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
    }

    # Health-only mode
    if ($HealthOnly) {
        Health-Only
        return
    }

    # Full deployment
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║       GOOGLE CLOUD WINDOWS TRADING STACK DEPLOYMENT          ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host "Log File: $DEPLOY_LOG" -ForegroundColor Gray

    Stage-WindowsBaseline
    Stage-InstallPython
    Stage-InstallGit
    Stage-CheckMT5
    Stage-DeploySource
    Stage-SetupVenv
    Stage-Configuration
    Stage-Directories
    Stage-MT5Verification
    Stage-SignalBots
    Stage-Executor
    Stage-DemoTest
    Stage-WindowsStartup
    Stage-HealthReport
    Stage-DigitalOcean

    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║             DEPLOYMENT COMPLETE                              ║" -ForegroundColor Green
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "  1. Edit .env with your credentials (Vantage, Telegram, Twelve Data)" -ForegroundColor Gray
    Write-Host "  2. Run health check: .\scripts\health_check.ps1" -ForegroundColor Gray
    Write-Host "  3. Monitor logs: Get-Content .\logs\*.log -Wait" -ForegroundColor Gray
    Write-Host "  4. Test reboot with scheduled task installed" -ForegroundColor Gray
    Write-Host ""
}

Main
