<#
.SYNOPSIS
Collects Windows server hardware, OS, disk, uptime, and patch inventory.
.DESCRIPTION
Get-WindowsServerInventory is a standalone, read-only reporting tool designed for safe operational use and interview demonstrations.
.EXAMPLE
Get-Help .\Get-WindowsServerInventory.ps1 -Full
.NOTES
Outputs are written beneath the repository Reports folder by default.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$ComputerName,

    [pscredential]$Credential,

    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\..\Reports\CSV')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$results = foreach ($computer in $ComputerName) {
    try {
        $cimParams = @{ ComputerName = $computer; ErrorAction = 'Stop' }
        if ($Credential) { $cimParams.Credential = $Credential }

        $os = Get-CimInstance @cimParams -ClassName Win32_OperatingSystem
        $system = Get-CimInstance @cimParams -ClassName Win32_ComputerSystem
        $cpu = Get-CimInstance @cimParams -ClassName Win32_Processor | Select-Object -First 1
        $disks = Get-CimInstance @cimParams -ClassName Win32_LogicalDisk -Filter "DriveType=3"
        $latestHotfix = Get-HotFix -ComputerName $computer -ErrorAction SilentlyContinue |
            Sort-Object InstalledOn -Descending | Select-Object -First 1

        foreach ($disk in $disks) {
            [pscustomobject]@{
                ComputerName       = $computer
                Manufacturer       = $system.Manufacturer
                Model              = $system.Model
                OperatingSystem    = $os.Caption
                OSVersion          = $os.Version
                LastBootTime       = $os.LastBootUpTime
                UptimeDays         = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 2)
                CPU                = $cpu.Name
                LogicalProcessors  = $system.NumberOfLogicalProcessors
                MemoryGB           = [math]::Round($system.TotalPhysicalMemory / 1GB, 2)
                Drive              = $disk.DeviceID
                DriveSizeGB        = [math]::Round($disk.Size / 1GB, 2)
                DriveFreeGB        = [math]::Round($disk.FreeSpace / 1GB, 2)
                DriveFreePercent   = if ($disk.Size) { [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1) } else { 0 }
                LatestHotfix       = $latestHotfix.HotFixID
                HotfixInstalledOn  = $latestHotfix.InstalledOn
                Status             = 'Success'
                Error              = $null
            }
        }
    }
    catch {
        [pscustomobject]@{
            ComputerName       = $computer
            Manufacturer       = $null
            Model              = $null
            OperatingSystem    = $null
            OSVersion          = $null
            LastBootTime       = $null
            UptimeDays         = $null
            CPU                = $null
            LogicalProcessors  = $null
            MemoryGB           = $null
            Drive              = $null
            DriveSizeGB        = $null
            DriveFreeGB        = $null
            DriveFreePercent   = $null
            LatestHotfix       = $null
            HotfixInstalledOn  = $null
            Status             = 'Failed'
            Error              = $_.Exception.Message
        }
    }
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$csvPath = Join-Path $OutputDirectory "WindowsServerInventory-$timestamp.csv"
$results | Export-Csv -Path $csvPath -NoTypeInformation
$results | Format-Table -AutoSize
Write-Host "Inventory exported to $csvPath"
