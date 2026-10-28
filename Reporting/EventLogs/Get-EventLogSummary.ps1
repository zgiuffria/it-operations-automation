<#
.SYNOPSIS
Summarizes recent Windows warning, error, and critical events.
.DESCRIPTION
Get-EventLogSummary is a standalone, read-only reporting tool designed for safe operational use and interview demonstrations.
.EXAMPLE
Get-Help .\Get-EventLogSummary.ps1 -Full
.NOTES
Outputs are written beneath the repository Reports folder or user profile fallback.
#>
[CmdletBinding()]
param(
    [string[]]$ComputerName = @($env:COMPUTERNAME),

    [ValidateRange(1, 720)]
    [int]$Hours = 24,

    [ValidateRange(1, 10000)]
    [int]$MaxEventsPerLog = 1000,

    [string[]]$LogName = @('System', 'Application'),

    [pscredential]$Credential
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function Send-ConsoleNotification {
    param(
        [string]$Title,
        [string]$Message,
        [string]$Color = 'Cyan'
    )
    $boxWidth = 60
    $dashLine = " =" * ($boxWidth / 2)
    Write-Host "`n$dashLine" -ForegroundColor $Color
    Write-Host " [!] $Title " -ForegroundColor $Color -NoNewline
    Write-Host "-> $Message" -ForegroundColor White
    Write-Host "$dashLine`n" -ForegroundColor $Color
}

# Resolve directory paths safely
$targetDir = '..\..\Reports\CSV'
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot $targetDir))) {
    $OutputDirectory = Join-Path $PSScriptRoot $targetDir
} else {
    $OutputDirectory = Join-Path $env:USERPROFILE "Reports\CSV"
}

try {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
} catch {
    Send-ConsoleNotification -Title "CRITICAL ERROR" -Message "Directory generation failed: $OutputDirectory" -Color 'Red'
    Write-Error $_.Exception.Message
    exit 1
}

$startTime = (Get-Date).AddHours(-$Hours)
Write-Host "Scanning event logs..." -ForegroundColor Cyan

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
                    TimeCreated  = $_.TimeCreated
                    ThreadId     = $_.ThreadId
                    EventId      = $_.Id
                    Provider     = $_.ProviderName
                    Channel      = $_.LogName
                    Level        = $_.LevelDisplayName
                    Message      = ($_.Message -replace '\s+', ' ').Trim()
                }
            }
        }
        catch {
            [pscustomobject]@{
                TimeCreated  = Get-Date
                ThreadId     = 0
                EventId      = 0
                Provider     = 'Script'
                Channel      = $log
                Level        = 'CollectionError'
                Message      = $_.Exception.Message
            }
        }
    }
}

if ($null -ne $events -and ($events | Measure-Object).Count -gt 0) {
    # Compile raw datasets, formatting the visual time column strings
    $summaryData = $events |
        Group-Object ThreadId, EventId, Provider, Channel, Level |
        ForEach-Object {
            $groupList = $_.Group
            $sample = $groupList | Select-Object -First 1
            $latestDateTime = ($groupList | Measure-Object TimeCreated -Maximum).Maximum
            
            [pscustomobject]@{
                ThreadId       = $sample.ThreadId
                RawTime        = $latestDateTime
                Time           = $latestDateTime.ToString("HH:mm:ss")
                EventId        = $sample.EventId
                ProviderName   = $sample.Provider
                Channel        = $sample.Channel
                Level          = $sample.Level
                Count          = $_.Count
                SampleMessage  = $sample.Message
            }
        }

    # Sort results by the raw DateTime object descending (most recent first)
    $summary = $summaryData | Sort-Object RawTime -Descending

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $detailPath = Join-Path $OutputDirectory "EventLogDetails-$timestamp.csv"
    $summaryPath = Join-Path $OutputDirectory "EventLogSummary-$timestamp.csv"
    
    $events | Export-Csv -Path $detailPath -NoTypeInformation
    $summary | Export-Csv -Path $summaryPath -NoTypeInformation
    
    # Custom property expression mappings with defined layout widths to prevent truncation
    $colThreadId   = @{Expression="ThreadId";    Width=10; Alignment="Left"}
    $colTime       = @{Expression="Time";        Width=12; Alignment="Left"}
    $colEventId    = @{Expression="EventId";     Width=10; Alignment="Left"}
    $colProvider   = @{Expression="ProviderName";Width=35; Alignment="Left"}
    $colChannel    = @{Expression="Channel";     Width=18; Alignment="Left"}
    $colCount      = @{Expression="Count";       Width=8;  Alignment="Left"}

    # Output top 25 records to the console using the wider formatting rules
    $summary | Select-Object -First 25 | Format-Table $colThreadId, $colTime, $colEventId, $colProvider, $colChannel, $colCount
    
    Write-Host "`nSummary: $summaryPath" -ForegroundColor Green
    Write-Host "Details: $detailPath" -ForegroundColor Green
    
    Send-ConsoleNotification -Title "TASK COMPLETE" -Message "Reports built and exported successfully to $OutputDirectory" -Color 'Green'
} else {
    Write-Host "No warning, error, or critical events found over the last $Hours hours." -ForegroundColor Yellow
    Send-ConsoleNotification -Title "TASK WARNING" -Message "No log alerts captured in target duration window." -Color 'Yellow'
}
