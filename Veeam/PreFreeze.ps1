#requires -Version 5.1
<#[.SYNOPSIS
Quiesces a designated Windows service before a Veeam guest snapshot.
.DESCRIPTION
Read this before use: stopping a service does NOT prove application-consistent backup.
Use only with an application vendor-approved stop/start procedure. Pair with
Veeam-PostThaw.ps1. Both scripts must use the same ServiceName and StateDirectory.
Exit 0 = pre-freeze succeeded; nonzero = failed.
#>
[CmdletBinding()]
param(
    [string]$ServiceName = 'MyCustomAppName',
    [string]$StateDirectory = 'C:\ProgramData\VeeamGuestScripts',
    [ValidateRange(5,300)][int]$TimeoutSeconds = 60
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$statePath = Join-Path $StateDirectory 'PreFreezeState.clixml'
$logPath = Join-Path $StateDirectory 'Veeam-GuestProcessing.log'
$stoppedByUs = $false
$originallyRunning = $false
$stateWritten = $false
function Write-AuditLog([string]$Message) {
    $line = '[{0}] [PRE] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 -ErrorAction Stop
}
try {
    if (-not [System.Security.Principal.WindowsPrincipal]::new([System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run under an elevated account with service-control rights.'
    }
    if ($ServiceName -eq 'MyCustomAppName') { throw 'Set -ServiceName to the actual Windows service name before use.' }
    New-Item -ItemType Directory -Path $StateDirectory -Force | Out-Null
    # A state file left behind means the previous cycle may not have thawed.
    if (Test-Path -LiteralPath $statePath) { throw "Existing state file: $statePath. Investigate/recover the previous backup cycle before proceeding." }
    $svc = Get-Service -Name $ServiceName -ErrorAction Stop
    Write-AuditLog "Starting; service=$ServiceName; initialStatus=$($svc.Status)"
    if ($svc.Status -eq 'StopPending' -or $svc.Status -eq 'StartPending') { throw "Service is in transitional state: $($svc.Status)" }
    $originallyRunning = ($svc.Status -eq 'Running')
    # Persist intent BEFORE stopping, so post-thaw can recover if pre-freeze is interrupted.
    $state = [pscustomobject]@{
        ServiceName = $ServiceName
        WasRunning = $originallyRunning
        CreatedUtc = (Get-Date).ToUniversalTime()
        ComputerName = $env:COMPUTERNAME
    }
    $state | Export-Clixml -LiteralPath $statePath -ErrorAction Stop
    $stateWritten = $true
    if ($originallyRunning) {
        Write-AuditLog 'Stopping service (without -Force).'
        Stop-Service -Name $ServiceName -ErrorAction Stop
        $svc = Get-Service -Name $ServiceName -ErrorAction Stop
        $svc.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds($TimeoutSeconds))
        $svc.Refresh()
        if ($svc.Status -ne 'Stopped') { throw "Service did not stop; status=$($svc.Status)" }
        $stoppedByUs = $true
        Write-AuditLog 'Service stopped; application consistency must be independently validated.'
    } else {
        Write-AuditLog "Service was $($svc.Status); no stop requested."
    }
    Write-AuditLog 'Pre-freeze completed successfully.'
    exit 0
}
catch {
    $message = $_.Exception.Message
    try { Write-AuditLog "ERROR: $message" } catch { Write-Error "Logging failed: $($_.Exception.Message)" }
    # Attempt recovery on failure, even if Stop-Service partially succeeded.
    if ($originallyRunning) {
        try {
            $current = Get-Service -Name $ServiceName -ErrorAction Stop
            if ($current.Status -ne 'Running') {
                Start-Service -Name $ServiceName -ErrorAction Stop
                $current = Get-Service -Name $ServiceName -ErrorAction Stop
                $current.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds($TimeoutSeconds))
            }
            Write-AuditLog 'Service recovered after pre-freeze failure.'
            if ($stateWritten) { Remove-Item -LiteralPath $statePath -Force -ErrorAction Stop }
        } catch {
            try { Write-AuditLog "RECOVERY FAILED: $($_.Exception.Message). Preserve state file for post-thaw/manual recovery." } catch {}
        }
    } elseif ($stateWritten) {
        try { Remove-Item -LiteralPath $statePath -Force -ErrorAction Stop } catch {}
    }
    Write-Error "Pre-freeze failed: $message"
    exit 1
}
