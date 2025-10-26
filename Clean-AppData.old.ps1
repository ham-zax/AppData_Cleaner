<#
.SYNOPSIS
    Scans AppData\Local and AppData\Roaming for orphaned folders from uninstalled applications and provides an option to delete them.

.DESCRIPTION
    This script identifies potentially orphaned application data folders by comparing them against a list of currently installed programs.
    It includes enhanced safety features, better matching logic, comprehensive logging, and PowerShell's built-in -WhatIf and -Confirm parameters.

.PARAMETER MinSizeMB
    The minimum size in megabytes a folder must be to be considered for deletion.
    This helps ignore tiny, empty, or insignificant leftover folders. Defaults to 1 MB.

.PARAMETER AdditionalWhitelist
    Additional folder names to add to the safety whitelist (case-insensitive).

.EXAMPLE
    .\Clean-AppData.ps1 -WhatIf
    Runs the script in "Dry Run" mode. Shows folders that WOULD be deleted without actually deleting anything. RECOMMENDED FIRST STEP.

.EXAMPLE
    .\Clean-AppData.ps1 -Verbose
    Runs the script with detailed, step-by-step output of the scanning process.

.EXAMPLE
    .\Clean-AppData.ps1 -Confirm
    Runs the script and prompts for confirmation before deleting each individual folder.

.EXAMPLE
    .\Clean-AppData.ps1 -MinSizeMB 50 -Verbose -WhatIf
    Shows orphaned folders larger than 50 MB with detailed progress (dry run).

.EXAMPLE
    .\Clean-AppData.ps1 -AdditionalWhitelist @('MyApp', 'CustomFolder')
    Adds custom folders to the safety whitelist.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(HelpMessage = 'Minimum folder size in MB to report as an orphan.')]
    [double]$MinSizeMB = 1,
    
    [Parameter(HelpMessage = 'Additional folder names to whitelist.')]
    [string[]]$AdditionalWhitelist = @()
)

# --- SAFETY: Comprehensive whitelist of folders to NEVER delete ---
Write-Verbose "Initializing safety whitelist..."
$Whitelist = @(
    # Microsoft & Windows
    'Microsoft', 'Microsoft Edge', 'Packages', 'Windows', 'WindowsApps', 'Programs',
    'MicrosoftEdge', 'Windows Defender', 'WindowsPowerShell', 'OneDrive',
    
    # Hardware Manufacturers
    'Google', 'NVIDIA', 'NVIDIA Corporation', 'Intel', 'AMD', 'Realtek',
    'Dell', 'HP', 'Lenovo', 'ASUS', 'Acer', 'Logitech', 'Corsair', 'Razer',
    
    # Common Software Publishers
    'Mozilla', 'Adobe', 'Apple', 'Oracle', 'Java', 'Steam', 'Epic', 'EpicGamesLauncher',
    'Discord', 'Spotify', 'Slack', 'Zoom', 'TeamViewer', 'VLC',
    
    # Developer Tools (MINIMAL - only critical system integration)
    # NOTE: Caches like npm-cache, pnpm-cache are NOT whitelisted - they can be safely cleaned
    # If you actively use dev tools, add them via -AdditionalWhitelist parameter
    'JetBrains', 'Visual Studio', 'Code', 'git', 'uvm', 'uv',
    
    # System & Common
    'Common Files', 'Temp', 'Downloaded Installations', 'CrashDumps',
    'D3DSCache', 'FontCache', 'IconCache', 'Microsoft_Corporation'
) + $AdditionalWhitelist

# Convert whitelist to lowercase for case-insensitive comparison
$WhitelistLower = $Whitelist | ForEach-Object { $_.ToLower() }

# --- Define paths to scan ---
$AppDataPaths = @(
    "$env:USERPROFILE\AppData\Local",
    "$env:USERPROFILE\AppData\Roaming"
)

# --- Initialize detailed log ---
$LogPath = "$env:USERPROFILE\Desktop\AppDataCleanup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$detailedLog = @()
$detailedLog += "AppData Cleanup Scan - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$detailedLog += "=" * 80
$detailedLog += ""

# --- Get installed program names from multiple sources ---
Write-Host "Gathering list of installed applications..." -ForegroundColor Cyan
$InstalledApps = @()

# Registry-based applications
Write-Verbose "Scanning registry for installed applications..."
$InstalledApps += (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, `
    HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*, `
    HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* `
    -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty DisplayName -ErrorAction SilentlyContinue)

# Windows Store / UWP apps
Write-Verbose "Scanning for Windows Store apps..."
try {
    $InstalledApps += (Get-AppxPackage -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
} catch {
    Write-Verbose "Could not retrieve Windows Store apps: $($_.Exception.Message)"
}

# Clean up the list
$InstalledApps = $InstalledApps | 
    Where-Object { $_ -and $_.Trim() -ne "" } | 
    Sort-Object -Unique

Write-Host "Found $($InstalledApps.Count) installed applications.`n" -ForegroundColor Green

$detailedLog += "Total Installed Applications Found: $($InstalledApps.Count)"
$detailedLog += ""

# --- Scan AppData folders and identify potential orphans ---
$minSizeBytes = $MinSizeMB * 1MB
$Orphaned = @()
$Skipped = @{
    Whitelist = @()
    TooSmall = @()
    Matched = @()
    ScanError = @()
}
$counter = 0

# Pre-calculate total for progress bar
$totalFolders = ($AppDataPaths | ForEach-Object { 
    (Get-ChildItem -Directory -Path $_ -ErrorAction SilentlyContinue).Count 
}) | Measure-Object -Sum | Select-Object -ExpandProperty Sum

Write-Host "Scanning $totalFolders folders for orphaned data...`n" -ForegroundColor Cyan

foreach ($Path in $AppDataPaths) {
    Write-Host "Scanning: $Path" -ForegroundColor Yellow
    $detailedLog += "Scanning: $Path"
    $detailedLog += "-" * 80
    
    Get-ChildItem -Directory -Path $Path -ErrorAction SilentlyContinue | ForEach-Object {
        $counter++
        Write-Progress -Activity "Scanning AppData folders..." `
            -Status "($counter / $totalFolders) - $($_.Name)" `
            -PercentComplete (($counter / $totalFolders) * 100)
        
        $Folder = $_.Name
        $FullName = $_.FullName

        # 1. Check against the safety whitelist (case-insensitive)
        if ($WhitelistLower -contains $Folder.ToLower()) {
            Write-Verbose "Skipping whitelisted folder: $Folder"
            $Skipped.Whitelist += $Folder
            return
        }

        # 2. Calculate folder size with error handling
        $folderSize = 0
        try {
            $folderSize = (Get-ChildItem -Recurse -Force -LiteralPath $FullName -ErrorAction Stop | 
                Measure-Object -Property Length -Sum -ErrorAction Stop).Sum
            if ($null -eq $folderSize) { $folderSize = 0 }
        } catch {
            Write-Verbose "Could not calculate size for: $Folder - $($_.Exception.Message)"
            $Skipped.ScanError += $Folder
            return
        }

        # 3. Check if the folder is smaller than the minimum size threshold
        if ($folderSize -lt $minSizeBytes) {
            Write-Verbose "Skipping small folder: $Folder ($([math]::Round($folderSize/1KB, 2)) KB)"
            $Skipped.TooSmall += $Folder
            return
        }

        # 4. Enhanced matching: Check if folder is related to any installed application
        # Use bidirectional fuzzy matching for better accuracy
        $isInstalled = $false
        $matchedApp = $null
        
        foreach ($app in $InstalledApps) {
            # Skip empty app names
            if ([string]::IsNullOrWhiteSpace($app)) { continue }
            
            # Bidirectional wildcard matching (case-insensitive)
            # Check if folder name is in app name OR app name is in folder name
            if (($app -like "*$Folder*") -or ($Folder -like "*$app*")) {
                $isInstalled = $true
                $matchedApp = $app
                Write-Verbose "Match found: Folder '$Folder' <-> App '$app'"
                break
            }
            
            # Additional check: Split on common delimiters and check individual words
            $folderWords = $Folder -split '[\s\-_\.]' | Where-Object { $_.Length -gt 3 }
            $appWords = $app -split '[\s\-_\.]' | Where-Object { $_.Length -gt 3 }
            
            foreach ($fw in $folderWords) {
                foreach ($aw in $appWords) {
                    if ($fw -like "*$aw*" -or $aw -like "*$fw*") {
                        $isInstalled = $true
                        $matchedApp = $app
                        Write-Verbose "Word match found: '$fw' <-> '$aw' (Folder: $Folder, App: $app)"
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
            # This is a potential orphan
            $Orphaned += [PSCustomObject]@{
                Path = $FullName
                Name = $Folder
                Size = $folderSize
                Location = if ($Path -like "*\Local*") { "Local" } else { "Roaming" }
            }
            $detailedLog += "ORPHAN: $Folder ($([math]::Round($folderSize/1MB, 2)) MB)"
        }
    }
    $detailedLog += ""
}
Write-Progress -Activity "Scan complete." -Completed

# --- Add statistics to log ---
$detailedLog += "=" * 80
$detailedLog += "SCAN STATISTICS"
$detailedLog += "=" * 80
$detailedLog += "Total Folders Scanned: $counter"
$detailedLog += "Whitelisted (Skipped): $($Skipped.Whitelist.Count)"
$detailedLog += "Too Small (Skipped): $($Skipped.TooSmall.Count)"
$detailedLog += "Matched to Apps (Kept): $($Skipped.Matched.Count)"
$detailedLog += "Scan Errors: $($Skipped.ScanError.Count)"
$detailedLog += "Potential Orphans: $($Orphaned.Count)"
$detailedLog += ""

# --- Capture initial free space on C: drive ---
Write-Verbose "Capturing initial disk space..."
$initialDrive = Get-PSDrive C
$initialFreeSpaceGB = [math]::Round($initialDrive.Free / 1GB, 2)

# --- Display results ---
Write-Host "`n" + ("=" * 80) -ForegroundColor Cyan
Write-Host "SCAN COMPLETE" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan

if ($Orphaned.Count -eq 0) {
    Write-Host "`nNo orphaned folders larger than $MinSizeMB MB were found. Your AppData is clean!" -ForegroundColor Green
} else {
    $totalSize = ($Orphaned | Measure-Object -Property Size -Sum).Sum
    Write-Host "`nFound $($Orphaned.Count) potential orphaned folders" -ForegroundColor Yellow
    Write-Host "Total reclaimable space: $([math]::Round($totalSize/1MB, 2)) MB ($([math]::Round($totalSize/1GB, 2)) GB)" -ForegroundColor Yellow
    Write-Host "`n⚠️  REVIEW THIS LIST CAREFULLY BEFORE DELETING ⚠️`n" -ForegroundColor Red
    
    # Format output as a detailed table
    $Orphaned | Sort-Object -Property Size -Descending | Format-Table -AutoSize @{
        Label = "Size (MB)";
        Expression = { [math]::Round($_.Size/1MB, 2) };
        Alignment = "Right"
    }, @{
        Label = "Location";
        Expression = { $_.Location };
        Width = 8
    }, @{
        Label = "Folder Name";
        Expression = { $_.Name }
    }

    # --- Save detailed log ---
    $detailedLog += "ORPHANED FOLDERS FOUND"
    $detailedLog += "=" * 80
    foreach ($item in ($Orphaned | Sort-Object -Property Size -Descending)) {
        $detailedLog += "$($item.Path) - $([math]::Round($item.Size/1MB, 2)) MB"
    }
    
    $detailedLog | Out-File -FilePath $LogPath -Encoding UTF8
    Write-Host "📄 Detailed log saved to: $LogPath`n" -ForegroundColor Cyan

    # --- Deletion Process using ShouldProcess ---
    if (-not $WhatIfPreference) {
        Write-Host "Proceeding with deletion..." -ForegroundColor Yellow
        Write-Host "(Use -WhatIf to preview without deleting, or -Confirm to approve each deletion)`n" -ForegroundColor Gray
    }
    
    $deletedCount = 0
    $deletedSize = 0
    $failedCount = 0
    
    foreach ($item in $Orphaned) {
        if ($PSCmdlet.ShouldProcess($item.Path, "Delete Orphaned Folder ($([math]::Round($item.Size/1MB, 2)) MB)")) {
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
            }
        }
    }
    
    # Final summary
    if (-not $WhatIfPreference -and $deletedCount -gt 0) {
        $freedMB = [math]::Round($deletedSize/1MB, 2)
        $freedGB = [math]::Round($deletedSize/1GB, 2)
        
        # Capture final free space and calculate actual space freed
        $finalDrive = Get-PSDrive C
        $finalFreeSpaceGB = [math]::Round($finalDrive.Free / 1GB, 2)
        $actualFreedGB = [math]::Round($finalFreeSpaceGB - $initialFreeSpaceGB, 2)
        
        Write-Host "`n" + ("=" * 80) -ForegroundColor Green
        Write-Host "CLEANUP SUMMARY" -ForegroundColor Green
        Write-Host ("=" * 80) -ForegroundColor Green
        Write-Host "Successfully deleted: $deletedCount folders" -ForegroundColor Green
        Write-Host "Calculated freed space: ${freedMB} MB (${freedGB} GB)" -ForegroundColor Green
        Write-Host "`nDisk Space Information:" -ForegroundColor Cyan
        Write-Host "  Before cleanup: $initialFreeSpaceGB GB free on C:" -ForegroundColor White
        Write-Host "  After cleanup:  $finalFreeSpaceGB GB free on C:" -ForegroundColor White
        Write-Host "  Actual space freed: ${actualFreedGB} GB" -ForegroundColor Yellow
        if ($failedCount -gt 0) {
            Write-Host "Failed deletions: $failedCount folders (may be in use or protected)" -ForegroundColor Yellow
        }
    }
}

Write-Host "`n✨ Cleanup process complete. ✨" -ForegroundColor Cyan