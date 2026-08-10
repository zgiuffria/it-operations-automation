<#
.SYNOPSIS
Identifies potentially inactive Microsoft 365 users.
.DESCRIPTION
Compares sign-in activity with a configurable inactivity threshold and exports review candidates.
This script performs read-only Microsoft 365 reporting through Microsoft Graph PowerShell. It does not modify tenant data.
.PARAMETER OutputDirectory
Directory where CSV output is written.
.PARAMETER DisconnectWhenComplete
Disconnects the current Microsoft Graph session after the report finishes.
.EXAMPLE
.\Get-M365InactiveUsers.ps1
.NOTES
Required delegated scopes: User.Read.All, AuditLog.Read.All
Some data may require an appropriate Microsoft 365 or Microsoft Entra license and administrator consent.
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\..\Reports\CSV'),

    [switch]$DisconnectWhenComplete,

    [ValidateRange(1,3650)]
    [int]$InactivityDays = 90
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

$requiredScopes = @('User.Read.All','AuditLog.Read.All')
Connect-RequiredGraphScope -Scopes $requiredScopes
$cutoff = (Get-Date).ToUniversalTime().AddDays(-$InactivityDays)
$uri = "https://graph.microsoft.com/v1.0/users?`$select=displayName,userPrincipalName,accountEnabled,userType,createdDateTime,signInActivity&`$top=500"
$users = @()
do {
    $response = Invoke-MgGraphRequest -Method GET -Uri $uri
    $users += $response.value
    $uri = $response.'@odata.nextLink'
} while ($uri)
$report = $users | ForEach-Object {
    $last = $_.signInActivity.lastSuccessfulSignInDateTime
    $lastDate = if ($last) { [datetime]$last } else { $null }
    if ($_.accountEnabled -and (-not $lastDate -or $lastDate -lt $cutoff)) {
        [pscustomobject]@{
            DisplayName       = $_.displayName
            UserPrincipalName = $_.userPrincipalName
            UserType          = $_.userType
            CreatedDateTime   = $_.createdDateTime
            LastSuccessfulSignIn = $lastDate
            DaysSinceSignIn   = if ($lastDate) { [math]::Floor(((Get-Date).ToUniversalTime() - $lastDate).TotalDays) } else { $null }
            ReviewReason      = if ($lastDate) { "No successful sign-in in $InactivityDays days" } else { 'No successful sign-in recorded' }
        }
    }
}
$path = New-ReportPath -Name 'M365-InactiveUsers'
$report | Sort-Object DaysSinceSignIn -Descending | Export-Csv $path -NoTypeInformation -Encoding UTF8
Write-Output $report
Write-Host "Report saved to $path"
if ($DisconnectWhenComplete) { Disconnect-MgGraph | Out-Null }
