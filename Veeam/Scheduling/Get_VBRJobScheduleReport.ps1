<#
.SYNOPSIS
  Collects job and schedule inventory from multiple Veeam Backup & Replication (VBR)
  servers and produces a sortable HTML report plus a CSV data export.

.DESCRIPTION
  Run from an administration workstation that can use PowerShell remoting to each
  VBR server. The Veeam Backup PowerShell module must be installed on each target.
  The script is read-only: it only queries Veeam configuration data.

  For site labels, provide either -VbrServers (site defaults to the server name) or
  -ServerListCsv. The CSV must have columns: VBRServer,Site.

.EXAMPLE
  .\Get-VBRJobScheduleReport.ps1 -VbrServers VBR01,VBR02 -OutputDirectory C:\Reports

.EXAMPLE
  .\Get-VBRJobScheduleReport.ps1 -ServerListCsv C:\Reports\VbrServers.csv `
    -OutputDirectory C:\Reports -Credential (Get-Credential)
#>

[CmdletBinding(DefaultParameterSetName='ServerNames')]
param(
    [Parameter(Mandatory=$true, ParameterSetName='ServerNames')]
    [ValidateNotNullOrEmpty()]
    [string[]]$VbrServers,
    [Parameter(Mandatory=$true, ParameterSetName='ServerList')]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$ServerListCsv,
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory,
    [pscredential]$Credential
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-ColorMap {
    param([string[]]$Values)
    $palette = @('#E8F1FB','#E9F6EE','#FFF3D6','#FCE8E6','#EEE8F8','#E3F4F1','#F9E4EE','#F1F0D8','#E8EDF2','#F4E7D3')
    $map = @{}
    $index = 0
    foreach ($value in ($Values | Where-Object { $_ } | Sort-Object -Unique)) {
        $map[$value] = $palette[$index % $palette.Count]
        $index++
    }
    return $map
}
function ConvertTo-HtmlEncoded {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

if ($PSCmdlet.ParameterSetName -eq 'ServerList') {
    $targets = Import-Csv -LiteralPath $ServerListCsv
    foreach ($target in $targets) {
        if ([string]::IsNullOrWhiteSpace($target.VBRServer)) { throw "Every row in '$ServerListCsv' must contain VBRServer." }
        if ([string]::IsNullOrWhiteSpace($target.Site)) { $target.Site = $target.VBRServer }
    }
} else {
    $targets = foreach ($server in $VbrServers) { [pscustomobject]@{ VBRServer = $server; Site = $server } }
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$csvPath   = Join-Path $OutputDirectory "VBR_Job_Schedules_$timestamp.csv"
$htmlPath  = Join-Path $OutputDirectory "VBR_Job_Schedules_$timestamp.html"
$errorPath = Join-Path $OutputDirectory "VBR_Job_Schedule_Collection_Errors_$timestamp.csv"

# Executes locally on each VBR server through PowerShell remoting.
$remoteCollector = {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    Import-Module Veeam.Backup.PowerShell -ErrorAction Stop

    function Get-LocalTextProperty {
        param([object]$Object, [string[]]$Names)
        if ($null -eq $Object) { return $null }
        foreach ($name in $Names) {
            $property = $Object.PSObject.Properties[$name]
            if ($null -ne $property -and $null -ne $property.Value) {
                $value = $property.Value
                if ($value -is [System.Array]) { return (($value | ForEach-Object { $_.ToString() }) -join ', ') }
                return $value.ToString()
            }
        }
        return $null
    }

    function Get-ScheduleSummary {
        param([object]$Job)
        $schedule = $null; $scheduleSource = $null
        try {
            $schedule = Get-VBRJobScheduleOptions -Job $Job -ErrorAction Stop
            $scheduleSource = 'Get-VBRJobScheduleOptions'
        } catch {
            foreach ($propertyName in @('ScheduleOptions','Schedule','ScheduleSettings')) {
                $property = $Job.PSObject.Properties[$propertyName]
                if ($null -ne $property -and $null -ne $property.Value) {
                    $schedule = $property.Value; $scheduleSource = "Job.$propertyName"; break
                }
            }
        }
        if ($null -eq $schedule) {
            return [pscustomobject]@{ ScheduleEnabled=$null; ScheduleType='Not returned by installed Veeam PowerShell API'; ScheduleSummary='Review this job in the VBR console.'; ScheduleRaw=$null; ScheduleSource=$scheduleSource }
        }

        $enabled = Get-LocalTextProperty $schedule @('Enabled','Enable','IsEnabled')
        $daily = $schedule.PSObject.Properties['DailyOptions']
        $monthly = $schedule.PSObject.Properties['MonthlyOptions']
        $periodic = $schedule.PSObject.Properties['PeriodicallyOptions']
        $after = Get-LocalTextProperty $schedule @('AfterJob','AfterThisJob','Job')
        $type = 'Configured'; $parts = New-Object System.Collections.Generic.List[string]
        if ($null -ne $enabled) { $parts.Add("Enabled=$enabled") }
        if ($null -ne $daily -and $null -ne $daily.Value) {
            $type = 'Daily/Weekly'
            $day = Get-LocalTextProperty $daily.Value @('DayOfWeek','Days','WeekDays'); $time = Get-LocalTextProperty $daily.Value @('Period','Time','At')
            if ($day) { $parts.Add("Days=$day") }; if ($time) { $parts.Add("Time=$time") }
        }
        if ($null -ne $monthly -and $null -ne $monthly.Value) {
            $type = 'Monthly'
            $day = Get-LocalTextProperty $monthly.Value @('DayOfMonth','Days','Day'); $month = Get-LocalTextProperty $monthly.Value @('Months','Month'); $time = Get-LocalTextProperty $monthly.Value @('Period','Time','At')
            if ($day) { $parts.Add("Day=$day") }; if ($month) { $parts.Add("Month=$month") }; if ($time) { $parts.Add("Time=$time") }
        }
        if ($null -ne $periodic -and $null -ne $periodic.Value) {
            $type = 'Periodic'
            $period = Get-LocalTextProperty $periodic.Value @('Period','Every','Interval'); $offset = Get-LocalTextProperty $periodic.Value @('Offset','PeriodicallyOffset')
            if ($period) { $parts.Add("Every=$period") }; if ($offset) { $parts.Add("Offset=$offset") }
        }
        if ($after) { $type = 'After another job'; $parts.Add("After=$after") }
        $raw = $schedule | ConvertTo-Json -Depth 8 -Compress -ErrorAction SilentlyContinue
        [pscustomobject]@{ ScheduleEnabled=$enabled; ScheduleType=$type; ScheduleSummary=($parts -join '; '); ScheduleRaw=$raw; ScheduleSource=$scheduleSource }
    }

    # Get-VBRJob does not include every family, so query each installed cmdlet.
    $jobSources = @(
        @{ Name='Standard/Replication'; Command='Get-VBRJob' },
        @{ Name='Backup Copy'; Command='Get-VBRBackupCopyJob' },
        @{ Name='SureBackup'; Command='Get-VBRSureBackupJob' },
        @{ Name='Tape'; Command='Get-VBRTapeJob' },
        @{ Name='Agent Policy'; Command='Get-VBRComputerBackupJob' },
        @{ Name='Plug-In'; Command='Get-VBRPluginJob' }
    )
    $seen = @{}
    foreach ($source in $jobSources) {
        if ($null -eq (Get-Command -Name $source.Command -ErrorAction SilentlyContinue)) { continue }
        try { $jobs = & $source.Command -ErrorAction Stop } catch { continue }
        foreach ($job in @($jobs)) {
            if ($null -eq $job) { continue }
            $id = Get-LocalTextProperty $job @('Id','UID','JobId'); $name = Get-LocalTextProperty $job @('Name')
            $key = "$($source.Name)|$id|$name"
            if ($seen.ContainsKey($key)) { continue }; $seen[$key] = $true
            $schedule = Get-ScheduleSummary -Job $job
            $jobType = Get-LocalTextProperty $job @('JobType','Type'); if ([string]::IsNullOrWhiteSpace($jobType)) { $jobType = $source.Name }
            [pscustomobject]@{
                JobName=$name; JobType=$jobType; JobFamily=$source.Name; JobId=$id
                JobDescription=(Get-LocalTextProperty $job @('Description'))
                JobEnabled=(Get-LocalTextProperty $job @('IsScheduleEnabled','Enabled','IsEnabled'))
                ScheduleEnabled=$schedule.ScheduleEnabled; ScheduleType=$schedule.ScheduleType
                ScheduleSummary=$schedule.ScheduleSummary; ScheduleSource=$schedule.ScheduleSource; ScheduleRaw=$schedule.ScheduleRaw
            }
        }
    }
}

$allRows = New-Object System.Collections.Generic.List[object]
$collectionErrors = New-Object System.Collections.Generic.List[object]
foreach ($target in $targets) {
    Write-Host "Collecting VBR job inventory from $($target.VBRServer) ..." -ForegroundColor Cyan
    try {
        $invokeParams = @{ ComputerName=$target.VBRServer; ScriptBlock=$remoteCollector; ErrorAction='Stop' }
        if ($PSBoundParameters.ContainsKey('Credential')) { $invokeParams.Credential = $Credential }
        $rows = Invoke-Command @invokeParams
        foreach ($row in @($rows)) {
            $allRows.Add([pscustomobject]@{ Site=$target.Site; VBRServer=$target.VBRServer; JobName=$row.JobName; JobType=$row.JobType; JobFamily=$row.JobFamily; JobId=$row.JobId; JobEnabled=$row.JobEnabled; ScheduleEnabled=$row.ScheduleEnabled; ScheduleType=$row.ScheduleType; ScheduleSummary=$row.ScheduleSummary; JobDescription=$row.JobDescription; ScheduleSource=$row.ScheduleSource; ScheduleRaw=$row.ScheduleRaw })
        }
    } catch {
        $collectionErrors.Add([pscustomobject]@{ VBRServer=$target.VBRServer; Site=$target.Site; Error=$_.Exception.Message })
        Write-Warning "Could not collect from $($target.VBRServer): $($_.Exception.Message)"
    }
}

$reportRows = @($allRows | Sort-Object Site, JobType, JobName)
$reportRows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
if ($collectionErrors.Count -gt 0) { $collectionErrors | Export-Csv -LiteralPath $errorPath -NoTypeInformation -Encoding UTF8 }

$siteColors = New-ColorMap ($reportRows.Site); $typeColors = New-ColorMap ($reportRows.JobType)
$rowsHtml = foreach ($row in $reportRows) {
    $site=ConvertTo-HtmlEncoded $row.Site; $server=ConvertTo-HtmlEncoded $row.VBRServer; $name=ConvertTo-HtmlEncoded $row.JobName; $type=ConvertTo-HtmlEncoded $row.JobType; $family=ConvertTo-HtmlEncoded $row.JobFamily; $enabled=ConvertTo-HtmlEncoded $row.JobEnabled; $scheduleEnabled=ConvertTo-HtmlEncoded $row.ScheduleEnabled; $scheduleType=ConvertTo-HtmlEncoded $row.ScheduleType; $summary=ConvertTo-HtmlEncoded $row.ScheduleSummary; $description=ConvertTo-HtmlEncoded $row.JobDescription; $raw=ConvertTo-HtmlEncoded $row.ScheduleRaw
    "<tr><td style='background:$($siteColors[$row.Site])'>$site</td><td>$server</td><td>$name</td><td style='background:$($typeColors[$row.JobType])'>$type</td><td>$family</td><td>$enabled</td><td>$scheduleEnabled</td><td>$scheduleType</td><td>$summary</td><td>$description</td><td title='$raw'>$(if ($raw) {'Hover for raw schedule data'} else {''})</td></tr>"
}
$errorHtml = if ($collectionErrors.Count -gt 0) {
    $items = foreach ($error in $collectionErrors) { "<li><strong>$(ConvertTo-HtmlEncoded $error.VBRServer)</strong> ($(ConvertTo-HtmlEncoded $error.Site)): $(ConvertTo-HtmlEncoded $error.Error)</li>" }
    "<section class='warning'><strong>Collection failures:</strong><ul>$($items -join "`n")</ul>See the accompanying errors CSV for the same details.</section>"
} else { '' }

$html = @"
<!doctype html><html lang="en"><head><meta charset="utf-8"><title>VBR Job Schedule Inventory</title><style>
body{font-family:Segoe UI,Arial,sans-serif;margin:24px;color:#1f2937}h1{margin-bottom:4px}.meta{color:#4b5563;margin-top:0}.controls{display:flex;gap:12px;flex-wrap:wrap;margin:20px 0}input,select{padding:7px;border:1px solid #9ca3af;border-radius:4px;min-width:220px}table{border-collapse:collapse;width:100%;font-size:13px}th{background:#16365c;color:white;cursor:pointer;position:sticky;top:0;text-align:left}th,td{border:1px solid #cbd5e1;padding:7px 8px;vertical-align:top}tbody tr:nth-child(even) td:not([style]){background:#f8fafc}.legend{font-size:12px;color:#4b5563}.warning{margin:14px 0;padding:12px;border-left:5px solid #b45309;background:#fffbeb}.count{font-weight:600}
</style></head><body><h1>Veeam Backup &amp; Replication Job Schedule Inventory</h1><p class="meta">Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K') | $($reportRows.Count) job records collected from $($targets.Count) requested VBR server(s).</p>$errorHtml
<div class="controls"><input id="search" placeholder="Search any column" oninput="filterRows()"><select id="siteFilter" onchange="filterRows()"><option value="">All sites</option></select><select id="typeFilter" onchange="filterRows()"><option value="">All job types</option></select><span class="count" id="count"></span></div><p class="legend">Click a column heading to sort. Site cells and job-type cells are color-coded independently. Hover over “raw schedule data” for the schedule object returned by the installed Veeam PowerShell API.</p>
<table id="report"><thead><tr><th>Site</th><th>VBR Server</th><th>Job Name</th><th>Job Type</th><th>Job Family</th><th>Job Enabled</th><th>Schedule Enabled</th><th>Schedule Type</th><th>Schedule Summary</th><th>Description</th><th>API Detail</th></tr></thead><tbody>$($rowsHtml -join "`n")</tbody></table>
<script>
const table=document.getElementById('report');function addOptions(id,col){const s=document.getElementById(id),v=[...new Set([...table.tBodies[0].rows].map(r=>r.cells[col].innerText).filter(Boolean))].sort();v.forEach(x=>{const o=document.createElement('option');o.value=x;o.textContent=x;s.appendChild(o)})}function filterRows(){const text=document.getElementById('search').value.toLowerCase(),site=document.getElementById('siteFilter').value,type=document.getElementById('typeFilter').value;let shown=0;[...table.tBodies[0].rows].forEach(r=>{const show=r.innerText.toLowerCase().includes(text)&&(!site||r.cells[0].innerText===site)&&(!type||r.cells[3].innerText===type);r.style.display=show?'':'none';if(show)shown++});document.getElementById('count').textContent=shown+' displayed'}[...table.tHead.rows[0].cells].forEach((th,n)=>th.addEventListener('click',()=>{const rows=[...table.tBodies[0].rows],asc=th.dataset.order!=='asc';rows.sort((a,b)=>a.cells[n].innerText.localeCompare(b.cells[n].innerText,undefined,{numeric:true})*(asc?1:-1));rows.forEach(r=>table.tBodies[0].appendChild(r));[...table.tHead.rows[0].cells].forEach(h=>delete h.dataset.order);th.dataset.order=asc?'asc':'desc'}));addOptions('siteFilter',0);addOptions('typeFilter',3);filterRows();
</script></body></html>
"@
Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8
Write-Host "Created HTML: $htmlPath" -ForegroundColor Green; Write-Host "Created CSV : $csvPath" -ForegroundColor Green
if ($collectionErrors.Count -gt 0) { Write-Host "Created errors CSV: $errorPath" -ForegroundColor Yellow }
