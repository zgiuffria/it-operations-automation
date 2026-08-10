# --- CONFIGURATION ---
$ServiceName  = "MyCustomAppName"
$LogFile      = "C:\Windows\Temp\Veeam_PreFreeze.log"
# ---------------------

# Setup clean logging
Function Write-Log ($Message) {
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$TimeStamp] $Message" | Out-File -FilePath $LogFile -Append
}

Write-Log "Pre-freeze script started."

try {
    # Check if service is running
    $Service = Get-Service -Name $ServiceName -ErrorAction Stop
    
    if ($Service.Status -eq 'Running') {
        Write-Log "Stopping service: $ServiceName"
        
        # Stop service and wait up to 60 seconds
        Stop-Service -Name $ServiceName -Force -ErrorAction Stop
        $Service.WaitForStatus('Stopped', '00:00:60')
        
        Write-Log "Service successfully stopped. System is now consistent."
    } else {
        Write-Log "Service was already stopped."
    }
    
    # Optional: Flush database buffers/caches if your app requires a command line utility
    # & "C:\Program Files\MyApp\bin\appadmin.exe" --flush-buffers
    
    Write-Log "Pre-freeze complete. Exiting with success code 0."
    exit 0
}
catch {
    Write-Log "ERROR occurred during pre-freeze: $_"
    # Exit with a non-zero code so Veeam knows the freeze failed
    exit 1
}
