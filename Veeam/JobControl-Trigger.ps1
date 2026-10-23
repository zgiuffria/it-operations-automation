# --- CONFIGURATION ---
$TargetJobName = "Daily VM Backup"
$Action        = "START" # Options: START, STOP, FORCE-FULL, RETRY
# ---------------------

<#
.SYNOPSIS
    Veeam Job Control and Trigger Management Engine.
.DESCRIPTION
    Interfaces with the Veeam PowerShell Snap-in to control specific backup or replication jobs, allowing administrators to programmatically trigger, stop, retry, or force an active full run.
.NOTES
    - How to use: Define your target job name and specific execution action profile in the configuration block.
    - Requirements: Run from an elevated PowerShell terminal directly on your target Veeam Backup & Replication server.
    - Automation: Can be embedded inside other scripts or triggered externally via Windows Task Scheduler.
#>

# In the post-job settings of Job 1, trigger Job 2
# Start-VBRJob -Job (Get-VBRJob -Name "Your-Second-Job-Name")

# Load Veeam Module
Import-Module Veeam.Backup.PowerShell -ErrorAction SilentlyContinue

# Fetch the specific job object
$Job = Get-VBRJob | Where-Object { $_.Name -eq $TargetJobName }

if (-not $Job) {
    Write-Error "Could not find a Veeam job named '$TargetJobName'."
    exit 1
}

# Check Current Execution Status
$LastSession = $Job.FindLastSession()
$IsRunning = $LastSession -and (-not $LastSession.IsCompleted)

switch ($Action.ToUpper()) {
    "START" {
        if ($IsRunning) {
            Write-Host "Job '$TargetJobName' is already running. Skipping trigger." -ForegroundColor Yellow
        } else {
            Write-Host "Triggering normal incremental run for '$TargetJobName'..." -ForegroundColor Green
            Start-VBRJob -Job $Job
        }
    }
    
    "FORCE-FULL" {
        if ($IsRunning) {
            Write-Host "Cannot force full backup: Job is currently running." -ForegroundColor Red
        } else {
            Write-Host "Triggering Active Full backup for '$TargetJobName'..." -ForegroundColor Cyan
            Start-VBRJob -Job $Job -FullBackup
        }
    }

    "RETRY" {
        if ($IsRunning) {
            Write-Host "Cannot retry: Job is currently running." -ForegroundColor Red
        } else {
            Write-Host "Retrying failed objects in '$TargetJobName'..." -ForegroundColor Yellow
            Start-VBRJob -Job $Job -RetryBackup
        }
    }

    "STOP" {
        if ($IsRunning) {
            Write-Host "Gracefully stopping running job '$TargetJobName'..." -ForegroundColor DarkYellow
            Stop-VBRJob -Job $Job
        } else {
            Write-Host "Job '$TargetJobName' is not running." -ForegroundColor Gray
        }
    }

    Default {
        Write-Error "Invalid action profile. Use START, STOP, FORCE-FULL, or RETRY."
    }
}
