<#
.SYNOPSIS
    Read-only Veeam Backup & Replication v13 operations dashboard.
.DESCRIPTION
    Collects backup sessions in a time window, latest result per discovered job,
    and best-effort repository capacity information. Creates standalone HTML and CSV reports.
    Run on a Windows VBR server or a management host with a working Veeam PowerShell connection.
    Some job types and repository backends expose different properties; unavailable metrics are labeled.
.PARAMETER DaysToCheck
    Number of days of session history to inspect (default 1).
.PARAMETER ReportDirectory
    Output directory for timestamped reports.
.PARAMETER WarningFreePercent
    Free-capacity warning threshold (default 20).
.PARAMETER CriticalFreePercent
    Free-capacity critical threshold (default 10).
.EXAMPLE
    .\Get-VeeamOperationsDashboard.ps1 -DaysToCheck 7 -ReportDirectory C:\Reports
.NOTES
    No external JavaScript dependencies. Read-only Veeam commands. Windows PowerShell 5.1 supported.
#>
[CmdletBinding()]
param(
    [ValidateRange(1,365)][int]$DaysToCheck = 1,
    [ValidateNotNullOrEmpty()][string]$ReportDirectory = 'C:\Reports',
    [ValidateRange(1,100)][double]$WarningFreePercent = 20,
    [ValidateRange(0,99)][double]$CriticalFreePercent = 10
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($CriticalFreePercent -ge $WarningFreePercent) { throw 'CriticalFreePercent must be less than WarningFreePercent.' }

function Get-SafeProperty {
    param([AllowNull()][object]$Object,[string]$Name,[AllowNull()][object]$Default = $null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}
function Html([AllowNull()][object]$Value) {
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}
function Get-Bytes {
    param([AllowNull()][object]$Object,[string[]]$Names)
    foreach ($name in $Names) {
        $v = Get-SafeProperty $Object $name
        if ($null -ne $v) {
            try {
                $n = [double]$v
                if (-not [double]::IsNaN($n) -and $n -ge 0) { return $n }
            } catch { }
        }
    }
    return $null
}
function Write-CsvFile {
    param([object[]]$Rows,[string]$Path,[string[]]$Columns)
    if ($Rows.Count -gt 0) {
        $Rows | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
    } else {
        # Preserve headers even when the dataset is empty.
        ('"' + ($Columns -join '","') + '"') | Set-Content -LiteralPath $Path -Encoding UTF8
    }
}
function Format-Date([AllowNull()][object]$Date) {
    if ($null -eq $Date) { return '' }
    try { return ([datetime]$Date).ToString('yyyy-MM-dd HH:mm:ss') } catch { return [string]$Date }
}
function Get-CssStatus([string]$Result) {
    switch ($Result.ToLowerInvariant()) {
        'success' { return 'ok' }
        'warning' { return 'warn' }
        'failed' { return 'bad' }
        default { return 'unknown' }
    }
}
function Get-RepoMetrics {
    param([object]$Repo)
    $sources = @($Repo, (Get-SafeProperty $Repo 'Info'), (Get-SafeProperty $Repo 'Container'))
    foreach ($src in $sources) {
        if ($null -eq $src) { continue }
        $capacity = Get-Bytes $src @('Capacity','TotalSpace','TotalCapacity')
        $free = Get-Bytes $src @('FreeSpace','FreeCapacity','AvailableSpace')
        if ($null -ne $capacity -and $capacity -gt 0 -and $null -ne $free -and $free -le $capacity) {
            return [pscustomobject]@{ Capacity = $capacity; Free = $free; Source = 'Repository object' }
        }
    }
    # Capacity may be absent or stale for certain repository types. Never infer it.
    return $null
}

$issues = New-Object 'System.Collections.Generic.List[object]'
$sessions = New-Object 'System.Collections.Generic.List[object]'
$repositories = New-Object 'System.Collections.Generic.List[object]'
$latestJobs = New-Object 'System.Collections.Generic.List[object]'
$cutoff = (Get-Date).AddDays(-$DaysToCheck)
$generated = Get-Date
$serverName = $env:COMPUTERNAME

try { Import-Module Veeam.Backup.PowerShell -ErrorAction Stop }
catch { throw "Veeam.Backup.PowerShell module could not be loaded: $($_.Exception.Message)" }
foreach ($command in @('Get-VBRBackupSession','Get-VBRJob','Get-VBRBackupRepository')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Required Veeam command unavailable: $command" }
}

Write-Host "Collecting Veeam session history since $(Format-Date $cutoff)..." -ForegroundColor Cyan
try {
    $rawSessions = @(Get-VBRBackupSession -ErrorAction Stop)
    foreach ($s in $rawSessions) {
        $created = Get-SafeProperty $s 'CreationTime'
        if ($null -eq $created) { continue }
        try { if ([datetime]$created -lt $cutoff) { continue } } catch { continue }
        $result = [string](Get-SafeProperty $s 'Result' 'Unknown')
        $state = [string](Get-SafeProperty $s 'State' 'Unknown')
        $name = [string](Get-SafeProperty $s 'JobName' (Get-SafeProperty $s 'Name' 'Unknown'))
        $end = Get-SafeProperty $s 'EndTime'
        $duration = ''
        if ($null -ne $end) {
            try {
                $elapsed = ([datetime]$end) - ([datetime]$created)
                if ($elapsed.TotalSeconds -ge 0) { $duration = [math]::Round($elapsed.TotalMinutes,1) }
            } catch { }
        }
        $sessions.Add([pscustomobject]@{
            JobName=$name; StartTime=Format-Date $created; EndTime=Format-Date $end;
            DurationMinutes=$duration; Result=$result; State=$state;
            SessionId=[string](Get-SafeProperty $s 'Id' '')
        })
    }
} catch {
    $issues.Add([pscustomobject]@{ Area='Sessions'; Item='Get-VBRBackupSession'; Error=$_.Exception.Message })
}

Write-Host 'Collecting job inventory...' -ForegroundColor Cyan
try {
    $jobs = @(Get-VBRJob -ErrorAction Stop)
    foreach ($job in $jobs) {
        $jobName = [string](Get-SafeProperty $job 'Name' 'Unknown')
        $jobType = [string](Get-SafeProperty $job 'JobType' 'Unknown')
        $matching = @($sessions | Where-Object { $_.JobName -eq $jobName } | Sort-Object StartTime -Descending)
        $last = if ($matching.Count -gt 0) { $matching[0] } else { $null }
        $latestJobs.Add([pscustomobject]@{
            JobName=$jobName; JobType=$jobType;
            LatestRunInWindow=if ($null -ne $last) { $last.StartTime } else { '' };
            LatestResultInWindow=if ($null -ne $last) { $last.Result } else { 'No runs in window' };
            RunsInWindow=$matching.Count
        })
    }
} catch {
    $issues.Add([pscustomobject]@{ Area='Jobs'; Item='Get-VBRJob'; Error=$_.Exception.Message })
}

Write-Host 'Collecting repository inventory...' -ForegroundColor Cyan
try {
    $rawRepos = @(Get-VBRBackupRepository -ErrorAction Stop)
    foreach ($repo in $rawRepos) {
        $name = [string](Get-SafeProperty $repo 'Name' 'Unknown')
        $type = [string](Get-SafeProperty $repo 'Type' 'Unknown')
        $path = [string](Get-SafeProperty $repo 'Path' '')
        $metrics = Get-RepoMetrics $repo
        if ($null -eq $metrics) {
            $repositories.Add([pscustomobject]@{
                Name=$name; Type=$type; Path=$path; CapacityGB=''; UsedGB=''; FreeGB=''; FreePercent=''; Status='Unavailable'
            })
            continue
        }
        $freePct = [math]::Round(100 * $metrics.Free / $metrics.Capacity,1)
        $status = if ($freePct -le $CriticalFreePercent) { 'Critical' } elseif ($freePct -le $WarningFreePercent) { 'Warning' } else { 'OK' }
        $repositories.Add([pscustomobject]@{
            Name=$name; Type=$type; Path=$path;
            CapacityGB=[math]::Round($metrics.Capacity / 1GB,2);
            UsedGB=[math]::Round(($metrics.Capacity - $metrics.Free) / 1GB,2);
            FreeGB=[math]::Round($metrics.Free / 1GB,2);
            FreePercent=$freePct; Status=$status
        })
    }
} catch {
    $issues.Add([pscustomobject]@{ Area='Repositories'; Item='Get-VBRBackupRepository'; Error=$_.Exception.Message })
}

New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
$folder = Join-Path $ReportDirectory ('VeeamDashboard-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$sessionRows = @($sessions | Sort-Object StartTime -Descending)
$repoRows = @($repositories | Sort-Object Name)
$jobRows = @($latestJobs | Sort-Object JobName)
$issueRows = @($issues)
Write-CsvFile $sessionRows (Join-Path $folder 'sessions.csv') @('JobName','StartTime','EndTime','DurationMinutes','Result','State','SessionId')
Write-CsvFile $repoRows (Join-Path $folder 'repositories.csv') @('Name','Type','Path','CapacityGB','UsedGB','FreeGB','FreePercent','Status')
Write-CsvFile $jobRows (Join-Path $folder 'jobs.csv') @('JobName','JobType','LatestRunInWindow','LatestResultInWindow','RunsInWindow')
Write-CsvFile $issueRows (Join-Path $folder 'collection-errors.csv') @('Area','Item','Error')

$success = @($sessionRows | Where-Object { $_.Result -eq 'Success' }).Count
$warning = @($sessionRows | Where-Object { $_.Result -eq 'Warning' }).Count
$failed = @($sessionRows | Where-Object { $_.Result -eq 'Failed' }).Count
$other = $sessionRows.Count - $success - $warning - $failed
$maxCount = [math]::Max(1,[math]::Max($success,[math]::Max($warning,[math]::Max($failed,$other))))
$chartBars = @(
    @{ Label='Success'; Value=$success; Class='ok' },
    @{ Label='Warning'; Value=$warning; Class='warn' },
    @{ Label='Failed'; Value=$failed; Class='bad' },
    @{ Label='Other / unfinished'; Value=$other; Class='unknown' }
) | ForEach-Object {
    $width = [math]::Round(100 * $_.Value / $maxCount,1)
    '<div class="barline"><span>'+(Html $_.Label)+'</span><div class="track"><div class="fill '+$_.Class+'" style="width:'+$width+'%"></div></div><strong>'+$_.Value+'</strong></div>'
}
$sessionHtml = foreach ($row in $sessionRows) {
    '<tr><td>'+(Html $row.JobName)+'</td><td>'+(Html $row.StartTime)+'</td><td>'+(Html $row.DurationMinutes)+'</td><td><span class="pill '+(Get-CssStatus $row.Result)+'">'+(Html $row.Result)+'</span></td><td>'+(Html $row.State)+'</td></tr>'
}
$jobHtml = foreach ($row in $jobRows) {
    '<tr><td>'+(Html $row.JobName)+'</td><td>'+(Html $row.JobType)+'</td><td>'+(Html $row.LatestRunInWindow)+'</td><td><span class="pill '+(Get-CssStatus $row.LatestResultInWindow)+'">'+(Html $row.LatestResultInWindow)+'</span></td><td>'+$row.RunsInWindow+'</td></tr>'
}
$repoHtml = foreach ($row in $repoRows) {
    $pct = if ($row.FreePercent -eq '') { 'Unknown' } else { "$(Html $row.FreePercent)%" }
    $capacity = if ($row.CapacityGB -eq '') { 'Unknown' } else { "$(Html $row.CapacityGB) GB" }
    $free = if ($row.FreeGB -eq '') { 'Unknown' } else { "$(Html $row.FreeGB) GB" }
    $css = switch ($row.Status) { 'OK' {'ok'} 'Warning' {'warn'} 'Critical' {'bad'} default {'unknown'} }
    '<tr><td>'+(Html $row.Name)+'</td><td>'+(Html $row.Type)+'</td><td>'+(Html $row.Path)+'</td><td>'+$capacity+'</td><td>'+$free+'</td><td>'+$pct+'</td><td><span class="pill '+$css+'">'+(Html $row.Status)+'</span></td></tr>'
}
$issueHtml = foreach ($row in $issueRows) {
    '<tr><td>'+(Html $row.Area)+'</td><td>'+(Html $row.Item)+'</td><td>'+(Html $row.Error)+'</td></tr>'
}
if (-not $sessionHtml) { $sessionHtml = '<tr><td colspan="5">No sessions returned for this period (or collection failed).</td></tr>' }
if (-not $jobHtml) { $jobHtml = '<tr><td colspan="5">No jobs returned.</td></tr>' }
if (-not $repoHtml) { $repoHtml = '<tr><td colspan="7">No repositories returned.</td></tr>' }
if (-not $issueHtml) { $issueHtml = '<tr><td colspan="3">No collection errors reported.</td></tr>' }
$reportStatus = if ($issueRows.Count -gt 0) { 'PARTIAL DATA - review collection errors' } else { 'Collection completed' }

$htmlText = @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Veeam Operations Dashboard</title>
<style>
:root{color-scheme:light}*{box-sizing:border-box}body{margin:0;background:#f3f6f8;color:#17232f;font:14px/1.5 'Segoe UI',Arial,sans-serif}header{background:#123b31;color:white;padding:26px max(24px,calc((100vw - 1200px)/2))}header h1{margin:0 0 4px;font-size:26px}header p{margin:0;color:#c9e1d9}.wrap{max-width:1200px;margin:24px auto;padding:0 18px}.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:14px}.card,.panel{background:white;border:1px solid #e3e8ed;border-radius:12px;padding:18px;box-shadow:0 2px 8px #182e3810}.card .label{font-size:12px;color:#5e6e7d;text-transform:uppercase;letter-spacing:.05em}.card .number{font-size:30px;font-weight:700;margin-top:4px}.panel{margin-top:18px;overflow:auto}h2{font-size:18px;margin:0 0 14px}.barline{display:grid;grid-template-columns:135px 1fr 44px;align-items:center;gap:12px;margin:12px 0}.track{height:16px;background:#e9eef2;border-radius:8px;overflow:hidden}.fill{height:100%;border-radius:8px}.fill.ok{background:#21885e}.fill.warn{background:#d39b20}.fill.bad{background:#c94545}.fill.unknown{background:#8a99a7}table{width:100%;border-collapse:collapse;white-space:nowrap}th,td{padding:10px 12px;text-align:left;border-bottom:1px solid #e8edf1}th{background:#f7f9fa;color:#475967;position:sticky;top:0}tr:hover td{background:#f9fbfc}.pill{display:inline-block;padding:2px 9px;border-radius:99px;font-weight:600}.pill.ok{background:#e0f3e9;color:#136a47}.pill.warn{background:#fff0ca;color:#815700}.pill.bad{background:#ffe4e4;color:#a42323}.pill.unknown{background:#edf0f3;color:#556574}.note{color:#62727f;font-size:12px;margin-top:12px}input{padding:9px 12px;border:1px solid #cdd8df;border-radius:7px;width:100%;max-width:360px;margin-bottom:12px}@media(max-width:600px){.barline{grid-template-columns:90px 1fr 30px}header{padding:20px}}
</style></head><body>
<header><h1>Veeam Operations Dashboard</h1><p>$(Html $serverName) | Last $DaysToCheck day(s) | Generated $(Html (Format-Date $generated)) | $(Html $reportStatus)</p></header>
<main class="wrap">
<section class="cards"><div class="card"><div class="label">Successful runs</div><div class="number">$success</div></div><div class="card"><div class="label">Warnings</div><div class="number">$warning</div></div><div class="card"><div class="label">Failed runs</div><div class="number">$failed</div></div><div class="card"><div class="label">Other / unfinished</div><div class="number">$other</div></div><div class="card"><div class="label">Repositories</div><div class="number">$($repoRows.Count)</div></div><div class="card"><div class="label">Collection errors</div><div class="number">$($issueRows.Count)</div></div></section>
<section class="panel"><h2>Backup execution results</h2>$($chartBars -join "`n")<p class="note">Counts reflect all returned backup sessions in the reporting window, not just each job's latest execution. Other / unfinished includes unclassified results.</p></section>
<section class="panel"><h2>Session history</h2><input aria-label="Filter sessions" placeholder="Filter sessions..." oninput="filterRows(this,'sessionTable')"><table id="sessionTable"><thead><tr><th>Job</th><th>Started</th><th>Duration (min)</th><th>Result</th><th>State</th></tr></thead><tbody>$($sessionHtml -join "`n")</tbody></table></section>
<section class="panel"><h2>Latest execution per job (within window)</h2><table><thead><tr><th>Job</th><th>Type</th><th>Latest run</th><th>Latest result</th><th>Runs</th></tr></thead><tbody>$($jobHtml -join "`n")</tbody></table></section>
<section class="panel"><h2>Repository capacity</h2><table><thead><tr><th>Repository</th><th>Type</th><th>Path</th><th>Capacity</th><th>Free</th><th>Free %</th><th>Status</th></tr></thead><tbody>$($repoHtml -join "`n")</tbody></table><p class="note">Capacity is best-effort from returned repository properties and may be unavailable or stale for some types. Verify in Veeam before taking action. Scale-out and object storage may require separate queries.</p></section>
<section class="panel"><h2>Collection errors</h2><table><thead><tr><th>Area</th><th>Command</th><th>Error</th></tr></thead><tbody>$($issueHtml -join "`n")</tbody></table></section>
<p class="note">Read-only report. Report status reflects collection success, not backup infrastructure health. All chart assets are embedded; no internet required.</p>
</main><script>function filterRows(input,id){var q=input.value.toLowerCase();document.querySelectorAll('#'+id+' tbody tr').forEach(function(row){row.style.display=row.textContent.toLowerCase().indexOf(q)>=0?'':'none'})}</script></body></html>
"@
$htmlPath = Join-Path $folder 'dashboard.html'
[System.IO.File]::WriteAllText($htmlPath,$htmlText,(New-Object System.Text.UTF8Encoding($false)))
Write-Host "Dashboard: $htmlPath" -ForegroundColor Green
Write-Host "CSV reports: $folder" -ForegroundColor Green
if ($issueRows.Count -gt 0) { Write-Warning "$($issueRows.Count) collection error(s) occurred. Review collection-errors.csv." }
[pscustomobject]@{ Dashboard=$htmlPath; ReportDirectory=$folder; Sessions=$sessionRows.Count; Repositories=$repoRows.Count; CollectionErrors=$issueRows.Count }
