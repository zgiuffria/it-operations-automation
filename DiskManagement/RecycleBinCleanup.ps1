# --- CONFIGURATION ---
# Script: RecycleBinInfo.ps1
# Description: Gathers Recycle Bin sizes per user, provides an interactive menu to safely clear specific or all bins.
# Usage: Triggered automatically via RecycleBinInfo.bat.  You must click yes on the UAC prompt to elevate privilages. 
# ---------------------

$recycleBinPath = "C:\`$Recycle.Bin"

if (-not (Test-Path -LiteralPath $recycleBinPath)) {
    Write-Error "Recycle Bin path not found or script isn't running with Administrator privileges."
    exit 1
}

Write-Host "Scanning user recycle bins (this may take a few moments)...`n" -ForegroundColor Cyan

# Gather the data
$results = Get-ChildItem -LiteralPath $recycleBinPath -Directory -Force | ForEach-Object {
    $userSID = $_.Name
    
    try {
        $user = (New-Object System.Security.Principal.SecurityIdentifier($userSID)).Translate([System.Security.Principal.NTAccount]).Value
    } catch {
        $user = "Unknown User ($userSID)"
    }
    
    $files = Get-ChildItem -LiteralPath $_.FullName -Recurse -Force -File -ErrorAction SilentlyContinue
    $sizeBytes = ($files | Measure-Object -Property Length -Sum).Sum

    if ($sizeBytes -ne $null) {
        $sizeMB = [math]::Round($sizeBytes / 1MB, 2)
        $sizeGB = [math]::Round($sizeBytes / 1GB, 2)
    } else {
        $sizeMB = 0
        $sizeGB = 0
    }
    
    [PSCustomObject]@{
        "User"       = $user
        "Size_MB"    = $sizeMB
        "Size_GB"    = $sizeGB
        "FolderPath" = $_.FullName
    }
}

# Display results in the matrix green style
$results | Format-Table @{Expression="User";Width=40}, @{Expression="Size_MB";Width=12}, @{Expression="Size_GB";Width=12} | Out-String -Stream | ForEach-Object {
    Write-Host $_ -ForegroundColor Green
}

Write-Host "`n--------------------------------------------------" -ForegroundColor Green

# Prompt 1: Ask to clean up
$cleanChoice = Read-Host "Would you like to clean up any of the recycling bins? (y/n)"
if ($cleanChoice.ToLower() -ne 'y') {
    Write-Host "Exiting without making changes." -ForegroundColor Yellow
    exit 0
}

# Prompt 2: Display numbered list of users
Write-Host "`nSelect an option below:" -ForegroundColor Green
Write-Host " [0] Remove the data from ALL recycling bins" -ForegroundColor Green

$menuIndex = 1
$userMenu = @{}

foreach ($row in $results) {
    # Skip displaying items that are already 0 MB to keep the menu clean
    if ($row.Size_MB -gt 0) {
        Write-Host " [$menuIndex] $($row.User) ($($row.Size_MB) MB)" -ForegroundColor Green
        $userMenu[$menuIndex] = $row
        $menuIndex++
    }
}

if ($userMenu.Count -eq 0) {
    Write-Host "`nAll active user recycle bins are already empty!" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
$selection = Read-Host "Enter the number next to your choice"

# Validate selection input
if ($selection -ne '0' -and -not $userMenu.ContainsKey([int]$selection)) {
    Write-Host "Invalid selection. Exiting script." -ForegroundColor Red
    exit 1
}

# Setup target details for warning logic
if ($selection -eq '0') {
    $targetName = "ALL user recycle bins"
    $pathsToDelete = $results.FolderPath
} else {
    $selectedUser = $userMenu[[int]$selection]
    $targetName = "the recycle bin for user: $($selectedUser.User)"
    $pathsToDelete = @($selectedUser.FolderPath)
}

# --- WARNING AND CONFIRMATION BLOCK ---
Write-Host "`n==================================================" -ForegroundColor Yellow
Write-Host "                     WARNING                      " -ForegroundColor Yellow
Write-Host "==================================================" -ForegroundColor Yellow
Write-Host "You are about to PERMANENTLY DESTRUCT data from:" -ForegroundColor Yellow
Write-Host "-> $targetName" -ForegroundColor Cyan
Write-Host "This operation CANNOT be undone. Files will be deleted bypassing the trash." -ForegroundColor Yellow
Write-Host "==================================================" -ForegroundColor Yellow

$confirm = Read-Host "Are you absolutely sure you want to proceed? (yes/no)"

if ($confirm.ToLower() -eq 'yes') {
    Write-Host "`nExecuting file removal..." -ForegroundColor Cyan
    foreach ($folder in $pathsToDelete) {
        # Deletes contents inside the specific SID directory without removing the system structure root folder itself
        Get-ChildItem -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Cleanup completed successfully!" -ForegroundColor Green
} else {
    Write-Host "`nAction canceled by user. No files were deleted." -ForegroundColor Yellow
}
