# Load Veeam Module
Import-Module Veeam.Backup.PowerShell -ErrorAction SilentlyContinue

Write-Host "Analyzing individual VM storage consumption... This may take a moment." -ForegroundColor Cyan

$VMAuditReport = @()

# Gather all protected backup objects (VMs, physical servers, etc.)
$AllProtectedObjects = Get-VBRBackup | Get-VBRBackupObject

# Group by the specific Object Name to handle VMs that span across multiple jobs/chains
$GroupedObjects = $AllProtectedObjects | Group-Object Name

foreach ($Group in $GroupedObjects) {
    $VMName = $Group.Name
    $TotalDiskSizeByte = 0
    $TotalDataSizeByte = 0
    $RestorePointCount = 0
    $AssociatedJobs = @()

    foreach ($OlmObj in $Group.Group) {
        # Track which job this instance is from
        $BackupJob = Get-VBRBackup | Where-Object { $_.Id -eq $OlmObj.BackupId }
        if ($BackupJob) { $AssociatedJobs += $BackupJob.Name }

        # Get all distinct historical restore points for this specific VM object
        $RPs = Get-VBRRestorePoint -BackupObject $OlmObj
        $RestorePointCount += $RPs.Count

        foreach ($RP in $RPs) {
            # Extract statistics for this specific point in time
            $Stats = $RP.Stats
            $TotalDiskSizeByte += $Stats.BackupSize # Exact repository space for this VM point
            $TotalDataSizeByte += $Stats.DataSize   # Original raw virtual disk size
        }
    }

    # Format numbers into readable GB units
    $DiskSizeGB = [Math]::Round(($TotalDiskSizeByte / 1GB), 2)
    $DataSizeGB = [Math]::Round(($TotalDataSizeByte / 1GB), 2)
    
    $ReductionRatio = "0:1"
    if ($DiskSizeGB -gt 0 -and $DataSizeGB -gt 0) {
        $Ratio = [Math]::Round(($DataSizeGB / $DiskSizeGB), 1)
        $ReductionRatio = "$Ratio:1"
    }

    # Consolidate job names into a single clean string
    $JobNamesString = ($AssociatedJobs | Select-Object -Unique) -join ", "

    # Build the structured custom object
    $VMAuditReport += [PSCustomObject]@{
        "VM / Object Name"    = $VMName
        "Target Backup Jobs"  = $JobNamesString
        "Total Restore Points"= $RestorePointCount
        "Raw Capacity (GB)"   = $DataSizeGB
        "Space On Disk (GB)"  = $DiskSizeGB
        "Dedupe/Comp Ratio"   = $ReductionRatio
    }
}

# Display in an interactive, filterable pop-up window
$VMAuditReport | Out-GridView -Title "Veeam Per-VM Storage Footprint Audit"

# Fallback print to the regular console window
$VMAuditReport | Format-Table -AutoSize
