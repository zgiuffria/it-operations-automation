<#
.SYNOPSIS
    Interactive read-only DNS, ICMP and TCP connectivity report.
.DESCRIPTION
    Scan selected hosts or CSV targets, inspect results, and export CSV/HTML.
    Designed for Windows PowerShell 5.1 and PowerShell 7+ on Windows.
    ICMP failure does not imply the host is offline; ICMP may be blocked.
.PARAMETER TargetHost
    Optional hostname or IP to select at startup.
.PARAMETER Ports
    TCP ports to check with TargetHost (default: 443).
.PARAMETER InputCsv
    Optional CSV with ComputerName, Ports and Description columns.
.PARAMETER PingCount
    ICMP attempts per target (1-10).
.PARAMETER TimeoutSeconds
    Timeout per TCP port connection (1-120).
.PARAMETER NoInitialScan
    Start at the menu without automatically scanning selected targets.
.EXAMPLE
    .\Get-NetworkHealthReport.ps1 -TargetHost server01 -Ports 443,3389
.EXAMPLE
    .\Get-NetworkHealthReport.ps1 -InputCsv .\network_targets.csv
.NOTES
    The scan tests connectivity only. TCP 'Open' does not validate the application protocol.
    Reports are written under ..\..\Reports\CSV or a user-profile fallback.
#>
[CmdletBinding()]
param(
    [string]$TargetHost,
    [ValidateRange(1,65535)][int[]]$Ports = @(443),
    [string]$InputCsv,
    [ValidateRange(1,10)][int]$PingCount = 2,
    [ValidateRange(1,120)][int]$TimeoutSeconds = 5,
    [switch]$NoInitialScan
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Targets = @()
$script:Results = @()
$script:HasScan = $false
$script:LastScan = $null
$basePath = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

function Get-ReportDirectory {
    $preferred = Join-Path $basePath '..\..\Reports\CSV'
    try { return (New-Item -ItemType Directory -Path $preferred -Force -ErrorAction Stop).FullName }
    catch {
        $profilePath = if ($env:USERPROFILE) { $env:USERPROFILE } else { [Environment]::GetFolderPath('UserProfile') }
        $fallback = Join-Path $profilePath 'Reports\CSV'
        return (New-Item -ItemType Directory -Path $fallback -Force -ErrorAction Stop).FullName
    }
}
$OutputDirectory = Get-ReportDirectory

function Read-MenuChoice {
    param([string]$Prompt,[string[]]$Allowed)
    while ($true) {
        $answer = (Read-Host $Prompt).Trim()
        if ($Allowed -contains $answer) { return $answer }
        Write-Host "Invalid choice. Select $($Allowed -join ', ')." -ForegroundColor Yellow
    }
}
function ConvertTo-Ports {
    param([string]$Text,[switch]$AllowEmpty)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        if ($AllowEmpty) { return @() }
        return @(443)
    }
    $list = @()
    foreach ($token in ($Text -split '[,;\s]+')) {
        if (-not $token) { continue }
        $number = 0
        if (-not [int]::TryParse($token,[ref]$number) -or $number -lt 1 -or $number -gt 65535) {
            throw "Invalid TCP port '$token'. Ports must be 1-65535."
        }
        $list += $number
    }
    return @($list | Sort-Object -Unique)
}
function New-Target {
    param([string]$Name,[int[]]$PortList,[string]$Description='')
    $nameValue = $Name.Trim()
    if (-not $nameValue) { throw 'Target name cannot be blank.' }
    # A host or IP is expected, not a URL. IPv6 literals may contain colons.
    if ($nameValue -match '[\s/\\]' -or $nameValue -match '^\w+://') {
        throw "Invalid target '$nameValue'. Enter a hostname or IP address, not a URL."
    }
    return [pscustomobject]@{
        ComputerName = $nameValue
        Ports = @($PortList | Sort-Object -Unique)
        Description = $Description
    }
}
function Import-Targets {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "CSV not found: $Path" }
    $rows = @(Import-Csv -LiteralPath $Path -ErrorAction Stop)
    if ($rows.Count -eq 0) { throw 'CSV contains no rows.' }
    $columns = @($rows[0].PSObject.Properties.Name)
    if ($columns -notcontains 'ComputerName') { throw 'CSV requires a ComputerName column.' }
    $imported = @()
    $line = 1
    foreach ($row in $rows) {
        $line++
        if ([string]::IsNullOrWhiteSpace([string]$row.ComputerName)) {
            Write-Warning "CSV row $line has no ComputerName; skipped."
            continue
        }
        try {
            $portText = if ($columns -contains 'Ports') { [string]$row.Ports } else { '' }
            $description = if ($columns -contains 'Description') { [string]$row.Description } else { '' }
            $portList = @(ConvertTo-Ports -Text $portText -AllowEmpty)
            $imported += New-Target -Name ([string]$row.ComputerName) -PortList $portList -Description $description
        } catch { Write-Warning "CSV row $line skipped: $($_.Exception.Message)" }
    }
    if ($imported.Count -eq 0) { throw 'No valid CSV targets were found.' }
    return $imported
}
function Resolve-Target {
    param([string]$Name)
    try {
        $addresses = @([System.Net.Dns]::GetHostAddresses($Name))
        if ($addresses.Count -eq 0) { throw 'No addresses returned.' }
        return [pscustomobject]@{ Status='Pass'; IPAddress=(($addresses | ForEach-Object IPAddressToString) -join ', '); Error='' }
    } catch { return [pscustomobject]@{ Status='Fail'; IPAddress=''; Error=$_.Exception.Message } }
}
function Test-Icmp {
    param([string]$Name,[int]$Count)
    try {
        # -Quiet is supported on Windows PowerShell 5.1 and PowerShell 7.
        $success = Test-Connection -ComputerName $Name -Count $Count -Quiet -ErrorAction Stop
        return [pscustomobject]@{ Status=$(if ($success) {'Pass'} else {'Fail'}); Error='' }
    } catch { return [pscustomobject]@{ Status='Fail'; Error=$_.Exception.Message } }
}
function Test-TcpPort {
    param([string]$Name,[int]$Port,[int]$Timeout)
    $client = $null
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $task = $client.ConnectAsync($Name,$Port)
        if (-not $task.Wait([TimeSpan]::FromSeconds($Timeout))) {
            return [pscustomobject]@{ Status='Timeout'; Error="No TCP connection within $Timeout second(s)." }
        }
        $task.GetAwaiter().GetResult()
        return [pscustomobject]@{ Status='Open'; Error='' }
    } catch {
        # A failed TCP connect cannot reliably distinguish 'closed' from 'filtered'.
        return [pscustomobject]@{ Status='Failed'; Error=$_.Exception.Message }
    } finally {
        if ($null -ne $client) { $client.Dispose() }
    }
}
# Handle unexpected/null probe results without terminating under StrictMode.
function Get-ProbeField {
    param(
        [AllowNull()][object]$Probe,
        [Parameter(Mandatory=$true)][string]$Property,
        [string]$Default = ''
    )
    if ($null -eq $Probe) { return $Default }
    $prop = $Probe.PSObject.Properties[$Property]
    if ($null -eq $prop -or $null -eq $prop.Value) { return $Default }
    return [string]$prop.Value
}

function Invoke-NetworkScan {
    param([object[]]$TargetList)
    if ($TargetList.Count -eq 0) { Write-Host 'Select targets first.' -ForegroundColor Yellow; return }
    $script:Results = @()
    $script:HasScan = $true
    $script:LastScan = Get-Date
    $index = 0
    foreach ($target in $TargetList) {
        $index++
        $name = [string]$target.ComputerName
        Write-Host "[$index/$($TargetList.Count)] Checking $name ..." -ForegroundColor Cyan
        $dns = Resolve-Target $name
        $ping = Test-Icmp $name $PingCount
        $portList = @($target.Ports)
        if ($portList.Count -eq 0) { $portList = @($null) }
        foreach ($port in $portList) {
            $tcp = if ($null -eq $port) {
                [pscustomobject]@{ Status='Not Tested'; Error='' }
            } else { Test-TcpPort -Name $name -Port ([int]$port) -Timeout $TimeoutSeconds }
            $script:Results += [pscustomobject]@{
                ComputerName=$name
                Description=[string]$target.Description
                IPAddress=(Get-ProbeField $dns IPAddress)
                DNSStatus=(Get-ProbeField $dns Status 'Unknown')
                Ping=(Get-ProbeField $ping Status 'Unknown')
                Port=$(if ($null -eq $port) { '' } else { [string]$port })
                PortStatus=(Get-ProbeField $tcp Status 'Unknown')
                DNSError=(Get-ProbeField $dns Error)
                PingError=(Get-ProbeField $ping Error)
                TCPError=(Get-ProbeField $tcp Error)
                CheckedAt=Get-Date
            }
        }
    }
    Write-Host "`nScan complete: $($TargetList.Count) target(s), $($script:Results.Count) result row(s)." -ForegroundColor Green
    Show-Results
}
function Show-Results {
    if (-not $script:HasScan) { Write-Host 'Run a scan first.' -ForegroundColor Yellow; return }
    if ($script:Results.Count -eq 0) { Write-Host 'No scan results.'; return }
    $script:Results | Select-Object ComputerName,IPAddress,DNSStatus,Ping,Port,PortStatus |
        Format-Table -AutoSize -Wrap | Out-Host
}
function Show-DeviceDetails {
    if (-not $script:HasScan -or $script:Results.Count -eq 0) {
        Write-Host 'Run a scan first.' -ForegroundColor Yellow; return
    }
    $names = @($script:Results | Select-Object -ExpandProperty ComputerName -Unique)
    while ($true) {
        Write-Host "`n================ TARGET DETAILS ================" -ForegroundColor Cyan
        for ($i=0; $i -lt $names.Count; $i++) { Write-Host " [$($i+1)] $($names[$i])" }
        Write-Host ' [0] Back to main menu'
        $s = (Read-Host 'Select target number').Trim()
        if ($s -eq '0') { return }
        $number = 0
        if (-not [int]::TryParse($s,[ref]$number) -or $number -lt 1 -or $number -gt $names.Count) {
            Write-Host 'Invalid selection.' -ForegroundColor Yellow; continue
        }
        $selected = $names[$number-1]
        Write-Host "`n================ $selected ================" -ForegroundColor Cyan
        @($script:Results | Where-Object ComputerName -eq $selected) |
            Format-List ComputerName,Description,IPAddress,DNSStatus,Ping,Port,PortStatus,DNSError,PingError,TCPError,CheckedAt | Out-Host
        [void](Read-Host 'Press Enter to return to the target list')
    }
}
function ConvertTo-HtmlSafe {
    param([AllowNull()][object]$Value)
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}
function Export-NetworkReports {
    if (-not $script:HasScan -or $script:Results.Count -eq 0) {
        Write-Host 'No scan results to export.' -ForegroundColor Yellow; return
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $csvPath = Join-Path $OutputDirectory "NetworkHealth-$stamp.csv"
    $htmlPath = Join-Path $OutputDirectory "NetworkHealth-$stamp.html"
    $script:Results | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
    $open = @($script:Results | Where-Object PortStatus -eq 'Open').Count
    $failed = @($script:Results | Where-Object { $_.PortStatus -in @('Failed','Timeout') }).Count
    $style = @'
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:24px;color:#243043;background:#f8fafc}
h1{margin-bottom:4px}.meta{color:#64748b;margin-bottom:20px}
.cards{display:flex;gap:12px;margin:16px 0}.card{padding:14px;background:white;border:1px solid #e2e8f0;border-radius:8px}
table{border-collapse:collapse;width:100%;background:white}th,td{border:1px solid #e2e8f0;padding:9px;text-align:left;vertical-align:top;word-break:break-word}
th{background:#eaf0f8}tr:nth-child(even){background:#f8fafc}.ok{color:#166534;font-weight:bold}.bad{color:#b91c1c;font-weight:bold}.neutral{color:#92400e;font-weight:bold}
</style>
'@
    $columns = @('ComputerName','Description','IPAddress','DNSStatus','Ping','Port','PortStatus','DNSError','PingError','TCPError','CheckedAt')
    $rows = foreach ($result in $script:Results) {
        $cells = foreach ($column in $columns) {
            $value = [string]$result.$column
            $cls = ''
            if ($column -in @('DNSStatus','Ping','PortStatus')) {
                $cls = if ($value -in @('Pass','Open')) { 'ok' } elseif ($value -in @('Fail','Failed','Timeout')) { 'bad' } else { 'neutral' }
            }
            '<td class="{0}">{1}</td>' -f $cls,(ConvertTo-HtmlSafe $value)
        }
        '<tr>{0}</tr>' -f ($cells -join '')
    }
    $headers = ($columns | ForEach-Object { '<th>{0}</th>' -f (ConvertTo-HtmlSafe $_) }) -join ''
    $html = @"
<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Network Health Report</title>$style</head>
<body><h1>Network Health Report</h1><div class="meta">Generated: $(ConvertTo-HtmlSafe (Get-Date))</div>
<div class="cards"><div class="card">Targets: $(@($script:Results | Select-Object -ExpandProperty ComputerName -Unique).Count)</div><div class="card">TCP open: $open</div><div class="card">TCP failed/timeouts: $failed</div></div>
<table><thead><tr>$headers</tr></thead><tbody>$($rows -join "`n")</tbody></table>
</body></html>
"@
    Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8
    Write-Host "CSV report:  $csvPath" -ForegroundColor Green
    Write-Host "HTML report: $htmlPath" -ForegroundColor Green
}
function Set-InteractiveTargets {
    while ($true) {
        Write-Host "`n================ SELECT TARGET ================" -ForegroundColor Cyan
        Write-Host ' [1] Local computer'
        Write-Host ' [2] Single hostname or IP address'
        Write-Host ' [3] Multiple hostnames or IPs (comma-separated)'
        Write-Host ' [4] Load targets from CSV'
        Write-Host ' [0] Back to main menu'
        $choice = Read-MenuChoice 'Select an option' @('0','1','2','3','4')
        if ($choice -eq '0') { return }
        try {
            if ($choice -eq '4') {
                $path = Read-Host "CSV path [default: $(Join-Path $basePath 'network_targets.csv')]"
                if ([string]::IsNullOrWhiteSpace($path)) { $path = Join-Path $basePath 'network_targets.csv' }
                $newTargets = @(Import-Targets -Path $path)
            } else {
                if ($choice -eq '1') { $names = @($env:COMPUTERNAME) }
                elseif ($choice -eq '2') { $names = @((Read-Host 'Enter hostname or IP address').Trim()) }
                else {
                    $names = @((Read-Host 'Enter comma-separated hostnames/IPs') -split ',' |
                        ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
                }
                if ($names.Count -eq 0 -or -not $names[0]) { throw 'No target entered.' }
                $portText = Read-Host 'TCP ports (comma-separated) [default: 443; type none for DNS/ICMP only]'
                $portList = if ($portText.Trim().ToLowerInvariant() -eq 'none') { @() } else { @(ConvertTo-Ports $portText) }
                $newTargets = @($names | ForEach-Object { New-Target -Name $_ -PortList $portList })
            }
            $script:Targets = @($newTargets)
            Write-Host "Selected $($script:Targets.Count) target(s)." -ForegroundColor Green
            return
        } catch { Write-Host "Unable to set targets: $($_.Exception.Message)" -ForegroundColor Red }
    }
}

# Explicit parameters take precedence over the default CSV. No CSV is required.
try {
    if ($TargetHost) {
        $script:Targets = @(New-Target -Name $TargetHost -PortList $Ports)
    } elseif ($InputCsv) {
        $script:Targets = @(Import-Targets -Path $InputCsv)
    } else {
        $defaultCsv = Join-Path $basePath 'network_targets.csv'
        if (Test-Path -LiteralPath $defaultCsv -PathType Leaf) {
            $script:Targets = @(Import-Targets -Path $defaultCsv)
        }
    }
} catch { Write-Warning "Initial target selection failed: $($_.Exception.Message)" }

if (-not $NoInitialScan -and $script:Targets.Count -gt 0) { Invoke-NetworkScan -TargetList $script:Targets }
while ($true) {
    $selectedText = if ($script:Targets.Count -eq 0) { 'Not Selected' }
        elseif ($script:Targets.Count -eq 1) { $script:Targets[0].ComputerName }
        else { "$($script:Targets.Count) targets" }
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host '                   NETWORK HEALTH SCANNER' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host " Current Target: $selectedText"
    Write-Host ' [1] Select target device(s)'
    Write-Host ' [2] Scan selected target(s)'
    Write-Host ' [3] Scan targets from CSV'
    Write-Host ' [4] View scan results'
    Write-Host ' [5] View individual device details'
    Write-Host ' [6] Export CSV and HTML reports'
    Write-Host ' [7] Quit'
    Write-Host '============================================================' -ForegroundColor Cyan
    $choice = Read-MenuChoice 'Select an option' @('1','2','3','4','5','6','7')
    try {
        switch ($choice) {
            '1' { Set-InteractiveTargets }
            '2' { Invoke-NetworkScan -TargetList $script:Targets }
            '3' {
                $path = Read-Host "CSV path [default: $(Join-Path $basePath 'network_targets.csv')]"
                if ([string]::IsNullOrWhiteSpace($path)) { $path = Join-Path $basePath 'network_targets.csv' }
                $loaded = @(Import-Targets -Path $path)
                $script:Targets = $loaded
                Invoke-NetworkScan -TargetList $script:Targets
            }
            '4' { Show-Results }
            '5' { Show-DeviceDetails }
            '6' { Export-NetworkReports }
            '7' { Write-Host 'Goodbye.' -ForegroundColor Cyan; return }
        }
    } catch { Write-Host "Operation failed: $($_.Exception.Message)" -ForegroundColor Red }
}
