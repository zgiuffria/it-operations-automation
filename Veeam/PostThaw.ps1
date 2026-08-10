$ServiceName  = "MyCustomAppName"
$LogFile      = "C:\Windows\Temp\Veeam_PreFreeze.log" # Use same log file

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
