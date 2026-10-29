<#
.SYNOPSIS
    SSL/TLS Certificate Expiration and Validation Scanner

.DESCRIPTION
    Scans HTTPS/TLS endpoints and reports:
      - Certificate subject and issuer
      - Certificate thumbprint
      - Expiration date and days remaining
      - Expiration status
      - Certificate validation status
      - Hostname mismatch
      - Certificate chain errors
      - Subject Alternative Names (SANs)
      - Negotiated TLS protocol
      - Connection and TLS errors

    Supports:
      - Individual hostname scanning
      - Custom TCP ports
      - CSV input
      - Interactive scanning
      - Timestamped CSV reports
      - Configurable warning threshold
      - Configurable connection timeout

    Invalid certificates are intentionally accepted during
    the TLS handshake so their properties can be inspected.

    Validation errors are captured and reported separately.

.PARAMETER InputCsv
    Optional path to a CSV containing HostName and Port columns.

.PARAMETER TargetHost
    Optional hostname or IP address to scan.

.PARAMETER Port
    TCP port used with TargetHost. Defaults to 443.

.PARAMETER WarningDays
    Number of days before expiration to generate a warning.
    Defaults to 30.

.PARAMETER TimeoutSeconds
    Maximum time allowed for TCP connection and TLS handshake
    combined. Defaults to 10 seconds.

.EXAMPLE
    .\Get-CertificateExpiration.ps1

.EXAMPLE
    .\Get-CertificateExpiration.ps1 -TargetHost google.com

.EXAMPLE
    .\Get-CertificateExpiration.ps1 -TargetHost server.company.com -Port 8443

.EXAMPLE
    .\Get-CertificateExpiration.ps1 -InputCsv .\endpoints.csv

.EXAMPLE
    .\Get-CertificateExpiration.ps1 -InputCsv .\endpoints.csv -WarningDays 60

.NOTES
    Compatible with Windows PowerShell 5.1 and PowerShell 7+.

    Scans TLS services that begin TLS immediately after
    establishing a TCP connection.

    STARTTLS protocols such as SMTP on port 25 or 587
    are not supported.
#>

[CmdletBinding()]
param(
    [string]$InputCsv,

    [string]$TargetHost,

    [ValidateRange(1, 65535)]
    [int]$Port = 443,

    [ValidateRange(1, 3650)]
    [int]$WarningDays = 30,

    [ValidateRange(1, 120)]
    [int]$TimeoutSeconds = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================
# INITIAL CONFIGURATION
# ============================================================

$basePath = if ($PSScriptRoot) {
    $PSScriptRoot
}
else {
    (Get-Location).Path
}

$relativePath = Join-Path $basePath '..\..\Reports\CSV'

try {
    $OutputDirectory = (
        New-Item -ItemType Directory `
            -Path $relativePath `
            -Force
    ).FullName
}
catch {
    $fallbackPath = Join-Path $env:USERPROFILE 'Reports\CSV'

    $OutputDirectory = (
        New-Item -ItemType Directory `
            -Path $fallbackPath `
            -Force
    ).FullName
}

$defaultCsv = Join-Path $basePath 'endpoints.csv'


# ============================================================
# DISPLAY FUNCTIONS
# ============================================================

function Show-Banner {

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "             SSL/TLS CERTIFICATE SCANNER" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Menu {

    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor Green
    Write-Host " [W] Scan another website"
    Write-Host " [C] Scan endpoints from CSV"
    Write-Host " [Q] Quit"
    Write-Host "------------------------------------------------------------" -ForegroundColor Green
}


# ============================================================
# CERTIFICATE SCANNING FUNCTION
# ============================================================

function Get-RemoteCertificate {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds
    )

    $client = $null
    $stream = $null
    $certificate = $null
    $task = $null

    $validationErrors = [System.Net.Security.SslPolicyErrors]::None
    $chainErrors = @()

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {

        # ----------------------------------------------------
        # TCP CONNECTION
        # ----------------------------------------------------

        $client = New-Object System.Net.Sockets.TcpClient

        $task = $client.ConnectAsync($HostName, $Port)

        if (-not $task.Wait(
            [TimeSpan]::FromSeconds($TimeoutSeconds)
        )) {
            throw "TCP connection timed out after $TimeoutSeconds seconds."
        }

        # Propagate connection errors.
        $task.GetAwaiter().GetResult()

        # ----------------------------------------------------
        # TLS CERTIFICATE VALIDATION CALLBACK
        # ----------------------------------------------------

        $callback = {

            param(
                $sender,
                $remoteCertificate,
                $chain,
                $sslPolicyErrors
            )

            $validationErrors = $sslPolicyErrors

            $chainErrors = @()

            if ($null -ne $chain) {

                foreach ($chainStatus in $chain.ChainStatus) {

                    $chainErrors += $chainStatus.Status.ToString()

                }
            }

            # Intentionally accept the certificate.
            # Validation failures are recorded separately.
            return $true
        }.GetNewClosure()

        # ----------------------------------------------------
        # TLS HANDSHAKE
        # ----------------------------------------------------

        $stream = New-Object System.Net.Security.SslStream(
            $client.GetStream(),
            $false,
            [System.Net.Security.RemoteCertificateValidationCallback]$callback
        )

        $remainingMilliseconds = [math]::Max(
            1,
            [int](
                ($TimeoutSeconds * 1000) -
                $stopwatch.ElapsedMilliseconds
            )
        )

        $handshakeTask = $stream.AuthenticateAsClientAsync($HostName)

        if (-not $handshakeTask.Wait($remainingMilliseconds)) {

            throw "TLS handshake timed out after $TimeoutSeconds seconds."

        }

        $handshakeTask.GetAwaiter().GetResult()

        # ----------------------------------------------------
        # RETRIEVE CERTIFICATE
        # ----------------------------------------------------

        if ($null -eq $stream.RemoteCertificate) {

            throw "The remote server did not provide a certificate."

        }

        $certificate = New-Object `
            System.Security.Cryptography.X509Certificates.X509Certificate2(
                $stream.RemoteCertificate
            )

        # ----------------------------------------------------
        # CERTIFICATE PROPERTIES
        # ----------------------------------------------------

        $subject = $certificate.Subject
        $issuer = $certificate.Issuer
        $thumbprint = $certificate.Thumbprint
        $notBefore = $certificate.NotBefore
        $notAfter = $certificate.NotAfter

        $tlsProtocol = $stream.SslProtocol.ToString()

        # ----------------------------------------------------
        # SUBJECT ALTERNATIVE NAMES
        # ----------------------------------------------------

        $sanNames = @()

        foreach ($extension in $certificate.Extensions) {

            if ($extension.Oid.Value -eq '2.5.29.17') {

                $sanText = $extension.Format($false)

                $sanNames += $sanText

            }
        }

        $sanString = if ($sanNames.Count -gt 0) {
            $sanNames -join '; '
        }
        else {
            'N/A'
        }

        # ----------------------------------------------------
        # VALIDATION STATUS
        # ----------------------------------------------------

        $validationStatus = 'Valid'

        if (
            $validationErrors -ne
            [System.Net.Security.SslPolicyErrors]::None
        ) {

            $validationStatus = $validationErrors.ToString()

        }

        $chainStatusString = if ($chainErrors.Count -gt 0) {
            ($chainErrors | Select-Object -Unique) -join '; '
        }
        else {
            'None'
        }

        # ----------------------------------------------------
        # RETURN RESULTS
        # ----------------------------------------------------

        return [pscustomobject]@{

            HostName         = $HostName
            Port             = $Port

            Subject          = $subject
            Issuer           = $issuer
            Thumbprint       = $thumbprint

            NotBefore        = $notBefore
            NotAfter         = $notAfter

            TLSProtocol      = $tlsProtocol

            SAN              = $sanString

            ValidationStatus = $validationStatus
            ChainErrors      = $chainStatusString

            ErrorMessage     = $null

        }

    }
    finally {

        $stopwatch.Stop()

        if ($null -ne $certificate) {
            $certificate.Dispose()
        }

        if ($null -ne $stream) {
            $stream.Dispose()
        }

        if ($null -ne $client) {
            $client.Dispose()
        }

    }
}


# ============================================================
# CSV IMPORT AND VALIDATION
# ============================================================

function Import-EndpointCsv {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {

        throw "CSV file not found: $Path"

    }

    $csv = @(Import-Csv -LiteralPath $Path)

    if ($csv.Count -eq 0) {

        throw "CSV file contains no endpoints."

    }

    # Validate required columns.

    $headers = @($csv[0].PSObject.Properties.Name)

    if ($headers -notcontains 'HostName') {

        throw "CSV file must contain a HostName column."

    }

    $validEndpoints = @()

    foreach ($row in $csv) {

        $hostValue = [string]$row.HostName

        if ([string]::IsNullOrWhiteSpace($hostValue)) {
            continue
        }

        $hostValue = $hostValue.Trim()

        # Default port.
        $portValue = 443

        if ($headers -contains 'Port') {

            if (-not [string]::IsNullOrWhiteSpace($row.Port)) {

                $parsedPort = 0

                if (-not [int]::TryParse(
                    $row.Port,
                    [ref]$parsedPort
                )) {

                    Write-Warning "Invalid port for $hostValue. Skipping."
                    continue

                }

                if ($parsedPort -lt 1 -or $parsedPort -gt 65535) {

                    Write-Warning "Port out of range for $hostValue. Skipping."
                    continue

                }

                $portValue = $parsedPort
            }
        }

        $validEndpoints += [pscustomobject]@{

            HostName = $hostValue
            Port     = $portValue

        }
    }

    # Remove duplicate hostname/port combinations.

    $validEndpoints = @(
        $validEndpoints |
            Sort-Object HostName, Port -Unique
    )

    if ($validEndpoints.Count -eq 0) {

        throw "No valid endpoints found in CSV."

    }

    return $validEndpoints
}


# ============================================================
# ENDPOINT SCANNING
# ============================================================

function Invoke-CertificateScan {

    param(
        [Parameter(Mandatory = $true)]
        [array]$Endpoints
    )

    $results = @()

    $total = $Endpoints.Count
    $current = 0

    foreach ($endpoint in $Endpoints) {

        $current++

        $hostName = $endpoint.HostName
        $endpointPort = [int]$endpoint.Port

        Write-Progress `
            -Activity "Scanning SSL/TLS Certificates" `
            -Status "$current of $total - ${hostName}:$endpointPort" `
            -PercentComplete (($current / $total) * 100)

        Write-Host ""
        Write-Host "Scanning ${hostName}:$endpointPort ..." -ForegroundColor Cyan

        $cert = $null

        try {

            $cert = Get-RemoteCertificate `
                -HostName $hostName `
                -Port $endpointPort `
                -TimeoutSeconds $TimeoutSeconds

            # ------------------------------------------------
            # EXPIRATION CALCULATION
            # ------------------------------------------------

            $timeRemaining = $cert.NotAfter - (Get-Date)

            $daysRemaining = [math]::Floor(
                $timeRemaining.TotalDays
            )

            if ($timeRemaining.TotalSeconds -le 0) {

                $expirationStatus = 'Expired'

            }
            elseif ($timeRemaining.TotalDays -le $WarningDays) {

                $expirationStatus = 'Warning'

            }
            else {

                $expirationStatus = 'Healthy'

            }

            # ------------------------------------------------
            # OVERALL STATUS
            # ------------------------------------------------

            $overallStatus = $expirationStatus

            if ($cert.ValidationStatus -ne 'Valid') {

                if ($expirationStatus -eq 'Expired') {
                    $overallStatus = 'Expired'
                }
                else {
                    $overallStatus = 'Invalid'
                }

            }

            # ------------------------------------------------
            # BUILD RESULT
            # ------------------------------------------------

            $result = [pscustomobject]@{

                HostName         = $hostName
                Port             = $endpointPort

                Subject          = $cert.Subject
                Issuer           = $cert.Issuer
                Thumbprint       = $cert.Thumbprint

                Expires          = $cert.NotAfter.ToString(
                    'yyyy-MM-dd HH:mm:ss'
                )

                DaysRemaining    = $daysRemaining

                ExpirationStatus = $expirationStatus
                ValidationStatus = $cert.ValidationStatus

                Status           = $overallStatus

                TLSProtocol      = $cert.TLSProtocol

                SAN              = $cert.SAN

                ChainErrors      = $cert.ChainErrors

                ErrorMessage     = ''

            }

            $results += $result

            # ------------------------------------------------
            # CONSOLE STATUS
            # ------------------------------------------------

            switch ($overallStatus) {

                'Healthy' {
                    Write-Host "  Healthy - $daysRemaining days remaining" `
                        -ForegroundColor Green
                }

                'Warning' {
                    Write-Host "  Warning - $daysRemaining days remaining" `
                        -ForegroundColor Yellow
                }

                'Expired' {
                    Write-Host "  Expired" `
                        -ForegroundColor Red
                }

                'Invalid' {
                    Write-Host "  Invalid certificate: $($cert.ValidationStatus)" `
                        -ForegroundColor Red
                }

            }

        }
        catch {

            $errorMessage = $_.Exception.Message

            Write-Host "  Failed: $errorMessage" `
                -ForegroundColor Red

            $results += [pscustomobject]@{

                HostName         = $hostName
                Port             = $endpointPort

                Subject          = 'N/A'
                Issuer           = 'N/A'
                Thumbprint       = 'N/A'

                Expires          = 'N/A'
                DaysRemaining    = $null

                ExpirationStatus = 'Unknown'
                ValidationStatus = 'Unknown'

                Status           = 'Failed'

                TLSProtocol      = 'N/A'
                SAN              = 'N/A'
                ChainErrors      = 'N/A'

                ErrorMessage     = $errorMessage

            }

        }
    }

    Write-Progress `
        -Activity "Scanning SSL/TLS Certificates" `
        -Completed

    return $results
}


# ============================================================
# REPORTING
# ============================================================

function Export-CertificateReport {

    param(
        [Parameter(Mandatory = $true)]
        [array]$Results
    )

    if ($Results.Count -eq 0) {

        Write-Warning "No results available to export."
        return

    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

    $csvPath = Join-Path `
        $OutputDirectory `
        "CertificateExpiration-$timestamp.csv"

    $Results |
        Export-Csv `
            -LiteralPath $csvPath `
            -NoTypeInformation `
            -Encoding UTF8

    # --------------------------------------------------------
    # CONSOLE TABLE
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "                   SCAN RESULTS" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    $Results |
        Format-Table `
            @{Label='HostName'; Expression={$_.HostName}; Width=25},
            @{Label='Port'; Expression={$_.Port}; Width=6},
            @{Label='Expires'; Expression={$_.Expires}; Width=20},
            @{Label='Days'; Expression={$_.DaysRemaining}; Width=7},
            @{Label='Status'; Expression={$_.Status}; Width=10},
            @{Label='Validation'; Expression={$_.ValidationStatus}; Width=25} `
            -Wrap

    # --------------------------------------------------------
    # SUMMARY
    # --------------------------------------------------------

    $healthy = @($Results | Where-Object Status -eq 'Healthy').Count
    $warning = @($Results | Where-Object Status -eq 'Warning').Count
    $expired = @($Results | Where-Object Status -eq 'Expired').Count
    $invalid = @($Results | Where-Object Status -eq 'Invalid').Count
    $failed  = @($Results | Where-Object Status -eq 'Failed').Count

    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host " SCAN SUMMARY" -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------" -ForegroundColor Cyan

    Write-Host " Total Scanned : $($Results.Count)"
    Write-Host " Healthy       : $healthy" -ForegroundColor Green
    Write-Host " Warning       : $warning" -ForegroundColor Yellow
    Write-Host " Expired       : $expired" -ForegroundColor Red
    Write-Host " Invalid       : $invalid" -ForegroundColor Red
    Write-Host " Failed        : $failed" -ForegroundColor Red

    Write-Host ""
    Write-Host "Certificate report exported to:" -ForegroundColor Green
    Write-Host $csvPath -ForegroundColor Green
}


# ============================================================
# INTERACTIVE INPUT
# ============================================================

function Read-Endpoint {

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan

    $interactiveHost = Read-Host "Enter HostName or IP Address"

    if ([string]::IsNullOrWhiteSpace($interactiveHost)) {

        Write-Warning "No hostname provided."
        return $null

    }

    $interactiveHost = $interactiveHost.Trim()

    $portInput = Read-Host "Enter TCP Port [443]"

    $interactivePort = 443

    if (-not [string]::IsNullOrWhiteSpace($portInput)) {

        $parsedPort = 0

        if (-not [int]::TryParse(
            $portInput,
            [ref]$parsedPort
        )) {

            Write-Warning "Invalid port."
            return $null

        }

        if ($parsedPort -lt 1 -or $parsedPort -gt 65535) {

            Write-Warning "Port must be between 1 and 65535."
            return $null

        }

        $interactivePort = $parsedPort
    }

    Write-Host "============================================================" -ForegroundColor Cyan

    return [pscustomobject]@{

        HostName = $interactiveHost
        Port     = $interactivePort

    }
}


# ============================================================
# MAIN EXECUTION
# ============================================================

Show-Banner

$scanMode = 'Initial'

while ($true) {

    $endpoints = @()

    try {

        switch ($scanMode) {

            'Initial' {

                if (-not [string]::IsNullOrWhiteSpace($TargetHost)) {

                    $endpoints = @(
                        [pscustomobject]@{
                            HostName = $TargetHost
                            Port     = $Port
                        }
                    )

                }
                elseif (-not [string]::IsNullOrWhiteSpace($InputCsv)) {

                    $endpoints = @(
                        Import-EndpointCsv -Path $InputCsv
                    )

                }
                elseif (Test-Path -LiteralPath $defaultCsv) {

                    Write-Host "Loading default CSV: $defaultCsv" `
                        -ForegroundColor Cyan

                    $endpoints = @(
                        Import-EndpointCsv -Path $defaultCsv
                    )

                }
                else {

                    $endpoint = Read-Endpoint

                    if ($null -ne $endpoint) {
                        $endpoints = @($endpoint)
                    }

                }

            }

            'Website' {

                $endpoint = Read-Endpoint

                if ($null -ne $endpoint) {
                    $endpoints = @($endpoint)
                }

            }

            'CSV' {

                $csvInput = Read-Host "Enter CSV path [default: $defaultCsv]"

                if ([string]::IsNullOrWhiteSpace($csvInput)) {
                    $csvInput = $defaultCsv
                }

                $endpoints = @(
                    Import-EndpointCsv -Path $csvInput
                )

            }

        }

        if ($endpoints.Count -gt 0) {

            Write-Host ""
            Write-Host "Starting scan of $($endpoints.Count) endpoint(s)..." `
                -ForegroundColor Cyan

            $results = @(
                Invoke-CertificateScan -Endpoints $endpoints
            )

            Export-CertificateReport -Results $results

        }
        else {

            Write-Warning "No endpoints selected."

        }

    }
    catch {

        Write-Host ""
        Write-Host "Error: $($_.Exception.Message)" `
            -ForegroundColor Red

    }

    # --------------------------------------------------------
    # MENU
    # --------------------------------------------------------

    $validSelection = $false

    while (-not $validSelection) {

        Show-Menu

        $menuAction = Read-Host "Select an option"

        switch ($menuAction.Trim().ToLower()) {

            'w' {

                $scanMode = 'Website'
                $validSelection = $true

            }

            'c' {

                $scanMode = 'CSV'
                $validSelection = $true

            }

            'q' {

                Write-Host ""
                Write-Host "Exiting script cleanly. Goodbye!" `
                    -ForegroundColor Cyan

                return

            }

            default {

                Write-Host "Invalid selection. Choose W, C, or Q." `
                    -ForegroundColor Yellow

            }

        }

    }

}
