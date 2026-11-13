# --- CONFIGURATION ---
# No manual configuration required. Run directly on the Veeam Server.
# ---------------------

<#
.SYNOPSIS
    Veeam Job-Level Backup Size and Storage Footprint Auditor.
.DESCRIPTION
    Loops through active backup chains to calculate actual space used on the backup repositories vs. original raw source sizes, providing data reduction metrics per job.
.NOTES
    - How to use: Run the script directly to see an interactive pop-up window of your backup job sizes.
    - Requirements: Run from an elevated PowerShell console on your target Veeam Backup & Replication server.
    - Output: Launches an interactive Out-GridView dashboard and falls back to a formatted console table.
#>

# Load Veeam Module
Import-Module Veeam.Backup.PowerShell -ErrorAction SilentlyContinue

Write-Host "Gathering Veeam Backup Storage Footprints... Please wait.`n" -ForegroundColor Cyan

# Fetch all active backup chains tracked by the VBR database
$Backups = Get-VBRBackup
$AuditReport = @()

foreach ($Backup in $Backups) {
    # Get all individual restore point storage files associated with this job
    $Storages = $Backup.GetStorages()
    
    $TotalDiskSizeByte = 0
    $TotalDataSizeByte = 0
    
    foreach ($Storage in $Storages) {
        # Extract stats from the metadata properties
        $Stats = $Storage.Stats
        $TotalDiskSizeByte += $Stats.BackupSize  # Actual space used on the backup repository
        $TotalDataSizeByte += $Stats.DataSize    # Original, uncompressed raw VM data size
    }
    
    # Calculate reduction and convert to GB
    $DiskSizeGB = [Math]::Round(($TotalDiskSizeByte / 1GB), 2)
    $DataSizeGB = [Math]::Round(($TotalDataSizeByte / 1GB), 2)
    
    $ReductionRatio = "0:1"
    if ($DiskSizeGB -gt 0 -and $DataSizeGB -gt 0) {
        $Ratio = [Math]::Round(($DataSizeGB / $DiskSizeGB), 1)
        $ReductionRatio = "$Ratio:1"
    }

    # Build an object for structured auditing output
    $AuditReport += [PSCustomObject]@{
        "Job / Backup Name" = $Backup.Name
        "Repository"        = $Backup.RepositoryName
        "Restore Points"    = $Storages.Count
        "Raw Data Size(GB)" = $DataSizeGB
        "Size On Disk(GB)"  = $DiskSizeGB
        "Reduction Ratio"   = $ReductionRatio
    }
}

# Output to an interactive, sortable grid view
$AuditReport | Out-GridView -Title "Veeam Backup Size Audit Log"

# Fallback: Print cleanly to the standard console table if Out-GridView is skipped
$AuditReport | Format-Table -AutoSize
