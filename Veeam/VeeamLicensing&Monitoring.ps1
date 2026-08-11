# --- CONFIGURATION ---
$ExpirationWarningDays = 30
$UsageThresholdPercent = 90
# ---------------------

# Load Veeam Module
Import-Module Veeam.Backup.PowerShell -ErrorAction SilentlyContinue

Write-Host "Gathering Veeam License Inventory and Metrics...`n" -ForegroundColor Cyan

# Fetch top-level license data
$LicenseInfo = Get-VBRInstalledLicense

if (-not $LicenseInfo) {
    Write-Error "No active Veeam license found or module failed to load."
    exit 1
}

# 1. Base License Profile
$ExpiryDate   = $LicenseInfo.ExpirationDate
$DaysToExpiry = (New-TimeSpan -Start (Get-Date) -End $ExpiryDate).Days
$SupportExpiry= $LicenseInfo.SupportExpirationDate
$DaysToSupport= (New-TimeSpan -Start (Get-Date) -End $SupportExpiry).Days

# Determine Status State
$LicStatus = "Healthy"
if ($DaysToExpiry -le $ExpirationWarningDays) { $LicStatus = "CRITICAL: Expiring Soon" }
elseif ($DaysToSupport -le $ExpirationWarningDays) { $LicStatus = "WARNING: Support Expiring" }

Write-Host "=== LICENSE PROFILE ===" -ForegroundColor Yellow
[PSCustomObject]@{
    "Product Edition"    = $LicenseInfo.Edition
    "Licensed To"        = $LicenseInfo.LicenseTo
    "License Type"       = $LicenseInfo.Type
    "Status"             = $LicStatus
    "Expiration Date"    = "$ExpiryDate ($DaysToExpiry Days Left)"
    "Support End Date"   = "$SupportExpiry ($DaysToSupport Days Left)"
    "Auto-Update"        = $LicenseInfo.AutoUpdateEnabled
} | Format-List

# 2. VUL / Instance Consumption Profile
$InstanceSummary = $LicenseInfo.InstanceLicenseSummary
Write-Host "=== INSTANCE USAGE (VUL) ===" -ForegroundColor Yellow
if ($InstanceSummary -and $InstanceSummary.Capacity -gt 0) {
    $UsedInstances = $InstanceSummary.Used
    $TotalInstances = $InstanceSummary.Capacity
    $RemainingInstances = $TotalInstances - $UsedInstances
    $PercentUsed = [Math]::Round(($UsedInstances / $TotalInstances) * 100, 1)

    if ($PercentUsed -ge $UsageThresholdPercent) {
        Write-Host "⚠️ WARNING: High VUL utilization detected ($PercentUsed%)!" -ForegroundColor Orange
    }

    [PSCustomObject]@{
        "Total VUL Capacity"  = $TotalInstances
        "Instances Used"      = $UsedInstances
        "Instances Remaining" = $RemainingInstances
        "Utilization %"       = "$PercentUsed %"
        "New Workloads Allowed" = [Math]::Max(0, $RemainingInstances)
    } | Format-Table -AutoSize
} else {
    Write-Host "No instance/VUL license consumption data detected.`n" -ForegroundColor Gray
}

# 3. Legacy Socket Consumption Profile
$SocketSummary = $LicenseInfo.SocketLicenseSummary
Write-Host "=== SOCKET USAGE ===" -ForegroundColor Yellow
if ($SocketSummary -and $SocketSummary.Capacity -gt 0) {
    [PSCustomObject]@{
        "Total CPU Sockets Licensed" = $SocketSummary.Capacity
        "Sockets In Use"             = $SocketSummary.Used
        "Remaining Sockets"          = ($SocketSummary.Capacity - $SocketSummary.Used)
    } | Format-Table -AutoSize
} else {
    Write-Host "No Socket-based licensing active on this platform.`n" -ForegroundColor Gray
}

# 4. Generate native HTML report to disk
$ReportPath = "C:\Reports\Veeam_License_Report.html"
Write-Host "Exporting comprehensive built-in HTML license usage summary..." -ForegroundColor Green
Generate-VBRLicenseUsageReport -Path $ReportPath -ErrorAction SilentlyContinue
Write-Host "Report saved successfully to: $ReportPath" -ForegroundColor Gray
