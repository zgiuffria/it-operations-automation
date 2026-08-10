<#
.SYNOPSIS
Reports Microsoft 365 license utilization.
.DESCRIPTION
Compares subscribed SKU capacity with consumed units and calculates available licenses.
This script performs read-only Microsoft 365 reporting through Microsoft Graph PowerShell. It does not modify tenant data.
.PARAMETER OutputDirectory
Directory where CSV output is written.
.PARAMETER DisconnectWhenComplete
Disconnects the current Microsoft Graph session after the report finishes.
.EXAMPLE
.\Get-M365LicenseUtilization.ps1
.NOTES
Required delegated scopes: Organization.Read.All, Directory.Read.All
Some data may require an appropriate Microsoft 365 or Microsoft Entra license and administrator consent.
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\..\Reports\CSV'),

    [switch]$DisconnectWhenComplete
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

$requiredScopes = @('Organization.Read.All','Directory.Read.All')
Connect-RequiredGraphScope -Scopes $requiredScopes
$response = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/subscribedSkus'
$report = $response.value | ForEach-Object {
    $enabled = [int]$_.prepaidUnits.enabled
    $consumed = [int]$_.consumedUnits
    [pscustomobject]@{
        SkuPartNumber  = $_.skuPartNumber
        SkuId          = $_.skuId
        EnabledUnits   = $enabled
        ConsumedUnits  = $consumed
        AvailableUnits = $enabled - $consumed
        UtilizationPct = if ($enabled -gt 0) { [math]::Round(($consumed / $enabled) * 100, 2) } else { 0 }
        CapabilityStatus = $_.capabilityStatus
    }
}
$path = New-ReportPath -Name 'M365-LicenseUtilization'
$report | Sort-Object UtilizationPct -Descending | Export-Csv $path -NoTypeInformation -Encoding UTF8
Write-Output $report
Write-Host "Report saved to $path"
if ($DisconnectWhenComplete) { Disconnect-MgGraph | Out-Null }
