# --- CONFIGURATION ---
$ReportPath = "C:\Reports\Veeam_Health_Report.html"
$DaysToCheck = 1
$SMTP_Server = "://yourdomain.com"
$Email_To = "admin@yourdomain.com"
$Email_From = "veeam-alerts@yourdomain.com"
# ---------------------

# Load Veeam Module
Import-Module Veeam.Backup.PowerShell -ErrorAction SilentlyContinue

# Fetch Data
$TargetDate = (Get-Date).AddDays(-$DaysToCheck)
$Jobs = Get-VBRJob | Where-Object { $_.GetLatestResult() -ne "None" }
$Repositories = Get-VBRBackupRepository

# Build HTML Report
$HTML = @"
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; background-color: #f4f4f4; margin: 20px; }
        h2 { color: #333; border-bottom: 2px solid #4CAF50; padding-bottom: 10px; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 30px; background: white; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #4CAF50; color: white; }
        .Success { color: green; font-weight: bold; }
        .Warning { color: orange; font-weight: bold; }
        .Failed { color: red; font-weight: bold; }
    </style>
</head>
<body>
    <h2>Veeam Job Status (Last $DaysToCheck Days)</h2>
    <table>
        <tr><th>Job Name</th><th>Job Type</th><th>Last Run Time</th><th>Status</th></tr>
"@

foreach ($Job in $Jobs) {
    $Session = $Job.FindLastSession()
    if ($Session.CreationTime -ge $TargetDate) {
        $Status = $Session.Result
        $HTML += "<tr><td>$($Job.Name)</td><td>$($Job.JobType)</td><td>$($Session.CreationTime)</td><td class='$Status'>$Status</td></tr>"
    }
}

$HTML += @"
    </table>
    <h2>Repository Storage Status</h2>
    <table>
        <tr><th>Repository Name</th><th>Path</th><th>Total (GB)</th><th>Free (GB)</th><th>Free %</th></tr>
"@

foreach ($Repo in $Repositories) {
    $Info = $Repo.Info
    if ($Info.Capacity -gt 0) {
        $TotalGB = [Math]::Round($Info.Capacity / 1GB, 2)
        $FreeGB = [Math]::Round($Info.FreeSpace / 1GB, 2)
        $PercentFree = [Math]::Round(($FreeGB / $TotalGB) * 100, 1)
        
        $HTML += "<tr><td>$($Repo.Name)</td><td>$($Info.Path)</td><td>$TotalGB</td><td>$FreeGB</td><td>$PercentFree %</td></tr>"
    }
}

$HTML += "</body></html>"
$HTML | Out-File $ReportPath -Force

# Optional: Email the report
# Send-MailMessage -To $Email_To -From $Email_From -Subject "Veeam Health Report" -BodyAsHtml $HTML -SmtpServer $SMTP_Server
