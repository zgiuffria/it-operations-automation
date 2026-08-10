<#
.SYNOPSIS
Creates a guest-account review report.
.DESCRIPTION
Lists guest users with account state, creation date, invitation state, and recent sign-in activity.
This script performs read-only Microsoft 365 reporting through Microsoft Graph PowerShell. It does not modify tenant data.
.PARAMETER OutputDirectory
Directory where CSV output is written.
.PARAMETER DisconnectWhenComplete
Disconnects the current Microsoft Graph session after the report finishes.
.EXAMPLE
.\Get-M365GuestUserReview.ps1
.NOTES
Required delegated scopes: User.Read.All, AuditLog.Read.All
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

$requiredScopes = @('User.Read.All','AuditLog.Read.All')
Connect-RequiredGraphScope -Scopes $requiredScopes
$uri = "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Guest'&`$select=displayName,userPrincipalName,mail,accountEnabled,createdDateTime,externalUserState,externalUserStateChangeDateTime,signInActivity&`$top=500"
$users = @()
do {
    $response = Invoke-MgGraphRequest -Method GET -Uri $uri -Headers @{ ConsistencyLevel='eventual' }
    $users += $response.value
    $uri = $response.'@odata.nextLink'
} while ($uri)
$report = $users | ForEach-Object {
    [pscustomobject]@{
        DisplayName          = $_.displayName
        UserPrincipalName    = $_.userPrincipalName
        Mail                 = $_.mail
        AccountEnabled       = $_.accountEnabled
        CreatedDateTime      = $_.createdDateTime
        InvitationState      = $_.externalUserState
        InvitationStateChanged = $_.externalUserStateChangeDateTime
        LastSuccessfulSignIn = $_.signInActivity.lastSuccessfulSignInDateTime
    }
}
$path = New-ReportPath -Name 'M365-GuestUserReview'
$report | Sort-Object LastSuccessfulSignIn | Export-Csv $path -NoTypeInformation -Encoding UTF8
Write-Output $report
Write-Host "Report saved to $path"
if ($DisconnectWhenComplete) { Disconnect-MgGraph | Out-Null }
