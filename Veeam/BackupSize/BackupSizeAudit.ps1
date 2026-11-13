<#
.SYNOPSIS
    Read-only Veeam Backup & Replication v13 backup storage footprint auditor.
.DESCRIPTION
    Inventories VBR backup objects, enumerates supported restore points, and sums
    reported backup storage metadata where exposed by the Veeam object model.
    Produces a standalone HTML dashboard, CSV reports and optional Out-GridView.
    Reported backup-file metadata is NOT equivalent to physically allocated disk
    usage (e.g., ReFS/XFS block cloning, deduplication, object storage).
.PARAMETER ReportDirectory
    Directory to store timestamped audit outputs.
.PARAMETER ShowGrid
    Open interactive Out-GridView if installed and available.
.PARAMETER SkipStorageDetails
    Skip potentially expensive GetStorages() enumeration.
.EXAMPLE
    .\Get-VeeamBackupStorageAudit.ps1 -ShowGrid
.EXAMPLE
    .\Get-VeeamBackupStorageAudit.ps1 -ReportDirectory 'D:\VeeamReports'
.NOTES
    Windows PowerShell 5.1, Veeam.Backup.PowerShell module, and access to VBR.
    Test against a representative backup before relying on the aggregate values.
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()][string]$ReportDirectory = 'C:\Reports\VeeamStorageAudit',
    [switch]$ShowGrid,
    [switch]$SkipStorageDetails
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SafeProperty {
    param([AllowNull()][object]$InputObject, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $InputObject) { return $null }
    $p = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}
function Convert-ToNullableDouble {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    $n = 0.0
    if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Any,
        [System.Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { return $n }
    return $null
}
function Html {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}
function Get-FirstValue {
    param([AllowNull()][object]$InputObject, [string[]]$Names)
    foreach ($name in $Names) {
        $value = Get-SafeProperty -InputObject $InputObject -Name $name
        if ($null -ne $value -and [string]$value -ne '') { return $value }
    }
    return $null
}
function Format-GB {
    param([AllowNull()][object]$Bytes)
    if ($null -eq $Bytes) { return 'N/A' }
    return ([math]::Round(([double]$Bytes / 1GB), 2)).ToString('N2', [System.Globalization.CultureInfo]::InvariantCulture)
}
function Add-Issue {
    param([string]$Backup, [string]$Stage, [string]$Message)
    $script:Issues.Add([pscustomobject]@{ Backup=$Backup; Stage=$Stage; Message=$Message })
}
function Export-Data {
    param([object[]]$Data, [string]$Path, [string[]]$Columns)
    if ($Data.Count -gt 0) {
        $Data | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
    } else {
        # Preserve CSV headers when a collection is empty.
        ($Columns -join ',') | Set-Content -LiteralPath $Path -Encoding UTF8
    }
}

try {
    Import-Module Veeam.Backup.PowerShell -ErrorAction Stop
    foreach ($cmd in @('Get-VBRBackup','Get-VBRRestorePoint')) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            throw "Required Veeam cmdlet unavailable: $cmd"
        }
    }
} catch {
    throw "Veeam PowerShell initialization failed: $($_.Exception.Message)"
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDir = Join-Path $ReportDirectory $stamp
New-Item -Path $runDir -ItemType Directory -Force | Out-Null
$Issues = [System.Collections.Generic.List[object]]::new()
$Rows = [System.Collections.Generic.List[object]]::new()
$StorageRows = [System.Collections.Generic.List[object]]::new()
$runStarted = Get-Date
Write-Host "Discovering Veeam backups on $env:COMPUTERNAME ..." -ForegroundColor Cyan
try {
    $backups = @(Get-VBRBackup -ErrorAction Stop)
} catch {
    throw "Unable to query Veeam backup inventory: $($_.Exception.Message)"
}

foreach ($backup in $backups) {
    $backupName = [string](Get-SafeProperty $backup 'Name')
    if (-not $backupName) { $backupName = '[Unnamed backup]' }
    Write-Verbose "Inspecting $backupName"
    $type = Get-FirstValue $backup @('TypeToString','JobType','Type')
    if ($null -eq $type) { $type = 'Unknown' }
    $repo = Get-FirstValue $backup @('RepositoryName')
    if ($null -eq $repo) { $repo = 'Unavailable' }
    $restoreCount = $null
    $restoreStatus = 'Unavailable'
    $storageCount = $null
    $backupBytes = $null
    $dataBytes = $null
    $storageStatus = if ($SkipStorageDetails) { 'Skipped' } else { 'Unavailable' }

    try {
        $points = @(Get-VBRRestorePoint -Backup $backup -ErrorAction Stop)
        $restoreCount = $points.Count
        $restoreStatus = 'Collected'
    } catch {
        Add-Issue $backupName 'RestorePoints' $_.Exception.Message
        $restoreStatus = 'Query failed or unsupported backup type'
    }

    if (-not $SkipStorageDetails) {
        try {
            if ($null -eq $backup.PSObject.Methods['GetStorages']) {
                throw 'This backup object does not expose GetStorages().'
            }
            $storages = @($backup.GetStorages() | Where-Object { $null -ne $_ })
            $storageCount = $storages.Count
            $sumBackup = 0.0; $sumData = 0.0
            $foundBackup = 0; $foundData = 0
            foreach ($storage in $storages) {
                $stats = Get-SafeProperty $storage 'Stats'
                $b = Convert-ToNullableDouble (Get-SafeProperty $stats 'BackupSize')
                $d = Convert-ToNullableDouble (Get-SafeProperty $stats 'DataSize')
                if ($null -ne $b -and $b -ge 0) { $sumBackup += $b; $foundBackup++ }
                if ($null -ne $d -and $d -ge 0) { $sumData += $d; $foundData++ }
                $StorageRows.Add([pscustomobject]@{
                    BackupName = $backupName
                    StorageName = [string](Get-FirstValue $storage @('Name','FilePath','Path'))
                    BackupSizeBytes = $b
                    DataSizeBytes = $d
                })
            }
            if ($storageCount -eq 0) {
                $storageStatus = 'No storage objects'
            } elseif ($foundBackup -eq $storageCount) {
                $backupBytes = $sumBackup
                if ($foundData -eq $storageCount) { $dataBytes = $sumData }
                $storageStatus = 'Collected'
            } else {
                $storageStatus = 'Incomplete metadata'
                Add-Issue $backupName 'StorageMetadata' "BackupSize present for $foundBackup of $storageCount storage objects; totals withheld."
            }
            if ($storageCount -gt 0 -and $foundData -ne $storageCount) {
                Add-Issue $backupName 'StorageMetadata' "DataSize present for $foundData of $storageCount storage objects; source total withheld."
            }
        } catch {
            Add-Issue $backupName 'StorageEnumeration' $_.Exception.Message
            $storageStatus = 'Query failed or unsupported backup type'
        }
    }
    $ratio = 'N/A'
    if ($null -ne $backupBytes -and $null -ne $dataBytes -and $backupBytes -gt 0 -and $dataBytes -gt 0) {
        $ratio = ('{0:N2}:1' -f ($dataBytes / $backupBytes))
    }
    $Rows.Add([pscustomobject]@{
        BackupName = $backupName
        BackupType = [string]$type
        Repository = [string]$repo
        RestorePoints = $restoreCount
        RestorePointStatus = $restoreStatus
        StorageObjects = $storageCount
        ReportedBackupGB = if ($null -ne $backupBytes) { [math]::Round($backupBytes / 1GB, 2) } else { $null }
        CumulativeDataGB = if ($null -ne $dataBytes) { [math]::Round($dataBytes / 1GB, 2) } else { $null }
        DataToBackupRatio = $ratio
        StorageStatus = $storageStatus
    })
}

$summaryPath = Join-Path $runDir 'backups.csv'
$storagePath = Join-Path $runDir 'storage-objects.csv'
$issuePath = Join-Path $runDir 'collection-errors.csv'
Export-Data -Data @($Rows.ToArray()) -Path $summaryPath -Columns @('BackupName','BackupType','Repository','RestorePoints','RestorePointStatus','StorageObjects','ReportedBackupGB','CumulativeDataGB','DataToBackupRatio','StorageStatus')
Export-Data -Data @($StorageRows.ToArray()) -Path $storagePath -Columns @('BackupName','StorageName','BackupSizeBytes','DataSizeBytes')
Export-Data -Data @($Issues.ToArray()) -Path $issuePath -Columns @('Backup','Stage','Message')

$reported = @($Rows | Where-Object { $null -ne $_.ReportedBackupGB })
$totalReportedGB = ($reported | Measure-Object -Property ReportedBackupGB -Sum).Sum
if ($null -eq $totalReportedGB) { $totalReportedGB = 0 }
$unavailableCount = @($Rows | Where-Object { $_.StorageStatus -ne 'Collected' }).Count
$knownRestorePoints = ($Rows | Where-Object { $null -ne $_.RestorePoints } | Measure-Object -Property RestorePoints -Sum).Sum
if ($null -eq $knownRestorePoints) { $knownRestorePoints = 0 }

$tableRows = [System.Text.StringBuilder]::new()
foreach ($r in ($Rows | Sort-Object -Property @{Expression='ReportedBackupGB';Descending=$true})) {
    $values = @($r.BackupName,$r.BackupType,$r.Repository,$r.RestorePoints,$r.RestorePointStatus,$r.StorageObjects,$r.ReportedBackupGB,$r.CumulativeDataGB,$r.DataToBackupRatio,$r.StorageStatus)
    [void]$tableRows.Append('<tr>')
    foreach ($v in $values) { [void]$tableRows.Append('<td>' + (Html $v) + '</td>') }
    [void]$tableRows.AppendLine('</tr>')
}
$issueRows = [System.Text.StringBuilder]::new()
foreach ($issue in $Issues) {
    [void]$issueRows.AppendLine('<tr><td>'+(Html $issue.Backup)+'</td><td>'+(Html $issue.Stage)+'</td><td>'+(Html $issue.Message)+'</td></tr>')
}
if ($Issues.Count -eq 0) { [void]$issueRows.AppendLine('<tr><td colspan="3">No collection errors recorded.</td></tr>') }

# Standalone HTML: no CDN or external JavaScript required.
$reportHtml = @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Veeam Backup Storage Audit</title>
<style>
:root{font-family:Segoe UI,Arial,sans-serif;color:#182331;background:#f3f6f9}body{margin:0;padding:24px;max-width:1500px;margin-inline:auto}
header{background:#12683e;color:white;padding:24px;border-radius:12px}header h1{margin:0 0 8px}header p{margin:0}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px;margin:18px 0}.card,section{background:white;border-radius:12px;padding:18px;box-shadow:0 1px 6px #0001}
.card strong{font-size:28px;display:block}.card span{color:#526273;font-size:13px}section{margin:18px 0;overflow:auto}h2{margin-top:0}
table{width:100%;border-collapse:collapse;font-size:13px}th,td{padding:9px;border-bottom:1px solid #e5ebef;text-align:left;white-space:nowrap}th{background:#edf3f6;position:sticky;top:0;cursor:pointer}
tr:nth-child(even){background:#fafcfd}input{padding:10px;border:1px solid #cbd5df;border-radius:7px;width:min(100%,390px);margin-bottom:12px}
.note{background:#fff4d6;border-left:4px solid #d59d16;padding:12px;margin-top:18px;border-radius:4px}small{color:#5b6b78}
</style></head><body>
<header><h1>Veeam Backup Storage Audit</h1><p>Server: $(Html $env:COMPUTERNAME) &nbsp; | &nbsp; Generated: $(Html ($runStarted.ToString('yyyy-MM-dd HH:mm:ss')))</p></header>
<div class="cards"><div class="card"><strong>$($Rows.Count)</strong><span>Backup objects</span></div><div class="card"><strong>$knownRestorePoints</strong><span>Restore points enumerated (partial if unsupported)</span></div><div class="card"><strong>$([math]::Round($totalReportedGB,2)) GB</strong><span>Reported backup-file size (available objects only)</span></div><div class="card"><strong>$unavailableCount</strong><span>Backups without complete storage totals</span></div><div class="card"><strong>$($Issues.Count)</strong><span>Collection issues</span></div></div>
<div class="note"><b>Measurement warning:</b> ReportedBackupGB is the sum of available Veeam storage metadata (Stats.BackupSize), NOT verified physical allocation on a repository. CumulativeDataGB is not unique source capacity. Ratios are not equivalent to Veeam compression/deduplication ratios. Unavailable totals are excluded, not treated as zero.</div>
<section><h2>Backup details</h2><input id="filter" placeholder="Filter by backup, type, repository, or status" oninput="filterTable()" aria-label="Filter backups">
<table id="backups"><thead><tr><th>Backup</th><th>Type</th><th>Repository (if exposed)</th><th>Restore Points</th><th>Restore Point Status</th><th>Storage Objects</th><th>Reported Backup GB</th><th>Cumulative Data GB</th><th>Data / Backup Ratio</th><th>Storage Status</th></tr></thead><tbody>$tableRows</tbody></table></section>
<section><h2>Collection issues</h2><table><thead><tr><th>Backup</th><th>Stage</th><th>Details</th></tr></thead><tbody>$issueRows</tbody></table></section>
<small>Generated read-only by Get-VeeamBackupStorageAudit.ps1. Results require validation against your Veeam v13 environment.</small>
<script>
function filterTable(){const q=document.getElementById('filter').value.toLowerCase();document.querySelectorAll('#backups tbody tr').forEach(r=>r.style.display=r.textContent.toLowerCase().includes(q)?'':'none');}
document.querySelectorAll('#backups th').forEach((th,i)=>th.addEventListener('click',()=>{const body=document.querySelector('#backups tbody');const rows=Array.from(body.rows);const desc=th.dataset.desc==='1';rows.sort((a,b)=>{const x=a.cells[i].textContent.trim(),y=b.cells[i].textContent.trim();const nx=Number(x),ny=Number(y);return (x!==''&&y!==''&&!Number.isNaN(nx)&&!Number.isNaN(ny)?nx-ny:x.localeCompare(y,undefined,{numeric:true}))*(desc?-1:1)});rows.forEach(r=>body.appendChild(r));th.dataset.desc=desc?'0':'1';}));
</script></body></html>
"@
$htmlPath = Join-Path $runDir 'dashboard.html'
[System.IO.File]::WriteAllText($htmlPath, $reportHtml, [System.Text.UTF8Encoding]::new($false))

Write-Host "`nVeeam backup storage audit complete" -ForegroundColor Green
Write-Host "Backups: $($Rows.Count) | Restore points (enumerated): $knownRestorePoints | Collection issues: $($Issues.Count)"
Write-Host "HTML: $htmlPath"
Write-Host "CSV:  $summaryPath"
$Rows | Sort-Object -Property ReportedBackupGB -Descending | Format-Table BackupName,Repository,RestorePoints,ReportedBackupGB,CumulativeDataGB,DataToBackupRatio,StorageStatus -AutoSize
if ($ShowGrid) {
    if (Get-Command Out-GridView -ErrorAction SilentlyContinue) {
        try { $Rows | Out-GridView -Title 'Veeam Backup Storage Audit' -ErrorAction Stop }
        catch { Write-Warning "Out-GridView unavailable: $($_.Exception.Message)" }
    } else { Write-Warning 'Out-GridView is not installed; console and HTML reports are available.' }
}
# Structured data is also emitted for use in other PowerShell workflows.
$Rows.ToArray()
