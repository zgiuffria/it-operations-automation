#requires -Version 5.1
<#
.SYNOPSIS
    Interactive SSL/TLS certificate scanner with CSV reports and certificate detail browser.
.DESCRIPTION
    Supports direct TLS endpoints (such as HTTPS). STARTTLS is not supported.
    Certificate validation errors are recorded while the handshake is allowed to finish.
    Reports are saved after every scan; the details browser uses the most recent results.
.EXAMPLE
    .\Get-CertificateExpiration.ps1 -TargetHost example.com -Port 443
.EXAMPLE
    .\Get-CertificateExpiration.ps1 -InputCsv .\endpoints.csv -WarningDays 60
#>
[CmdletBinding()]
param(
    [string]$InputCsv,
    [string]$TargetHost,
    [ValidateRange(1,65535)][int]$Port = 443,
    [ValidateRange(1,3650)][int]$WarningDays = 30,
    [ValidateRange(1,120)][int]$TimeoutSeconds = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$basePath = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$defaultCsv = Join-Path $basePath 'endpoints.csv'
$reportFolder = Join-Path $basePath '..\..\Reports\CSV'
try {
    $OutputDirectory = (New-Item -ItemType Directory -Path $reportFolder -Force -ErrorAction Stop).FullName
} catch {
    $OutputDirectory = (New-Item -ItemType Directory -Path (Join-Path $HOME 'Reports\CSV') -Force -ErrorAction Stop).FullName
}
$script:LastResults = @()

function New-Endpoint([string]$Name, [int]$TcpPort) {
    $Name = $Name.Trim()
    if ([string]::IsNullOrWhiteSpace($Name)) { throw 'Hostname cannot be empty.' }
    if ($Name -match '^[a-z][a-z0-9+.-]*://') { throw 'Enter a hostname, not a URL (omit https://).' }
    if ($Name -match '[\s/]') { throw 'Hostname must not contain spaces or URL paths.' }
    [pscustomobject]@{ HostName = $Name; Port = $TcpPort }
}

function Import-EndpointList([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "CSV file not found: $Path" }
    $rows = @(Import-Csv -LiteralPath $Path)
    if ($rows.Count -eq 0) { throw 'CSV has no data rows.' }
    $columns = @($rows[0].PSObject.Properties.Name)
    if ($columns -notcontains 'HostName') { throw 'CSV must have a HostName column.' }
    $list = New-Object 'System.Collections.Generic.List[object]'
    foreach ($row in $rows) {
        $name = [string]$row.HostName
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $tcpPort = 443
        if ($columns -contains 'Port' -and -not [string]::IsNullOrWhiteSpace([string]$row.Port)) {
            $parsed = 0
            if (-not [int]::TryParse(([string]$row.Port).Trim(), [ref]$parsed) -or $parsed -lt 1 -or $parsed -gt 65535) {
                Write-Warning "Skipping '$name': invalid port '$($row.Port)'."
                continue
            }
            $tcpPort = $parsed
        }
        try { $list.Add((New-Endpoint $name $tcpPort)) }
        catch { Write-Warning "Skipping '$name': $($_.Exception.Message)" }
    }
    $unique = @($list | Sort-Object HostName, Port -Unique)
    if ($unique.Count -eq 0) { throw 'No valid endpoints in CSV.' }
    return $unique
}

function Read-SingleEndpoint {
    $name = Read-Host 'Hostname or IP (no https://)'
    if ([string]::IsNullOrWhiteSpace($name)) { Write-Warning 'No hostname entered.'; return $null }
    $portText = Read-Host 'TCP port [443]'
    $tcpPort = 443
    if (-not [string]::IsNullOrWhiteSpace($portText)) {
        if (-not [int]::TryParse($portText.Trim(), [ref]$tcpPort) -or $tcpPort -lt 1 -or $tcpPort -gt 65535) {
            Write-Warning 'Port must be a number from 1 to 65535.'
            return $null
        }
    }
    try { return New-Endpoint $name $tcpPort }
    catch { Write-Warning $_.Exception.Message; return $null }
}

function Get-RemoteCertificate {
    param([string]$HostName, [int]$Port, [int]$TimeoutSeconds)
    $client = $null
    $ssl = $null
    $cert = $null
    $state = [pscustomobject]@{ Errors = [System.Net.Security.SslPolicyErrors]::None; ChainErrors = @() }
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $connect = $client.ConnectAsync($HostName, $Port)
        if (-not $connect.Wait([TimeSpan]::FromSeconds($TimeoutSeconds))) { throw "TCP connection timed out after $TimeoutSeconds seconds." }
        $connect.GetAwaiter().GetResult()

        $callbackScript = {
            param($sender, $remoteCert, $chain, $errors)
            $state.Errors = $errors
            $state.ChainErrors = @()
            if ($null -ne $chain) {
                $state.ChainErrors = @($chain.ChainStatus | ForEach-Object { $_.Status.ToString() } | Select-Object -Unique)
            }
            return $true  # Inspection only: never use this callback for ordinary HTTPS requests.
        }.GetNewClosure()
        $callback = [System.Net.Security.RemoteCertificateValidationCallback]$callbackScript
        $ssl = [System.Net.Security.SslStream]::new($client.GetStream(), $false, $callback)
        $remaining = [int][math]::Max(1, ($TimeoutSeconds * 1000 - $timer.ElapsedMilliseconds))
        $auth = $ssl.AuthenticateAsClientAsync($HostName)
        if (-not $auth.Wait($remaining)) { throw "TLS handshake timed out after $TimeoutSeconds seconds." }
        $auth.GetAwaiter().GetResult()
        if ($null -eq $ssl.RemoteCertificate) { throw 'Server did not provide a certificate.' }
        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($ssl.RemoteCertificate)

        $sans = @()
        foreach ($extension in $cert.Extensions) {
            if ($extension.Oid.Value -eq '2.5.29.17') { $sans += $extension.Format($false) }
        }
        [pscustomobject]@{
            Subject = $cert.Subject
            Issuer = $cert.Issuer
            Thumbprint = $cert.Thumbprint
            SerialNumber = $cert.SerialNumber
            NotBefore = $cert.NotBefore
            NotAfter = $cert.NotAfter
            SignatureAlgorithm = $cert.SignatureAlgorithm.FriendlyName
            PublicKeyAlgorithm = $cert.PublicKey.Oid.FriendlyName
            TLSProtocol = $ssl.SslProtocol.ToString()
            SAN = if ($sans.Count) { $sans -join '; ' } else { 'N/A' }
            ValidationStatus = if ($state.Errors -eq [System.Net.Security.SslPolicyErrors]::None) { 'Valid' } else { $state.Errors.ToString() }
            ChainErrors = if ($state.ChainErrors.Count) { $state.ChainErrors -join '; ' } else { 'None' }
        }
    } finally {
        $timer.Stop()
        if ($null -ne $cert) { $cert.Dispose() }
        if ($null -ne $ssl) { $ssl.Dispose() }
        if ($null -ne $client) { $client.Dispose() }
    }
}

function Invoke-CertificateScan([object[]]$Endpoints) {
    $results = New-Object 'System.Collections.Generic.List[object]'
    $count = 0
    foreach ($endpoint in $Endpoints) {
        $count++
        $name = [string]$endpoint.HostName
        $tcpPort = [int]$endpoint.Port
        Write-Progress -Activity 'Scanning TLS certificates' -Status "$count/$($Endpoints.Count): ${name}:$tcpPort" -PercentComplete (100 * $count / $Endpoints.Count)
        Write-Host "Scanning ${name}:$tcpPort ..." -ForegroundColor Cyan
        try {
            $info = Get-RemoteCertificate -HostName $name -Port $tcpPort -TimeoutSeconds $TimeoutSeconds
            $remaining = $info.NotAfter - (Get-Date)
            $days = [math]::Floor($remaining.TotalDays)
            $expiration = if ($remaining.TotalSeconds -le 0) { 'Expired' } elseif ($remaining.TotalDays -le $WarningDays) { 'Warning' } else { 'Healthy' }
            $status = if ($expiration -eq 'Expired') { 'Expired' } elseif ($info.ValidationStatus -ne 'Valid') { 'Invalid' } else { $expiration }
            $results.Add([pscustomobject]@{
                HostName=$name; Port=$tcpPort; Subject=$info.Subject; Issuer=$info.Issuer
                Thumbprint=$info.Thumbprint; SerialNumber=$info.SerialNumber
                NotBefore=$info.NotBefore.ToString('yyyy-MM-dd HH:mm:ss')
                Expires=$info.NotAfter.ToString('yyyy-MM-dd HH:mm:ss')
                DaysRemaining=$days; ExpirationStatus=$expiration; ValidationStatus=$info.ValidationStatus
                Status=$status; TLSProtocol=$info.TLSProtocol; SAN=$info.SAN
                SignatureAlgorithm=$info.SignatureAlgorithm; PublicKeyAlgorithm=$info.PublicKeyAlgorithm
                ChainErrors=$info.ChainErrors; ErrorMessage=''
            })
            $color = switch ($status) { 'Healthy' {'Green'} 'Warning' {'Yellow'} default {'Red'} }
            Write-Host "  $status ($days days remaining)" -ForegroundColor $color
        } catch {
            $message = $_.Exception.Message
            Write-Warning "${name}:$tcpPort - $message"
            $results.Add([pscustomobject]@{
                HostName=$name; Port=$tcpPort; Subject='N/A'; Issuer='N/A'; Thumbprint='N/A'
                SerialNumber='N/A'; NotBefore='N/A'; Expires='N/A'; DaysRemaining=$null
                ExpirationStatus='Unknown'; ValidationStatus='Unknown'; Status='Failed'
                TLSProtocol='N/A'; SAN='N/A'; SignatureAlgorithm='N/A'; PublicKeyAlgorithm='N/A'
                ChainErrors='N/A'; ErrorMessage=$message
            })
        }
    }
    Write-Progress -Activity 'Scanning TLS certificates' -Completed
    return $results.ToArray()
}

function Show-ScanSummary([object[]]$Results) {
    Write-Host "`n==================== SCAN RESULTS ====================" -ForegroundColor Cyan
    $Results | Format-Table -AutoSize HostName, Port, Expires, DaysRemaining, Status, ValidationStatus | Out-Host
    foreach ($kind in @('Healthy','Warning','Expired','Invalid','Failed')) {
        $amount = @($Results | Where-Object { $_.Status -eq $kind }).Count
        $color = switch ($kind) { 'Healthy' {'Green'} 'Warning' {'Yellow'} default {'Red'} }
        Write-Host ("  {0,-8}: {1}" -f $kind, $amount) -ForegroundColor $color
    }
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $path = Join-Path $OutputDirectory "CertificateExpiration-$timestamp.csv"
    $Results | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8
    Write-Host "`nCSV report: $path" -ForegroundColor Green
}

function Show-CertificateDetails([object]$Certificate) {
    Write-Host "`n================ CERTIFICATE DETAILS ================" -ForegroundColor Cyan
    $fields = [ordered]@{
        'Host Name' = $Certificate.HostName
        'Port' = $Certificate.Port
        'Overall Status' = $Certificate.Status
        'Expiration Status' = $Certificate.ExpirationStatus
        'Validation Status' = $Certificate.ValidationStatus
        'Subject' = $Certificate.Subject
        'Issuer' = $Certificate.Issuer
        'Thumbprint' = $Certificate.Thumbprint
        'Serial Number' = $Certificate.SerialNumber
        'Valid From' = $Certificate.NotBefore
        'Expires' = $Certificate.Expires
        'Days Remaining' = if ($null -eq $Certificate.DaysRemaining) { 'N/A' } else { $Certificate.DaysRemaining }
        'TLS Protocol' = $Certificate.TLSProtocol
        'Signature Algorithm' = $Certificate.SignatureAlgorithm
        'Public Key Algorithm' = $Certificate.PublicKeyAlgorithm
        'Subject Alternative Names' = $Certificate.SAN
        'Certificate Chain Errors' = $Certificate.ChainErrors
        'Connection / TLS Error' = if ($Certificate.ErrorMessage) { $Certificate.ErrorMessage } else { 'None' }
    }
    foreach ($key in $fields.Keys) {
        Write-Host ("{0,-26}: {1}" -f $key, $fields[$key])
    }
    Write-Host '=====================================================' -ForegroundColor Cyan
}

function Show-CertificateBrowser {
    if ($script:LastResults.Count -eq 0) {
        Write-Warning 'No scan results available. Run a scan first.'
        return
    }
    while ($true) {
        Write-Host "`n================ CERTIFICATE LIST ==================" -ForegroundColor Cyan
        for ($i = 0; $i -lt $script:LastResults.Count; $i++) {
            $item = $script:LastResults[$i]
            $daysText = if ($null -eq $item.DaysRemaining) { 'N/A' } else { [string]$item.DaysRemaining }
            Write-Host ("{0,3}. {1,-28} {2,5}  {3,-9} {4,6} days" -f ($i + 1), $item.HostName, $item.Port, $item.Status, $daysText)
        }
        Write-Host '  0. Return to main menu'
        $selection = Read-Host 'Select certificate number'
        $number = -1
        if (-not [int]::TryParse($selection, [ref]$number)) {
            Write-Warning 'Enter a number from the list.'
            continue
        }
        if ($number -eq 0) { return }
        if ($number -lt 1 -or $number -gt $script:LastResults.Count) {
            Write-Warning 'Invalid certificate number.'
            continue
        }
        Show-CertificateDetails $script:LastResults[$number - 1]
        [void](Read-Host 'Press Enter to return to the certificate list')
    }
}

function Start-Scan([object[]]$Endpoints) {
    if ($Endpoints.Count -eq 0) { Write-Warning 'No endpoints to scan.'; return }
    $script:LastResults = @(Invoke-CertificateScan -Endpoints $Endpoints)
    Show-ScanSummary -Results $script:LastResults
}

Write-Host "`n=====================================================" -ForegroundColor Cyan
Write-Host '            SSL/TLS CERTIFICATE SCANNER' -ForegroundColor Cyan
Write-Host '=====================================================' -ForegroundColor Cyan

try {
    if (-not [string]::IsNullOrWhiteSpace($TargetHost)) {
        Start-Scan -Endpoints @((New-Endpoint $TargetHost $Port))
    } elseif (-not [string]::IsNullOrWhiteSpace($InputCsv)) {
        Start-Scan -Endpoints @(Import-EndpointList $InputCsv)
    } elseif (Test-Path -LiteralPath $defaultCsv -PathType Leaf) {
        Write-Host "Loading default CSV: $defaultCsv" -ForegroundColor Cyan
        Start-Scan -Endpoints @(Import-EndpointList $defaultCsv)
    } else {
        $endpoint = Read-SingleEndpoint
        if ($null -ne $endpoint) { Start-Scan -Endpoints @($endpoint) }
    }
} catch { Write-Warning "Initial scan failed: $($_.Exception.Message)" }

while ($true) {
    Write-Host "`n================ CERTIFICATE SCANNER MENU ================" -ForegroundColor Cyan
    Write-Host '  [1] Scan another website'
    Write-Host '  [2] Scan endpoints from CSV'
    Write-Host '  [3] View certificate details'
    Write-Host '  [4] Quit'
    Write-Host '==========================================================' -ForegroundColor Cyan
    $choice = (Read-Host 'Select an option').Trim()
    switch ($choice) {
        '1' {
            $endpoint = Read-SingleEndpoint
            if ($null -ne $endpoint) { Start-Scan -Endpoints @($endpoint) }
        }
        '2' {
            $path = Read-Host "CSV path [default: $defaultCsv]"
            if ([string]::IsNullOrWhiteSpace($path)) { $path = $defaultCsv }
            try { Start-Scan -Endpoints @(Import-EndpointList $path.Trim('"')) }
            catch { Write-Warning $_.Exception.Message }
        }
        '3' { Show-CertificateBrowser }
        '4' { Write-Host 'Exiting.' -ForegroundColor Cyan; return }
        default { Write-Warning 'Please select 1, 2, 3, or 4.' }
    }
}
