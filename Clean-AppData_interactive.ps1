<#
.SYNOPSIS
    Interactive scanner for orphaned AppData folders with selective deletion.

.DESCRIPTION
    Scans AppData directories for potentially orphaned folders and provides an interactive menu
    to review and selectively delete them. Includes enhanced safety features and detailed logging.

.PARAMETER MinSizeMB
    The minimum size in megabytes a folder must be to be considered. Defaults to 1 MB.

.PARAMETER AdditionalWhitelist
    Additional folder names to add to the safety whitelist (case-insensitive).

.PARAMETER AutoDelete
    Skips interactive menu and deletes all orphaned folders (DANGEROUS - use with caution).

.EXAMPLE
    .\Clean-AppData.ps1
    Runs in interactive mode - scans, shows results, lets you select what to delete.

.EXAMPLE
    .\Clean-AppData.ps1 -MinSizeMB 50
    Only shows folders larger than 50 MB for consideration.

.EXAMPLE
    .\Clean-AppData.ps1 -AdditionalWhitelist @('notebooklm-mcp', 'my-dev-tool')
    Protects specific folders from being flagged as orphans.
#>
[CmdletBinding()]
param(
    [Parameter(HelpMessage = 'Minimum folder size in MB to report as an orphan.')]
    [double]$MinSizeMB = 1,
    
    [Parameter(HelpMessage = 'Additional folder names to whitelist.')]
    [string[]]$AdditionalWhitelist = @(),
    
    [Parameter(HelpMessage = 'Skip interactive menu and delete all (DANGEROUS).')]
    [switch]$AutoDelete
)

# --- SAFETY: Comprehensive whitelist of folders to NEVER delete ---
Write-Host "Initializing safety whitelist..." -ForegroundColor Cyan
$Whitelist = @(
    # Microsoft & Windows
    'Microsoft', 'Microsoft Edge', 'Packages', 'Windows', 'WindowsApps', 'Programs',
    'MicrosoftEdge', 'Windows Defender', 'WindowsPowerShell', 'OneDrive', 'Comms',
    
    # Hardware Manufacturers
    'Google', 'NVIDIA', 'NVIDIA Corporation', 'Intel', 'AMD', 'Realtek',
    'Dell', 'HP', 'Lenovo', 'ASUS', 'Acer', 'Logitech', 'Corsair', 'Razer',
    
    # Common Software Publishers
    'Mozilla', 'Adobe', 'Apple', 'Oracle', 'Java', 'Steam', 'Epic', 'EpicGamesLauncher',
    'Discord', 'Spotify', 'Slack', 'Zoom', 'TeamViewer', 'VLC',
    
    # Developer Tools (CRITICAL - IDEs and core tools only)
    'JetBrains', 'Visual Studio', 'Code', 'git', 'GitHub Desktop',
    
    # System & Common
    'Common Files', 'Temp', 'Downloaded Installations', 'CrashDumps',
    'D3DSCache', 'FontCache', 'IconCache', 'Microsoft_Corporation'
) + $AdditionalWhitelist

# Convert whitelist to lowercase for case-insensitive comparison
$WhitelistLower = $Whitelist | ForEach-Object { $_.ToLower() }

Write-Host "Protected folders: $($Whitelist.Count)" -ForegroundColor Green
Write-Host ""

# --- Define paths to scan ---
$AppDataPaths = @(
    "$env:USERPROFILE\AppData\Local",
    "$env:USERPROFILE\AppData\Roaming"
)

# --- Initialize logging ---
$logTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
# Use USERPROFILE instead of Desktop to avoid path issues
$LogPath = "$env:USERPROFILE\AppDataCleanup_$logTimestamp.log"
$detailedLog = @()
$detailedLog += "AppData Cleanup Scan - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$detailedLog += "=" * 80
$detailedLog += ""

# --- Capture initial free space ---
$initialDrive = Get-PSDrive C
$initialFreeSpaceGB = [math]::Round($initialDrive.Free / 1GB, 2)

# --- Get installed program names from multiple sources ---
Write-Host "Gathering list of installed applications..." -ForegroundColor Cyan
$InstalledApps = @()

# Registry-based applications
$InstalledApps += (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, `
    HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*, `
    HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* `
    -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty DisplayName -ErrorAction SilentlyContinue)

# Windows Store / UWP apps
try {
    $InstalledApps += (Get-AppxPackage -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
} catch {
    Write-Host "Could not retrieve Windows Store apps" -ForegroundColor Yellow
}

# Clean up the list
$InstalledApps = $InstalledApps | 
    Where-Object { $_ -and $_.Trim() -ne "" } | 
    Sort-Object -Unique

Write-Host "Found $($InstalledApps.Count) installed applications" -ForegroundColor Green
Write-Host ""

$detailedLog += "Total Installed Applications Found: $($InstalledApps.Count)"
$detailedLog += ""

# --- Scan AppData folders ---
$minSizeBytes = $MinSizeMB * 1MB
$Orphaned = @()
$Skipped = @{
    Whitelist = @()
    TooSmall = @()
    Matched = @()
    ScanError = @()
}
$counter = 0

$totalFolders = ($AppDataPaths | ForEach-Object { 
    (Get-ChildItem -Directory -Path $_ -ErrorAction SilentlyContinue).Count 
}) | Measure-Object -Sum | Select-Object -ExpandProperty Sum

Write-Host "Scanning $totalFolders folders..." -ForegroundColor Cyan
Write-Host ""

foreach ($Path in $AppDataPaths) {
    $locationName = if ($Path -like "*\Local*") { "Local" } else { "Roaming" }
    Write-Host "Scanning: $Path" -ForegroundColor Yellow
    
    Get-ChildItem -Directory -Path $Path -ErrorAction SilentlyContinue | ForEach-Object {
        $counter++
        Write-Progress -Activity "Scanning AppData folders..." `
            -Status "($counter / $totalFolders) - $($_.Name)" `
            -PercentComplete (($counter / $totalFolders) * 100)
        
        $Folder = $_.Name
        $FullName = $_.FullName

        # Check whitelist (case-insensitive)
        if ($WhitelistLower -contains $Folder.ToLower()) {
            $Skipped.Whitelist += $Folder
            return
        }

        # Calculate folder size
        $folderSize = 0
        try {
            $folderSize = (Get-ChildItem -Recurse -Force -LiteralPath $FullName -ErrorAction Stop | 
                Measure-Object -Property Length -Sum -ErrorAction Stop).Sum
            if ($null -eq $folderSize) { $folderSize = 0 }
        } catch {
            $Skipped.ScanError += $Folder
            return
        }

        # Check size threshold
        if ($folderSize -lt $minSizeBytes) {
            $Skipped.TooSmall += $Folder
            return
        }

        # Check if folder matches any installed application
        $isInstalled = $false
        $matchedApp = $null
        
        foreach ($app in $InstalledApps) {
            if ([string]::IsNullOrWhiteSpace($app)) { continue }
            
            # Bidirectional wildcard matching
            if (($app -like "*$Folder*") -or ($Folder -like "*$app*")) {
                $isInstalled = $true
                $matchedApp = $app
                break
            }
            
            # Word-level matching
            $folderWords = $Folder -split '[\s\-_\.]' | Where-Object { $_.Length -gt 3 }
            $appWords = $app -split '[\s\-_\.]' | Where-Object { $_.Length -gt 3 }
            
            foreach ($fw in $folderWords) {
                foreach ($aw in $appWords) {
                    if ($fw -like "*$aw*" -or $aw -like "*$fw*") {
                        $isInstalled = $true
                        $matchedApp = $app
                        break
                    }
                }
                if ($isInstalled) { break }
            }
            
            if ($isInstalled) { break }
        }

        if ($isInstalled) {
            $Skipped.Matched += "$Folder -> $matchedApp"
        } else {
            # Potential orphan
            $Orphaned += [PSCustomObject]@{
                Index = $Orphaned.Count + 1
                Path = $FullName
                Name = $Folder
                Size = $folderSize
                Location = $locationName
                Selected = $true  # Default to selected for deletion
            }
        }
    }
}
Write-Progress -Activity "Scan complete." -Completed

# --- Display results ---
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "SCAN COMPLETE" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

if ($Orphaned.Count -eq 0) {
    Write-Host "No orphaned folders larger than $MinSizeMB MB were found. Your AppData is clean!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Statistics:" -ForegroundColor Cyan
    Write-Host "  Folders scanned: $counter"
    Write-Host "  Whitelisted: $($Skipped.Whitelist.Count)"
    Write-Host "  Too small: $($Skipped.TooSmall.Count)"
    Write-Host "  Matched to apps: $($Skipped.Matched.Count)"
    exit
}

$totalSize = ($Orphaned | Measure-Object -Property Size -Sum).Sum
$totalSizeMB = [math]::Round($totalSize/1MB, 2)
$totalSizeGB = [math]::Round($totalSize/1GB, 2)

Write-Host "Found $($Orphaned.Count) potential orphaned folders" -ForegroundColor Yellow
Write-Host "Total size: ${totalSizeMB} MB (${totalSizeGB} GB)" -ForegroundColor Yellow
Write-Host ""

# Display the list
Write-Host "Potential Orphaned Folders:" -ForegroundColor Yellow
Write-Host ""
$Orphaned | Sort-Object -Property Size -Descending | Format-Table -AutoSize @{
    Label = "#";
    Expression = { $_.Index };
    Width = 4
}, @{
    Label = "Size (MB)";
    Expression = { [math]::Round($_.Size/1MB, 2) };
    Alignment = "Right";
    Width = 10
}, @{
    Label = "Loc";
    Expression = { $_.Location };
    Width = 7
}, @{
    Label = "Folder Name";
    Expression = { $_.Name }
}

# --- Interactive Selection Menu ---
if (-not $AutoDelete) {
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host "INTERACTIVE SELECTION" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "All folders are currently SELECTED for deletion." -ForegroundColor Yellow
    Write-Host "Review carefully and deselect folders you want to KEEP." -ForegroundColor Yellow
    Write-Host ""
    
    $continue = $true
    while ($continue) {
        $selectedCount = ($Orphaned | Where-Object { $_.Selected }).Count
        $selectedSize = ($Orphaned | Where-Object { $_.Selected } | Measure-Object -Property Size -Sum).Sum
        $selectedSizeMB = [math]::Round($selectedSize/1MB, 2)
        $selectedSizeGB = [math]::Round($selectedSize/1GB, 2)
        
        Write-Host ""
        Write-Host "Currently selected: $selectedCount folders (${selectedSizeMB} MB / ${selectedSizeGB} GB)" -ForegroundColor $(if ($selectedCount -gt 0) { "Yellow" } else { "Green" })
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Cyan
        Write-Host "  [1-$($Orphaned.Count)] - Toggle selection for folder # (e.g., type '5' to toggle folder 5)"
        Write-Host "  [A]  - Select All for deletion"
        Write-Host "  [N]  - Select None (keep all)"
        Write-Host "  [D]  - Delete selected folders"
        Write-Host "  [S]  - Show current selection"
        Write-Host "  [Q]  - Quit without deleting"
        Write-Host ""
        
        $choice = Read-Host "Your choice"
        $choice = $choice.Trim().ToUpper()
        
        switch -Regex ($choice) {
            '^[0-9]+$' {
                # Toggle individual folder
                $index = [int]$choice
                if ($index -ge 1 -and $index -le $Orphaned.Count) {
                    $folder = $Orphaned[$index - 1]
                    $folder.Selected = -not $folder.Selected
                    $status = if ($folder.Selected) { "WILL DELETE" } else { "WILL KEEP" }
                    Write-Host "Folder #$index ($($folder.Name)): $status" -ForegroundColor $(if ($folder.Selected) { "Red" } else { "Green" })
                } else {
                    Write-Host "Invalid folder number. Enter 1-$($Orphaned.Count)" -ForegroundColor Red
                }
            }
            '^A$' {
                # Select all
                $Orphaned | ForEach-Object { $_.Selected = $true }
                Write-Host "All folders selected for deletion" -ForegroundColor Yellow
            }
            '^N$' {
                # Select none
                $Orphaned | ForEach-Object { $_.Selected = $false }
                Write-Host "All folders deselected - nothing will be deleted" -ForegroundColor Green
            }
            '^S$' {
                # Show selection
                Write-Host ""
                Write-Host "Current Selection:" -ForegroundColor Cyan
                $Orphaned | Sort-Object -Property Index | ForEach-Object {
                    $status = if ($_.Selected) { "[DELETE]" } else { "[ KEEP ]" }
                    $statusColor = if ($_.Selected) { "Red" } else { "Green" }
                    $sizeMB = [math]::Round($_.Size/1MB, 2)
                    Write-Host "$status #$($_.Index) - ${sizeMB} MB - $($_.Name)" -ForegroundColor $statusColor
                }
            }
            '^D$' {
                # Proceed with deletion
                $selectedToDelete = $Orphaned | Where-Object { $_.Selected }
                if ($selectedToDelete.Count -eq 0) {
                    Write-Host "No folders selected for deletion." -ForegroundColor Green
                    $continue = $false
                } else {
                    Write-Host ""
                    Write-Host "WARNING: You are about to delete $($selectedToDelete.Count) folders (${selectedSizeMB} MB)" -ForegroundColor Red
                    Write-Host "This action cannot be easily undone!" -ForegroundColor Red
                    Write-Host ""
                    $confirm = Read-Host "Type 'DELETE' to confirm (or anything else to cancel)"
                    if ($confirm -eq 'DELETE') {
                        $continue = $false
                    } else {
                        Write-Host "Deletion cancelled. You can continue selecting." -ForegroundColor Green
                    }
                }
            }
            '^Q$' {
                # Quit
                Write-Host "Exiting without deleting anything." -ForegroundColor Green
                exit
            }
            default {
                Write-Host "Invalid choice. Try again." -ForegroundColor Red
            }
        }
    }
} else {
    Write-Host ""
    Write-Host "AUTO-DELETE MODE: Will delete all $($Orphaned.Count) folders" -ForegroundColor Red
    Start-Sleep -Seconds 2
}

# --- Deletion Process ---
$toDelete = $Orphaned | Where-Object { $_.Selected }

if ($toDelete.Count -eq 0) {
    Write-Host ""
    Write-Host "No folders selected for deletion. Exiting." -ForegroundColor Green
    exit
}

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Red
Write-Host "DELETING FOLDERS" -ForegroundColor Red
Write-Host ("=" * 80) -ForegroundColor Red
Write-Host ""

$deletedCount = 0
$deletedSize = 0
$failedCount = 0
$failed = @()

foreach ($item in $toDelete) {
    try {
        Remove-Item -Recurse -Force -LiteralPath $item.Path -ErrorAction Stop
        $sizeMB = [math]::Round($item.Size/1MB, 2)
        Write-Host "[OK] Deleted: $($item.Name) (${sizeMB} MB)" -ForegroundColor Green
        $deletedCount++
        $deletedSize += $item.Size
    } catch {
        Write-Host "[FAIL] Failed to delete: $($item.Name)" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        $failedCount++
        $failed += $item.Name
    }
}

# --- Final summary ---
$finalDrive = Get-PSDrive C
$finalFreeSpaceGB = [math]::Round($finalDrive.Free / 1GB, 2)
$actualFreedGB = [math]::Round($finalFreeSpaceGB - $initialFreeSpaceGB, 2)
$freedMB = [math]::Round($deletedSize/1MB, 2)
$freedGB = [math]::Round($deletedSize/1GB, 2)

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Green
Write-Host "CLEANUP SUMMARY" -ForegroundColor Green
Write-Host ("=" * 80) -ForegroundColor Green
Write-Host "Successfully deleted: $deletedCount folders" -ForegroundColor Green
Write-Host "Calculated freed space: ${freedMB} MB (${freedGB} GB)" -ForegroundColor Green

if ($failedCount -gt 0) {
    Write-Host ""
    Write-Host "Failed deletions: $failedCount folders" -ForegroundColor Yellow
    Write-Host "  (May be in use or protected)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Disk Space Information:" -ForegroundColor Cyan
Write-Host "  Before cleanup: ${initialFreeSpaceGB} GB free on C:" -ForegroundColor White
Write-Host "  After cleanup:  ${finalFreeSpaceGB} GB free on C:" -ForegroundColor White
Write-Host "  Actual space freed: ${actualFreedGB} GB" -ForegroundColor Yellow

# --- Save log ---
$detailedLog += ""
$detailedLog += "DELETED FOLDERS"
$detailedLog += "=" * 80
foreach ($item in $toDelete) {
    $status = if ($item.Name -in $failed) { "FAILED" } else { "SUCCESS" }
    $detailedLog += "$status - $($item.Path) - $([math]::Round($item.Size/1MB, 2)) MB"
}
$detailedLog += ""
$detailedLog += "SUMMARY"
$detailedLog += "Deleted: $deletedCount | Failed: $failedCount | Space Freed: ${freedGB} GB"

try {
    $detailedLog | Out-File -FilePath $LogPath -Encoding UTF8
    Write-Host ""
    Write-Host "Log saved to: $LogPath" -ForegroundColor Cyan
} catch {
    Write-Host ""
    Write-Host "Could not save log file: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Cleanup complete!" -ForegroundColor Green