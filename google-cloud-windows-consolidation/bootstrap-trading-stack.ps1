# ─────────────────────────────────────────────────────────────────────────────
# Trading Stack Bootstrap — Windows VM Initialization
# ─────────────────────────────────────────────────────────────────────────────
# Purpose: Prepare Windows VM for full trading stack deployment
# Requirements: Only Administrator PowerShell + winget (no Git/Python needed yet)
# Usage: .\bootstrap-trading-stack.ps1 OR paste as inline PowerShell
# ─────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ─── Configuration ─────────────────────────────────────────────────────────
$REPO_URL = "https://github.com/AjayOberoi1117/MediDeals-iOS-App.git"
$REPO_BRANCH = "claude/bots-trade-signals-debug-wjevgt"
$EXPECTED_SHA = "25aabd2a40bd03af75f7cae2101c9fb577a34143"
$REPO_DIR = "C:\MediDeals-iOS-App"
$TRADING_ROOT = "C:\TradingBots"
$DEPLOY_SCRIPT = "$REPO_DIR\google-cloud-windows-consolidation\install-and-deploy.ps1"

# ─── Utilities ─────────────────────────────────────────────────────────────
function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║ $($Message.PadRight(62)) ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
}

function Write-Status {
    param(
        [string]$Component,
        [string]$Status,
        [string]$Details = ""
    )

    $color = switch ($Status) {
        "PASS" { "Green" }
        "FAIL" { "Red" }
        "WARN" { "Yellow" }
        default { "Gray" }
    }

    $symbol = if ($Status -eq "PASS") { "✓" } elseif ($Status -eq "FAIL") { "✗" } else { "•" }

    if ($Details) {
        Write-Host "  $symbol $Component`: $Status | $Details" -ForegroundColor $color
    } else {
        Write-Host "  $symbol $Component`: $Status" -ForegroundColor $color
    }
}

function Write-Fatal {
    param([string]$Message)
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║ FATAL ERROR                                                    ║" -ForegroundColor Red
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host $Message -ForegroundColor Red
    Write-Host ""
    exit 1
}

function Ensure-Admin {
    $is_admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $is_admin) {
        Write-Fatal "Administrator privileges required. Right-click PowerShell → 'Run as Administrator'"
    }
}

# ─── Step 1: Admin Check ───────────────────────────────────────────────────
Write-Header "BOOTSTRAP: TRADING STACK INITIALIZATION"

Ensure-Admin
Write-Status "Administrator" "PASS"

# ─── Step 2: Fix Python 3.12 PATH ─────────────────────────────────────────
Write-Header "STEP 1: PYTHON 3.12 PATH FIX"

try {
    $python_test = python --version 2>&1
    if ($python_test -match "3\.12") {
        Write-Status "Python 3.12" "PASS" "$python_test"
    } else {
        throw "Version mismatch"
    }
} catch {
    Write-Status "Python" "WARN" "Fixing PATH..."

    # Disable Microsoft Store alias
    try {
        Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Aliases\python.exe" -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Aliases\py.exe" -Force -ErrorAction SilentlyContinue
        Write-Status "Microsoft Store Alias" "PASS" "Disabled"
    } catch {}

    # Find Python installation
    $python_paths = @(
        "C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python312",
        "C:\Program Files\Python312",
        "C:\Program Files (x86)\Python312"
    )

    $python_exe = $null
    foreach ($path in $python_paths) {
        if (Test-Path "$path\python.exe") {
            $python_exe = "$path\python.exe"
            $python_dir = $path
            break
        }
    }

    if ($python_exe) {
        # Add to PATH if not already
        $current_path = [Environment]::GetEnvironmentVariable("Path", "Machine")
        if ($current_path -notlike "*$python_dir*") {
            [Environment]::SetEnvironmentVariable(
                "Path",
                "$current_path;$python_dir",
                "Machine"
            )
            Write-Status "Python PATH" "PASS" "Added $python_dir"
        }

        # Refresh current process PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

        # Verify
        Start-Sleep -Seconds 1
        $python_ver = & $python_exe --version 2>&1
        if ($python_ver -match "3\.12") {
            Write-Status "Python Verification" "PASS" "$python_ver"
        } else {
            Write-Status "Python Verification" "WARN" "Version uncertain, proceeding..."
        }
    } else {
        Write-Fatal "Python 3.12 installation not found. Install via: winget install Python.Python.3.12"
    }
}

Write-Host ""

# ─── Step 3: Install Git via winget ────────────────────────────────────────
Write-Header "STEP 2: GIT INSTALLATION"

try {
    $git_ver = git --version 2>&1
    Write-Status "Git" "PASS" "$git_ver"
} catch {
    Write-Status "Git" "WARN" "Installing via winget (this may take 1-2 minutes)..."

    try {
        winget install --id Git.Git -e --silent --accept-source-agreements 2>&1 | Out-Null

        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

        Start-Sleep -Seconds 3

        $git_ver = git --version 2>&1
        if ($git_ver -match "git") {
            Write-Status "Git" "PASS" "$git_ver"
        } else {
            throw "Git not in PATH after install"
        }
    } catch {
        Write-Fatal "Git installation failed. Manual install required: https://git-scm.com/download/win"
    }
}

Write-Host ""

# ─── Step 4: Clone Repository ──────────────────────────────────────────────
Write-Header "STEP 3: REPOSITORY CLONE"

if (Test-Path $REPO_DIR) {
    Write-Status "Repository" "PASS" "Already cloned, updating..."
    try {
        Push-Location $REPO_DIR
        git fetch origin $REPO_BRANCH 2>&1 | Out-Null
        git checkout $REPO_BRANCH 2>&1 | Out-Null
        Pop-Location
    } catch {
        Write-Fatal "Failed to update existing repository: $_"
    }
} else {
    Write-Status "Cloning" "INFO" "Repository (this may take a moment)..."

    try {
        git clone --branch $REPO_BRANCH --depth 1 $REPO_URL $REPO_DIR 2>&1 | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "Git clone failed"
        }

        Write-Status "Repository" "PASS" "Cloned successfully"
    } catch {
        Write-Fatal "Repository clone failed: $_"
    }
}

Write-Host ""

# ─── Step 5: Verify SHA ────────────────────────────────────────────────────
Write-Header "STEP 4: COMMIT VERIFICATION"

try {
    Push-Location $REPO_DIR

    # Get current HEAD SHA
    $current_sha = git rev-parse --short HEAD 2>&1

    if ($current_sha -match $EXPECTED_SHA.Substring(0, 7)) {
        Write-Status "Commit SHA" "PASS" "$current_sha (expected)"
    } else {
        Write-Status "Commit SHA" "WARN" "Current: $current_sha | Expected: $($EXPECTED_SHA.Substring(0, 7))"
        Write-Host ""
        Write-Host "Branch head may have moved. Current commit is still valid." -ForegroundColor Yellow
    }

    Pop-Location
} catch {
    Write-Status "SHA Verification" "FAIL" "Could not verify: $_"
}

Write-Host ""

# ─── Step 6: Verify Deployment Script ──────────────────────────────────────
Write-Header "STEP 5: DEPLOYMENT SCRIPT VERIFICATION"

if (-not (Test-Path $DEPLOY_SCRIPT)) {
    Write-Fatal "Deployment script not found: $DEPLOY_SCRIPT"
}

Write-Status "Deployment Script" "PASS" "Found"
Write-Status "Location" "PASS" $DEPLOY_SCRIPT

Write-Host ""

# ─── Step 7: Launch Deployment ────────────────────────────────────────────
Write-Header "BOOTSTRAP COMPLETE - LAUNCHING DEPLOYMENT"

Write-Host ""
Write-Host "Repository cloned to: $REPO_DIR" -ForegroundColor Green
Write-Host "Deployment script: $DEPLOY_SCRIPT" -ForegroundColor Green
Write-Host ""
Write-Host "Starting full deployment automation..." -ForegroundColor Cyan
Write-Host ""

# Change to deployment directory and run
try {
    Push-Location (Split-Path $DEPLOY_SCRIPT)

    # Verify execution policy allows running scripts
    $exec_policy = Get-ExecutionPolicy -Scope CurrentUser
    if ($exec_policy -eq "Restricted") {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Write-Status "Execution Policy" "PASS" "Updated to RemoteSigned"
    }

    # Run deployment
    & $DEPLOY_SCRIPT

    Pop-Location

} catch {
    Write-Fatal "Deployment script execution failed: $_"
}

Write-Host ""
Write-Host "Bootstrap and deployment complete!" -ForegroundColor Green
