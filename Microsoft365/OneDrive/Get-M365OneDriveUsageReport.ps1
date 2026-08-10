<#
.SYNOPSIS
Exports OneDrive usage details.
.DESCRIPTION
Downloads OneDrive storage, activity, owner, and site usage details.
This script performs read-only Microsoft 365 reporting through Microsoft Graph PowerShell. It does not modify tenant data.
.PARAMETER OutputDirectory
Directory where CSV output is written.
.PARAMETER DisconnectWhenComplete
Disconnects the current Microsoft Graph session after the report finishes.
.EXAMPLE
.\Get-M365OneDriveUsageReport.ps1
.NOTES
Required delegated scopes: Reports.Read.All
Some data may require an appropriate Microsoft 365 or Microsoft Entra license and administrator consent.
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\..\Reports\CSV'),

    [switch]$DisconnectWhenComplete,

    [ValidateSet(7,30,90,180)]
    [int]$Days = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Connect-RequiredGraphScope {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Scopes)

    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        throw 'Microsoft Graph PowerShell is required. Install with: Install-Module Microsoft.Graph -Scope CurrentUser'
    }

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    $context = Get-MgContext
    $missing = @($Scopes | Where-Object { -not $context -or $_ -notin $context.Scopes })
    if ($missing.Count -gt 0) {
        Write-Verbose "Connecting to Microsoft Graph with scopes: $($Scopes -join ', ')"
        Connect-MgGraph -Scopes $Scopes -NoWelcome | Out-Null
    }
}

function New-ReportPath {
    param([Parameter(Mandatory)][string]$Name)
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    Join-Path $OutputDirectory ("{0}-{1}.csv" -f $Name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

$requiredScopes = @('Reports.Read.All')
Connect-RequiredGraphScope -Scopes $requiredScopes
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$path = New-ReportPath -Name 'M365-OneDriveUsage'
$uri = "https://graph.microsoft.com/v1.0/reports/getOneDriveUsageAccountDetail(period='D$Days')"
Invoke-MgGraphRequest -Method GET -Uri $uri -OutputFilePath $path
$report = Import-Csv $path
Write-Output $report
Write-Host "Report saved to $path"
if ($DisconnectWhenComplete) { Disconnect-MgGraph | Out-Null }
