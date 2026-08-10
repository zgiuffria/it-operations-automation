<#
.SYNOPSIS
Summarizes recent Windows warning, error, and critical events.
.DESCRIPTION
Get-EventLogSummary is a standalone, read-only reporting tool designed for safe operational use and interview demonstrations.
.EXAMPLE
Get-Help .\Get-EventLogSummary.ps1 -Full
.NOTES
Outputs are written beneath the repository Reports folder by default.
#>
[CmdletBinding()]
param(
    [string[]]$ComputerName = @($env:COMPUTERNAME),

    [ValidateRange(1, 720)]
    [int]$Hours = 24,

    [ValidateRange(1, 10000)]
    [int]$MaxEventsPerLog = 1000,

    [string[]]$LogName = @('System', 'Application'),

    [pscredential]$Credential,

    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\..\Reports\CSV')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$startTime = (Get-Date).AddHours(-$Hours)

$events = foreach ($computer in $ComputerName) {
    foreach ($log in $LogName) {
        try {
            $params = @{
                ComputerName = $computer
                FilterHashtable = @{ LogName = $log; Level = 1,2,3; StartTime = $startTime }
                MaxEvents = $MaxEventsPerLog
                ErrorAction = 'Stop'
            }
            if ($Credential) { $params.Credential = $Credential }

            Get-WinEvent @params | ForEach-Object {
                [pscustomobject]@{
                    ComputerName = $computer
                    LogName      = $log
                    TimeCreated  = $_.TimeCreated
                    Level        = $_.LevelDisplayName
                    Provider     = $_.ProviderName
                    EventId      = $_.Id
                    Message      = ($_.Message -replace '\s+', ' ').Trim()
                }
            }
        }
        catch {
            [pscustomobject]@{
                ComputerName = $computer
                LogName      = $log
                TimeCreated  = Get-Date
                Level        = 'CollectionError'
                Provider     = 'Script'
                EventId      = 0
                Message      = $_.Exception.Message
            }
        }
    }
}

$summary = $events |
    Group-Object ComputerName, LogName, Level, Provider, EventId |
    Sort-Object Count -Descending |
    ForEach-Object {
        $sample = $_.Group | Select-Object -First 1
        [pscustomobject]@{
            ComputerName = $sample.ComputerName
            LogName      = $sample.LogName
            Level        = $sample.Level
            Provider     = $sample.Provider
            EventId      = $sample.EventId
            Count        = $_.Count
            Latest       = ($_.Group | Measure-Object TimeCreated -Maximum).Maximum
            SampleMessage = $sample.Message
        }
    }

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$detailPath = Join-Path $OutputDirectory "EventLogDetails-$timestamp.csv"
$summaryPath = Join-Path $OutputDirectory "EventLogSummary-$timestamp.csv"
$events | Export-Csv -Path $detailPath -NoTypeInformation
$summary | Export-Csv -Path $summaryPath -NoTypeInformation
$summary | Select-Object -First 25 | Format-Table -AutoSize
Write-Host "Summary: $summaryPath"
Write-Host "Details: $detailPath"
