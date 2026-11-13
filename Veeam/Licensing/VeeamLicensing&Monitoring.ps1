#requires -Version 5.1
<#
.SYNOPSIS
    Read-only Veeam Backup & Replication v13 license audit and HTML dashboard.
.DESCRIPTION
    Reports license expiration, support expiration, VUL and socket usage.
    Exports CSV, HTML, and an optional native Veeam license usage report.
    Maintains a local historical CSV of utilization snapshots for trend review.
.PARAMETER ReportDirectory
    Destination directory for reports and local history.
.PARAMETER ExpirationWarningDays
    Days remaining before warning; <=7 days is critical.
.PARAMETER UsageThresholdPercent
    Utilization percentage at which to warn.
.PARAMETER SkipNativeReport
    Do not request the Veeam-generated license usage HTML report.
.EXAMPLE
    .\Get-VeeamLicenseDashboard.ps1 -ReportDirectory C:\Reports -UsageThresholdPercent 90
.NOTES
    Run on a Windows VBR server with Veeam.Backup.PowerShell available.
    This script does not modify Veeam licensing or configuration.
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()][string]$ReportDirectory = 'C:\Reports',
    [ValidateRange(1,365)][int]$ExpirationWarningDays = 30,
    [ValidateRange(1,100)][int]$UsageThresholdPercent = 90,
    [switch]$SkipNativeReport
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SafeProperty {
    param([AllowNull()][object]$InputObject, [string[]]$Names)
    if ($null -eq $InputObject) { return $null }
    foreach ($name in $Names) {
        $prop = $InputObject.PSObject.Properties[$name]
        if ($null -ne $prop -and $null -ne $prop.Value) { return $prop.Value }
    }
    return $null
}
function Convert-ToNumber {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    $parsed = 0.0
    if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Any,
        [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) { return $parsed }
    return $null
}
function Get-DateStatus {
    param([AllowNull()][object]$Value, [int]$WarningDays)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return [pscustomobject]@{ Date = 'Unavailable'; DaysLeft = $null; Status = 'Unknown' }
    }
    try { $date = [datetime]$Value } catch {
        return [pscustomobject]@{ Date = 'Unavailable'; DaysLeft = $null; Status = 'Unknown' }
    }
    # Some perpetual licenses expose a default/sentinel date rather than an expiration.
    if ($date.Year -le 1901 -or $date.Year -ge 9990) {
        return [pscustomobject]@{ Date = 'Not applicable'; DaysLeft = $null; Status = 'N/A' }
    }
    $days = [int][math]::Ceiling(($date - (Get-Date)).TotalDays)
    $status = if ($days -lt 0) { 'Expired' } elseif ($days -le 7) { 'Critical' } elseif ($days -le $WarningDays) { 'Warning' } else { 'Healthy' }
    return [pscustomobject]@{ Date = $date.ToString('yyyy-MM-dd'); DaysLeft = $days; Status = $status }
}
function Html {
    param([AllowNull()][object]$Value)
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}
function Get-UsageRecord {
    param([string]$Category, [string]$Workload, [AllowNull()][object]$Total, [AllowNull()][object]$Used, [int]$Threshold)
    $capacity = Convert-ToNumber $Total
    $consumed = Convert-ToNumber $Used
    $remaining = $null; $percent = $null; $status = 'Unknown'
    if ($null -ne $capacity -and $capacity -gt 0 -and $null -ne $consumed) {
        $remaining = $capacity - $consumed
        $percent = [math]::Round(($consumed / $capacity) * 100, 1)
        $status = if ($percent -ge 100) { 'Critical' } elseif ($percent -ge $Threshold) { 'Warning' } else { 'Healthy' }
    }
    return [pscustomobject]@{
        Category = $Category; Workload = $Workload; Licensed = $capacity; Used = $consumed
        Remaining = $remaining; PercentUsed = $percent; Status = $status
    }
}

$errors = New-Object 'System.Collections.Generic.List[object]'
$usage = New-Object 'System.Collections.Generic.List[object]'
$now = Get-Date
$stamp = $now.ToString('yyyyMMdd-HHmmss')
$reportFolder = Join-Path $ReportDirectory "Veeam-License-$stamp"
New-Item -ItemType Directory -Path $reportFolder -Force | Out-Null

try {
    Import-Module Veeam.Backup.PowerShell -ErrorAction Stop
} catch {
    throw "Cannot load Veeam.Backup.PowerShell. Run on a VBR v13 server with the console/module installed. $($_.Exception.Message)"
