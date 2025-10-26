<#
.SYNOPSIS
    Cleans temporary files and caches to reclaim disk space safely.

.DESCRIPTION
    Removes files from Windows temp directories, user temp folders, browser caches, and application caches.
    Includes safe deletion with error handling, comprehensive logging, and careful aggressive mode handling.

.PARAMETER Aggressive
    Also removes package manager and build caches (requires confirmation).

.PARAMETER DryRun
    Lists candidate folders without deleting anything (similar to -WhatIf).

.PARAMETER MinimumSizeMB
    Only show/delete folders larger than this size. Defaults to 1 MB.

.PARAMETER NoParallel
    Disable parallel deletion (enabled by default on PS 7+).

.PARAMETER LogDirectory
    Directory where the cleanup log will be written. Created if it does not exist. Defaults to the user profile.

.EXAMPLE
    .\Clean-TempFiles.ps1 -DryRun
    Shows all temp files and caches that would be deleted without actually deleting them.

.EXAMPLE
    .\Clean-TempFiles.ps1 -Aggressive -DryRun
    Preview aggressive mode (package manager caches) without deletion.

.EXAMPLE
    .\Clean-TempFiles.ps1 -Aggressive
    Deletes temp files, caches, and package manager caches (with confirmation).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(HelpMessage = 'Also remove package manager and build caches (requires confirmation).')]
    [switch]$Aggressive,

    [Parameter(HelpMessage = 'Report files without deleting them.')]
    [switch]$DryRun,

    [Parameter(HelpMessage = 'Only show/delete folders larger than this size in MB.')]
    [int]$MinimumSizeMB = 1,

    [Parameter(HelpMessage = 'Disable parallel deletion (enabled by default on PS 7+).')]
    [switch]$NoParallel,

    [Parameter(HelpMessage = 'Directory where the cleanup log will be written.')]
    [string]$LogDirectory = "$env:USERPROFILE"
)

function Convert-Size {
    [CmdletBinding()]
    param(
        [double]$Bytes
    )

    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    elseif ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    elseif ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    else { return ('{0:N0} B' -f $Bytes) }
}

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Not running as Administrator. Some system temp paths may be inaccessible."
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
try {
    $logDirectoryResolved = (Resolve-Path -LiteralPath $LogDirectory -ErrorAction Stop).Path
} catch {
    $null = New-Item -ItemType Directory -Path $LogDirectory -Force -ErrorAction SilentlyContinue
    $logDirectoryResolved = (Resolve-Path -LiteralPath $LogDirectory -ErrorAction Stop).Path
}

$logPath = Join-Path -Path $logDirectoryResolved -ChildPath "TempCleanup_$timestamp.log"
$divider = [string]::new('=', 80)
$logLines = @(
    "Temp Files Cleanup - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    $divider,
    "Mode: $(if ($Aggressive) { 'AGGRESSIVE' } else { 'STANDARD' })",
    "Admin: $isAdmin",
    ""
)

# Confirmation for aggressive mode
if ($Aggressive -and -not $DryRun) {
    Write-Host ""
    Write-Host "⚠️  AGGRESSIVE MODE: Will delete package manager caches" -ForegroundColor Yellow
    Write-Host "This will cause re-download of packages on next use" -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "Continue with aggressive cleanup? (y/N)"
    if ($confirm -ne 'y') {
        Write-Host "Cancelled." -ForegroundColor Green
        return
    }
    Write-Host ""
}

# Define cleanup paths
$cleanupPaths = @()
$minSizeBytes = $MinimumSizeMB * 1MB

# Standard temp directories (safe to delete)
$standardPaths = @(
    "$env:TEMP",
    "$env:WINDIR\Temp",
    "$env:USERPROFILE\AppData\Local\Temp",
    "$env:USERPROFILE\AppData\Local\CrashDumps",
    "$env:USERPROFILE\AppData\Local\Microsoft\Windows\WebCache",
    "$env:USERPROFILE\AppData\LocalLow\Temp",
    "$env:USERPROFILE\AppData\Local\Microsoft\Windows\WER\ReportQueue",
    "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache*.db",
    "$env:LOCALAPPDATA\Microsoft\Terminal Server Client\Cache"
)

foreach ($path in $standardPaths) {
    if (Test-Path -LiteralPath $path) {
        $cleanupPaths += @{
            Path = $path
            Type = "System Temp"
            Aggressive = $false
        }
    }
}

# Browser caches (safe to delete)
$browserCaches = @(
    "$env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\Cache",
    "$env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\Code Cache",
    "$env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\Default\Cache",
    "$env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\Default\Code Cache",
    "$env:USERPROFILE\AppData\Local\BraveSoftware\Brave-Browser\User Data\Default\Cache"
)

foreach ($cache in $browserCaches) {
    if (Test-Path -LiteralPath $cache) {
        $cleanupPaths += @{
            Path = $cache
            Type = "Browser Cache"
            Aggressive = $false
        }
    }
}

# Firefox cache (handle wildcard profiles)
$firefoxProfilesPath = "$env:USERPROFILE\AppData\Local\Mozilla Firefox\Profiles"
if (Test-Path -LiteralPath $firefoxProfilesPath) {
    try {
        $firefoxProfiles = Get-ChildItem -LiteralPath $firefoxProfilesPath -Directory -ErrorAction Stop
        foreach ($profile in $firefoxProfiles) {
            $cachePath = Join-Path $profile.FullName "cache2"
            if (Test-Path -LiteralPath $cachePath) {
                $cleanupPaths += @{
                    Path = $cachePath
                    Type = "Browser Cache"
                    Aggressive = $false
                }
            }
        }
    } catch {
        Write-Warning "Could not enumerate Firefox profiles: $($_.Exception.Message)"
    }
}

# Application caches (safe to delete)
$appCaches = @(
    "$env:USERPROFILE\AppData\Local\Microsoft\Windows\INetCache",
    "$env:USERPROFILE\AppData\Local\NuGet\v3-cache",
    "$env:LOCALAPPDATA\NuGet\Cache"
)

foreach ($cache in $appCaches) {
    if (Test-Path -LiteralPath $cache) {
        $cleanupPaths += @{
            Path = $cache
            Type = "App Cache"
            Aggressive = $false
        }
    }
}

# Aggressive: Package manager caches (CAREFULLY)
if ($Aggressive) {
    $aggressivePaths = @(
        "$env:USERPROFILE\.npm\_cacache",                     # npm cache only (not packages)
        "$env:USERPROFILE\.npm\_logs",                        # npm logs
        "$env:APPDATA\npm-cache",                             # Alternative npm cache
        "$env:USERPROFILE\.pnpm-store\v3\tmp",               # pnpm temp only
        "$env:USERPROFILE\.cargo\registry\cache",             # cargo cache (safe, regenerable)
        "$env:USERPROFILE\.nuget\v3-cache",                  # NuGet HTTP cache
        "$env:LOCALAPPDATA\Microsoft\VisualStudio\*\ComponentModelCache",  # VS cache only
        "$env:USERPROFILE\.gradle\caches",                    # Gradle cache (safe)
        "$env:USERPROFILE\.gradle\wrapper\dists\.tmp",       # Gradle temp
        "$env:LOCALAPPDATA\JetBrains\*\caches"               # IDE caches only
    )

    foreach ($cache in $aggressivePaths) {
        # Handle wildcards
        if ($cache -like "*\*") {
            $basePath = $cache -replace '\\\*.*', ''
            if (Test-Path -LiteralPath $basePath) {
                try {
                    $items = Get-ChildItem -LiteralPath $basePath -Directory -ErrorAction Stop
                    foreach ($item in $items) {
                        $expandedPath = $cache -replace '\\\*', '\' + $item.Name
                        if (Test-Path -LiteralPath $expandedPath) {
                            $cleanupPaths += @{
                                Path = $expandedPath
                                Type = "Package Manager / Build Cache"
                                Aggressive = $true
                            }
                        }
                    }
                } catch {
                    Write-Warning "Could not enumerate '$basePath': $($_.Exception.Message)"
                }
            }
        } else {
            if (Test-Path -LiteralPath $cache) {
                $cleanupPaths += @{
                    Path = $cache
                    Type = "Package Manager / Build Cache"
                    Aggressive = $true
                }
            }
        }
    }
}

Write-Host "Scanning for temp files and caches..." -ForegroundColor Cyan
$targets = @()
$totalSize = 0

foreach ($item in $cleanupPaths) {
    $path = $item.Path
    $type = $item.Type
    
    try {
        if (Test-Path -LiteralPath $path -PathType Container) {
            # Skip empty directories early
            $firstFile = Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $firstFile) { continue }

            $size = 0
            $fileCount = 0
            
            try {
                $files = Get-ChildItem -LiteralPath $path -Recurse -Force -File -ErrorAction Stop
                $fileCount = ($files | Measure-Object).Count
                $size = ($files | Measure-Object -Property Length -Sum -ErrorAction Stop).Sum
                if ($null -eq $size) { $size = 0 }
            } catch {
                Write-Warning "Could not calculate size for '$path': $($_.Exception.Message)"
            }
            
            # Only include if meets minimum size threshold
            if ($size -ge $minSizeBytes -and $fileCount -gt 0) {
                $targets += [PSCustomObject]@{
                    Path = $path
                    Type = $type
                    Size = [double]$size
                    FileCount = [int]$fileCount
                    Aggressive = $item.Aggressive
                }
                $totalSize += $size
                Write-Host "  Found: $type - $path ($(Convert-Size -Bytes $size), $fileCount files)" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Warning "Error accessing '$path': $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host ($divider) -ForegroundColor Cyan
Write-Host "CLEANUP CANDIDATES" -ForegroundColor Cyan
Write-Host ($divider) -ForegroundColor Cyan

if ($targets.Count -eq 0) {
    Write-Host "No temp files or caches found (larger than $MinimumSizeMB MB)." -ForegroundColor Green
    $logLines += "RESULT: No temp files detected."
    $logLines | Out-File -FilePath $logPath -Encoding UTF8
    return
}

$targets | Sort-Object Size -Descending | Select-Object `
    @{Name = 'Type'; Expression = { $_.Type } },
    @{Name = 'Size'; Expression = { Convert-Size -Bytes $_.Size } },
    @{Name = 'Files'; Expression = { $_.FileCount } },
    @{Name = 'Path'; Expression = { $_.Path } } | Format-Table -AutoSize

Write-Host ""
Write-Host "Total reclaimable: $(Convert-Size -Bytes $totalSize)" -ForegroundColor Yellow

if ($DryRun -or $WhatIfPreference) {
    Write-Host "Dry run enabled. No files were deleted." -ForegroundColor Yellow
    $logLines += "MODE: DRY RUN - No deletions performed."
    $logLines | Out-File -FilePath $logPath -Encoding UTF8
    Write-Host "Log saved to: $logPath" -ForegroundColor Cyan
    return
}

Write-Host ""
Write-Host "Proceeding with deletion..." -ForegroundColor Yellow

# Use parallel deletion by default on PS 7+, unless -NoParallel is specified
$useParallel = (-not $NoParallel) -and $PSVersionTable.PSVersion.Major -ge 7

if ($useParallel) {
    # Parallel deletion with proper result collection
    $results = $targets | ForEach-Object -Parallel {
        $target = $_
        $path = $target.Path
        $type = $target.Type
        $size = $target.Size
        
        try {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            Write-Host "[OK] Deleted $($type): $($path)" -ForegroundColor Green
            [PSCustomObject]@{
                Success = $true
                Target = $target
                Message = "DELETED"
            }
        } catch {
            if ($_.Exception.Message -match 'being used by another process|Access is denied') {
                Write-Warning "Skipped locked path '$path' (in use by another process)."
                [PSCustomObject]@{
                    Success = $false
                    Target = $target
                    Message = "SKIPPED (LOCKED)"
                }
            } else {
                Write-Warning "Failed to delete '$path': $($_.Exception.Message)"
                [PSCustomObject]@{
                    Success = $false
                    Target = $target
                    Message = "FAILED: $($_.Exception.Message)"
                }
            }
        }
    } -ThrottleLimit 10

    $deleted = @($results | Where-Object Success)
    $deletedSize = ($deleted | Measure-Object -Property { $_.Target.Size } -Sum).Sum
    if ($null -eq $deletedSize) { $deletedSize = 0 }
    
    # Add results to log
    foreach ($result in $results) {
        if ($result.Success) {
            $logLines += "DELETED: $($result.Target.Type) - $($result.Target.Path) | $(Convert-Size -Bytes $result.Target.Size)"
        } else {
            $logLines += "$($result.Message): $($result.Target.Path)"
        }
    }
} else {
    # Sequential deletion with proper variable tracking
    $deleted = @()
    $failed = @()
    $deletedSize = 0

    foreach ($target in $targets) {
        $path = $target.Path
        $type = $target.Type
        $size = $target.Size
        $sizeLabel = Convert-Size -Bytes $size
        
        if ($PSCmdlet.ShouldProcess($path, "Delete $type ($sizeLabel)")) {
            try {
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
                Write-Host "[OK] Deleted $($type): $($path)" -ForegroundColor Green
                $deleted += $target
                $deletedSize += $size
                $logLines += "DELETED: $type - $path | $sizeLabel"
            } catch {
                if ($_.Exception.Message -match 'being used by another process|Access is denied') {
                    Write-Warning "Skipped locked path '$path' (in use by another process)."
                    $logLines += "SKIPPED (LOCKED): $path"
                } else {
                    Write-Warning "Failed to delete '$path': $($_.Exception.Message)"
                    $failed += $path
                    $logLines += "FAILED: $path -- $($_.Exception.Message)"
                }
            }
        }
    }
}

Write-Host ""
Write-Host ($divider) -ForegroundColor Green
Write-Host "CLEANUP SUMMARY" -ForegroundColor Green
Write-Host ($divider) -ForegroundColor Green
Write-Host "Candidates processed: $($targets.Count)" -ForegroundColor White
Write-Host "Deleted paths:      $($deleted.Count)" -ForegroundColor Green
Write-Host "Total freed:        $(Convert-Size -Bytes $deletedSize)" -ForegroundColor Green

$logLines += ""
$logLines += "SUMMARY: Deleted $($deleted.Count) of $($targets.Count) paths, Total Freed $(Convert-Size -Bytes $deletedSize)"
$logLines | Out-File -FilePath $logPath -Encoding UTF8
Write-Host ""
Write-Host "Log saved to: $logPath" -ForegroundColor Cyan
