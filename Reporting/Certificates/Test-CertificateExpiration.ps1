<#
.SYNOPSIS
Checks remote TLS certificate expiration and exports findings.
.DESCRIPTION
Test-CertificateExpiration is a standalone, read-only reporting tool designed for safe operational use and interview demonstrations.
.EXAMPLE
Get-Help .\Test-CertificateExpiration.ps1 -Full
.NOTES
Outputs are written beneath the repository Reports folder by default.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InputCsv,

    [ValidateRange(1, 3650)]
    [int]$WarningDays = 30,

    [ValidateRange(1, 120)]
    [int]$TimeoutSeconds = 10,

    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\..\Reports\CSV')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RemoteCertificate {
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )

    $client = [System.Net.Sockets.TcpClient]::new()
    $stream = $null
    try {
        $task = $client.ConnectAsync($HostName, $Port)
        if (-not $task.Wait([TimeSpan]::FromSeconds($TimeoutSeconds))) {
            throw "Connection timed out after $TimeoutSeconds seconds"
        }

        $callback = { param($sender, $certificate, $chain, $sslPolicyErrors) return $true }
        $stream = [System.Net.Security.SslStream]::new($client.GetStream(), $false, $callback)
        $stream.AuthenticateAsClient($HostName)
        [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($stream.RemoteCertificate)
    }
    finally {
        if ($stream) { $stream.Dispose() }
        $client.Dispose()
    }
}

if (-not (Test-Path $InputCsv)) { throw "Input CSV not found: $InputCsv" }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$results = foreach ($endpoint in (Import-Csv $InputCsv)) {
    $hostName = $endpoint.HostName
    $port = if ($endpoint.Port) { [int]$endpoint.Port } else { 443 }
    try {
        $cert = Get-RemoteCertificate -HostName $hostName -Port $port -TimeoutSeconds $TimeoutSeconds
        $daysRemaining = [math]::Floor(($cert.NotAfter - (Get-Date)).TotalDays)
        [pscustomobject]@{
            HostName      = $hostName
            Port          = $port
            Subject       = $cert.Subject
            Issuer        = $cert.Issuer
            Thumbprint    = $cert.Thumbprint
            ValidFrom     = $cert.NotBefore
            Expires       = $cert.NotAfter
            DaysRemaining = $daysRemaining
            Status        = if ($daysRemaining -lt 0) { 'Expired' } elseif ($daysRemaining -le $WarningDays) { 'Warning' } else { 'Healthy' }
            Error         = $null
        }
    }
    catch {
        [pscustomobject]@{
            HostName      = $hostName
            Port          = $port
            Subject       = $null
            Issuer        = $null
            Thumbprint    = $null
            ValidFrom     = $null
            Expires       = $null
            DaysRemaining = $null
            Status        = 'Failed'
            Error         = $_.Exception.Message
        }
    }
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$csvPath = Join-Path $OutputDirectory "CertificateExpiration-$timestamp.csv"
$results | Sort-Object DaysRemaining | Export-Csv -Path $csvPath -NoTypeInformation
$results | Sort-Object DaysRemaining | Format-Table -AutoSize
Write-Host "Certificate report exported to $csvPath"
