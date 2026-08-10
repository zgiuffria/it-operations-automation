<#
.SYNOPSIS
Tests DNS, ICMP, and TCP connectivity and creates CSV/HTML reports.
.DESCRIPTION
Get-NetworkHealthReport is a standalone, read-only reporting tool designed for safe operational use and interview demonstrations.
.EXAMPLE
Get-Help .\Get-NetworkHealthReport.ps1 -Full
.NOTES
Outputs are written beneath the repository Reports folder by default.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InputCsv,

    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\..\Reports\CSV'),

    [ValidateRange(1, 10)]
    [int]$PingCount = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-HostSafely {
    param([Parameter(Mandatory)][string]$ComputerName)
    try {
        $addresses = [System.Net.Dns]::GetHostAddresses($ComputerName)
        ($addresses | ForEach-Object IPAddressToString) -join ', '
    }
    catch { $null }
}

if (-not (Test-Path $InputCsv)) {
    throw "Input CSV not found: $InputCsv"
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$targets = Import-Csv $InputCsv
$results = foreach ($target in $targets) {
    $name = $target.ComputerName
    if ([string]::IsNullOrWhiteSpace($name)) { continue }

    $ports = @()
    if ($target.Ports) {
        $ports = $target.Ports -split '[,; ]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
    }

    $ping = Test-Connection -ComputerName $name -Count $PingCount -Quiet -ErrorAction SilentlyContinue
    $dns = Resolve-HostSafely -ComputerName $name

    if ($ports.Count -eq 0) {
        [pscustomobject]@{
            ComputerName = $name
            Description  = $target.Description
            IPAddress    = $dns
            Ping         = if ($ping) { 'Pass' } else { 'Fail' }
            Port         = ''
            PortStatus   = 'Not Tested'
            CheckedAt    = Get-Date
        }
        continue
    }

    foreach ($port in $ports) {
        $portOpen = Test-NetConnection -ComputerName $name -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue
        [pscustomobject]@{
            ComputerName = $name
            Description  = $target.Description
            IPAddress    = $dns
            Ping         = if ($ping) { 'Pass' } else { 'Fail' }
            Port         = $port
            PortStatus   = if ($portOpen) { 'Open' } else { 'Closed/Filtered' }
            CheckedAt    = Get-Date
        }
    }
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$csvPath = Join-Path $OutputDirectory "NetworkHealth-$timestamp.csv"
$htmlPath = Join-Path $OutputDirectory "NetworkHealth-$timestamp.html"

$results | Export-Csv -Path $csvPath -NoTypeInformation

$style = @'
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:24px;color:#222}
h1{margin-bottom:4px}.meta{color:#666;margin-bottom:18px}
table{border-collapse:collapse;width:100%}th,td{border:1px solid #ddd;padding:8px;text-align:left}
th{background:#f3f4f6}tr:nth-child(even){background:#fafafa}
</style>
'@

$body = $results | ConvertTo-Html -Fragment
ConvertTo-Html -Title 'Network Health Report' -Head $style -Body "<h1>Network Health Report</h1><div class='meta'>Generated $(Get-Date)</div>$body" |
    Set-Content -Path $htmlPath -Encoding UTF8

Write-Host "CSV report:  $csvPath"
Write-Host "HTML report: $htmlPath"
