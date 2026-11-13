#requires -Version 5.1
<#[.SYNOPSIS
Restores the original Windows service state after a Veeam guest snapshot.
.DESCRIPTION
Pair with Veeam-PreFreeze.ps1. Does not start a service that was originally stopped.
Preserves state file if restart fails, so recovery can be retried.
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
function Write-AuditLog([string]$Message) {
    $line = '[{0}] [POST] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 -ErrorAction Stop
}
try {
    if (-not [System.Security.Principal.WindowsPrincipal]::new([System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run under an elevated account with service-control rights.'
    }
    if ($ServiceName -eq 'MyCustomAppName') { throw 'Set -ServiceName to the actual Windows service name before use.' }
    if (-not (Test-Path -LiteralPath $statePath)) { throw "Missing pre-freeze state: $statePath. Cannot determine whether service should be started." }
    $state = Import-Clixml -LiteralPath $statePath -ErrorAction Stop
    if ($state.ServiceName -ne $ServiceName -or $state.ComputerName -ne $env:COMPUTERNAME) {
        throw 'State file does not match this computer and service; refusing to change service state.'
    }
    Write-AuditLog "Starting; service=$ServiceName; originallyRunning=$($state.WasRunning)"
    $svc = Get-Service -Name $ServiceName -ErrorAction Stop
    if ($state.WasRunning) {
        if ($svc.Status -ne 'Running') {
            Write-AuditLog "Starting service; currentStatus=$($svc.Status)"
            Start-Service -Name $ServiceName -ErrorAction Stop
            $svc = Get-Service -Name $ServiceName -ErrorAction Stop
            $svc.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds($TimeoutSeconds))
            $svc.Refresh()
        }
        if ($svc.Status -ne 'Running') { throw "Service did not reach Running; status=$($svc.Status)" }
        Write-AuditLog 'Service is running. Perform application-specific health checks separately.'
    } else {
        Write-AuditLog 'Service was not originally running; leaving its current state unchanged.'
    }
    Remove-Item -LiteralPath $statePath -Force -ErrorAction Stop
    Write-AuditLog 'Post-thaw completed successfully.'
    exit 0
}
catch {
    $message = $_.Exception.Message
    try { Write-AuditLog "ERROR: $message; state file retained if present." } catch { Write-Error "Logging failed: $($_.Exception.Message)" }
    Write-Error "Post-thaw failed: $message"
    exit 1
}
