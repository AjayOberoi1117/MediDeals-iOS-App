# ─────────────────────────────────────────────────────────────────────────────
# Windows Task Scheduler Setup for Trading Stack
# ─────────────────────────────────────────────────────────────────────────────
# Purpose: Create automatic startup task for trading stack after VM reboot
# Runs: At system boot, no interactive login required
# Privileges: Highest available
# Restart: On failure, every 5 minutes, max 10 retries
#
# Usage:
#   Install:   .\install_scheduled_tasks.ps1
#   Uninstall: .\install_scheduled_tasks.ps1 -Uninstall
#   List:      .\install_scheduled_tasks.ps1 -List
# ─────────────────────────────────────────────────────────────────────────────

param(
    [switch]$Uninstall,
    [switch]$List
)

$ErrorActionPreference = "Stop"

$TRADING_BOTS_ROOT = "C:\TradingBots"
$SCRIPTS_DIR = Join-Path $TRADING_BOTS_ROOT "scripts"
$STARTUP_SCRIPT = Join-Path $SCRIPTS_DIR "startup_with_executor.ps1"
$TASK_NAME = "TradingStack-AutoStart"
$TASK_PATH = "\TradingBots\"

# ─── Helper Functions ──────────────────────────────────────────────────────
function Test-AdminPrivileges {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════"
    Write-Host $Message
    Write-Host "═══════════════════════════════════════════════════════════════"
}

# ─── Uninstall Task ────────────────────────────────────────────────────────
function Uninstall-Task {
    Write-Header "UNINSTALLING SCHEDULED TASK"

    $task = Get-ScheduledTask -TaskName $TASK_NAME -TaskPath $TASK_PATH -ErrorAction SilentlyContinue

    if ($null -eq $task) {
        Write-Host "Task '$TASK_NAME' not found - nothing to uninstall" "Yellow"
        return $true
    }

    try {
        Unregister-ScheduledTask -TaskName $TASK_NAME -TaskPath $TASK_PATH -Confirm:$false
        Write-Host "✓ Task uninstalled: $TASK_NAME" "Green"
        return $true
    } catch {
        Write-Host "✗ Failed to uninstall task: $_" "Red"
        return $false
    }
}

# ─── List Task ─────────────────────────────────────────────────────────────
function List-Task {
    Write-Header "INSTALLED SCHEDULED TASK"

    $task = Get-ScheduledTask -TaskName $TASK_NAME -TaskPath $TASK_PATH -ErrorAction SilentlyContinue

    if ($null -eq $task) {
        Write-Host "No scheduled task found for '$TASK_NAME'" "Yellow"
        return $true
    }

    Write-Host "Task Name: $($task.TaskName)" "Cyan"
    Write-Host "Path: $($task.TaskPath)" "Cyan"
    Write-Host "Status: $($task.State)" "Cyan"
    Write-Host ""

    $trigger = $task.Triggers[0]
    if ($null -ne $trigger) {
        Write-Host "Trigger Type: $($trigger.GetType().Name)" "Cyan"
        if ($trigger.GetType().Name -eq "BootTrigger") {
            Write-Host "Trigger: System boot" "Cyan"
            Write-Host "Delay: $($trigger.Delay)" "Cyan"
        }
    }

    $action = $task.Actions[0]
    if ($null -ne $action) {
        Write-Host "Action: $($action.Execute)" "Cyan"
        Write-Host "Arguments: $($action.Arguments)" "Cyan"
        Write-Host "Working Directory: $($action.WorkingDirectory)" "Cyan"
    }

    Write-Host ""
    Write-Host "To uninstall this task:" "Yellow"
    Write-Host "  .\install_scheduled_tasks.ps1 -Uninstall" "Yellow"
    Write-Host ""

    return $true
}

# ─── Install Task ──────────────────────────────────────────────────────────
function Install-Task {
    Write-Header "INSTALLING SCHEDULED TASK"

    # Validate prerequisites
    if (-not (Test-Path $STARTUP_SCRIPT)) {
        Write-Host "✗ Startup script not found: $STARTUP_SCRIPT" "Red"
        return $false
    }

    Write-Host "Validating prerequisites..." "Cyan"
    Write-Host "  Root: $TRADING_BOTS_ROOT" "Gray"
    Write-Host "  Startup script: $STARTUP_SCRIPT" "Gray"

    # Remove existing task if it exists (idempotent)
    $existing = Get-ScheduledTask -TaskName $TASK_NAME -TaskPath $TASK_PATH -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        Write-Host "Existing task found - removing..." "Yellow"
        try {
            Unregister-ScheduledTask -TaskName $TASK_NAME -TaskPath $TASK_PATH -Confirm:$false
            Start-Sleep -Seconds 1
        } catch {
            Write-Host "✗ Failed to remove existing task: $_" "Red"
            return $false
        }
    }

    # Create trigger: At system boot with 1-minute delay
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $trigger.Delay = "PT1M"  # 1 minute delay to allow system stabilization

    # Create action: Run PowerShell script
    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$STARTUP_SCRIPT`"" `
        -WorkingDirectory $TRADING_BOTS_ROOT

    # Create settings: Restart on failure
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable `
        -RestartCount 10 `
        -RestartInterval (New-TimeSpan -Minutes 5) `
        -MultipleInstances IgnoreNew

    # Get principal for SYSTEM account with highest privileges
    $principal = New-ScheduledTaskPrincipal `
        -UserId "SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest

    # Register the task
    try {
        Write-Host "Creating scheduled task..." "Cyan"
        $task = Register-ScheduledTask `
            -TaskName $TASK_NAME `
            -TaskPath $TASK_PATH `
            -Trigger $trigger `
            -Action $action `
            -Settings $settings `
            -Principal $principal `
            -Force

        Write-Host ""
        Write-Host "✓ Task created successfully" "Green"
        Write-Host ""
        Write-Host "Task Details:" "Cyan"
        Write-Host "  Name: $($task.TaskName)" "Gray"
        Write-Host "  Path: $($task.TaskPath)" "Gray"
        Write-Host "  Trigger: At system boot (1 min delay)" "Gray"
        Write-Host "  Action: PowerShell -File $STARTUP_SCRIPT" "Gray"
        Write-Host "  Restart: 10 retries, 5-minute interval" "Gray"
        Write-Host "  Privileges: SYSTEM, Highest" "Gray"
        Write-Host ""
        Write-Host "To uninstall:" "Yellow"
        Write-Host "  .\install_scheduled_tasks.ps1 -Uninstall" "Yellow"
        Write-Host ""

        return $true
    } catch {
        Write-Host "✗ Failed to create scheduled task: $_" "Red"
        return $false
    }
}

# ─── Main ──────────────────────────────────────────────────────────────────
function Main {
    # Check admin privileges
    if (-not (Test-AdminPrivileges)) {
        Write-Host "✗ This script requires administrator privileges" "Red"
        Write-Host "Please run as Administrator" "Red"
        exit 1
    }

    # Route to appropriate function
    if ($Uninstall) {
        $success = Uninstall-Task
    } elseif ($List) {
        $success = List-Task
    } else {
        $success = Install-Task
    }

    exit $(if ($success) { 0 } else { 1 })
}

Main
