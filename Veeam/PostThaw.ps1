# --- CONFIGURATION ---
$ServiceName  = "MyCustomAppName"
$LogFile      = "C:\Windows\Temp\Veeam_PreFreeze.log"
# ---------------------

<#
.SYNOPSIS
    Veeam Post-Thaw Application Processing Script.
.DESCRIPTION
    Restarts the non-VSS-aware service inside a Windows guest VM immediately after the backup snapshot is created, bringing the application back online.
.NOTES
    - How to use: Match the service name and log destination with your corresponding Pre-Freeze script.
    - Requirements: Configure inside Veeam Backup Job properties under Guest Processing -> Applications -> Scripts.
    - Execution: Returns code 0 on success, or code 1 on failure to log critical startup errors.
#>

# Setup clean logging
Function Write-Log ($Message) {
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$TimeStamp] $Message" | Out-File -FilePath $LogFile -Append
}

Write-Log "Post-thaw script started. Restarting application services..."

try {
    Start-Service -Name $ServiceName -ErrorAction Stop
    Write-Log "Service $ServiceName successfully restarted. Exiting with 0."
    exit 0
}
catch {
    Write-Log "CRITICAL ERROR: Failed to restart service: $_"
    exit 1
}
