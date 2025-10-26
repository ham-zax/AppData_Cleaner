<#
.SYNOPSIS
    Recursively finds and deletes node_modules folders to reclaim disk space.

.DESCRIPTION
    Traverses one or more root directories, identifies node_modules folders, reports their sizes,
    and (unless run in DryRun/WhatIf mode) deletes them. Generates a detailed log summarizing the
    scan and cleanup outcomes.

.PARAMETER Roots
    One or more directory roots to scan. Defaults to the current working directory.

.PARAMETER MaxDepth
    Limits how far below each root the script will look for node_modules folders. Use -1 for unlimited depth.

.PARAMETER DryRun
    Lists candidate folders without deleting anything (similar to -WhatIf).

.PARAMETER LogDirectory
    Directory where the cleanup log will be written. Created if it does not exist. Defaults to the user profile.

.EXAMPLE
    .\Clean-NodeModules.ps1 -Roots 'D:\Projects' -DryRun
    Shows all node_modules folders under D:\Projects and their sizes without deleting them.

.EXAMPLE
    .\Clean-NodeModules.ps1 -Roots 'D:\Projects','E:\Playground' -WhatIf
    Uses PowerShell's WhatIf semantics to preview deletions.

.EXAMPLE
    .\Clean-NodeModules.ps1 -Roots 'E:\Repos' -MaxDepth 2 -Confirm:$false
    Deletes node_modules folders up to two levels deep without prompting for confirmation.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Alias('Root', 'Path')]
    [string[]]$Roots,

    [Parameter(HelpMessage = 'Limit search depth relative to each root (-1 for unlimited).')]
    [int]$MaxDepth = -1,

    [Parameter(HelpMessage = 'Report folders without deleting them.')]
    [switch]$DryRun,

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

if (-not $PSBoundParameters.ContainsKey('Roots') -or -not $Roots) {
    $Roots = @()
    $userProfile = $env:USERPROFILE
    
    # Common user directories to scan (exclude system/protected paths)
    $commonPaths = @(
        'Desktop',
        'Documents',
        'Downloads',
        'OneDrive',
        'source',                  # e.g. C:\Users\<User>\source\repos (Visual Studio)
        'repos',                   # common manual repo folder
        'Projects',                # user-created project folder
        'project',                 # alternate naming
        'Code',                    # used by VSCode/JetBrains users
        'dev',                     # short for "development"
        'Development',             # capitalized variant
        'Work',                    # common for freelance/project folders
        'workspace',               # VS Code / IDE workspace folder
        'GitHub',                  # used when cloning repos
        'git',                     # another git clone location
        'Web',                     # for web dev / frontend projects
        'wwwroot'                  # ASP.NET / web root
    )

    
    foreach ($subPath in $commonPaths) {
        $fullPath = Join-Path -Path $userProfile -ChildPath $subPath
        if (Test-Path -LiteralPath $fullPath) {
            $Roots += $fullPath
        }
    }
    
    # Add current working directory if not already included
    $cwd = (Get-Location).Path
    if ($Roots -notcontains $cwd) {
        $Roots = @($cwd) + $Roots
    }

    # Add drive roots and common dev folders from other drives (D:, E:, etc.)
    $extraDrives = Get-PSDrive | Where-Object { $_.Free -and $_.Root -match '^[D-Z]:\\$' }
    foreach ($drive in $extraDrives) {
        # Add the entire drive root for comprehensive scanning
        $Roots += $drive.Root.TrimEnd('\')
        
        # Also add specific common folders for faster targeted scanning if needed
        foreach ($folder in @('dev', 'Projects', 'Repos', 'Code', 'source')) {
            $candidate = Join-Path $drive.Root $folder
            if (Test-Path -LiteralPath $candidate) {
                # Only add if not already included via root
                $candidateResolved = (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).ProviderPath
                if ($Roots -notcontains $candidateResolved -and $Roots -notcontains $drive.Root.TrimEnd('\')) {
                    $Roots += $candidateResolved
                }
            }
        }
    }
}

# Resolve root directories
$resolvedRoots = @()
foreach ($root in $Roots) {
    if ([string]::IsNullOrWhiteSpace($root)) { continue }
    try {
        $resolvedRoots += (Resolve-Path -LiteralPath $root -ErrorAction Stop).ProviderPath
    } catch {
        Write-Warning "Skipping invalid root '$root' ($($_.Exception.Message))"
    }
}

if (-not $resolvedRoots) {
    throw "No valid roots supplied. Provide at least one existing directory via -Roots."
}

# Resolve / create log directory
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
try {
    $logDirectoryResolved = (Resolve-Path -LiteralPath $LogDirectory -ErrorAction Stop).ProviderPath
} catch {
    try {
        $null = New-Item -ItemType Directory -Path $LogDirectory -Force
        $logDirectoryResolved = (Resolve-Path -LiteralPath $LogDirectory -ErrorAction Stop).ProviderPath
    } catch {
        throw "Unable to resolve log directory '$LogDirectory' ($($_.Exception.Message))"
    }
}

$logPath = Join-Path -Path $logDirectoryResolved -ChildPath "NodeModulesCleanup_$timestamp.log"
$divider = [string]::new('=', 80)
$logLines = @(
    "node_modules Cleanup - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    $divider,
    ""
)

$targets = @()

foreach ($root in ($resolvedRoots | Sort-Object -Unique)) {
    try {
        $rootItem = Get-Item -LiteralPath $root -ErrorAction Stop
    } catch {
        Write-Warning "Cannot access root '$root' ($($_.Exception.Message)). Skipping."
        $logLines += "SKIP ROOT: $root -- $($_.Exception.Message)"
        $logLines += ""
        continue
    }

    $rootFullPath = $rootItem.FullName.TrimEnd('\')
    if (-not (Test-Path -LiteralPath $rootFullPath -PathType Container)) {
        Write-Warning "Root '$rootFullPath' is not a directory. Skipping."
        $logLines += "SKIP ROOT: $rootFullPath -- not a directory"
        $logLines += ""
        continue
    }

    Write-Host "Scanning root: $rootFullPath" -ForegroundColor Cyan
    $logLines += "ROOT: $rootFullPath"
    $logLines += "-" * 80

    $rootDepth = ($rootFullPath -split '\\').Count

    try {
        Get-ChildItem -Directory -LiteralPath $rootFullPath -Recurse -Force -ErrorAction Stop | Where-Object {
            $_.Name -ieq 'node_modules'
        } | ForEach-Object {
            $nodePath = $_.FullName.TrimEnd('\')
            $nodeDepth = ($nodePath -split '\\').Count
            $relativeDepth = $nodeDepth - $rootDepth

            if ($MaxDepth -ge 0 -and $relativeDepth -gt $MaxDepth) {
                return
            }

            $sizeBytes = 0
            try {
                $sizeBytes = (Get-ChildItem -LiteralPath $nodePath -Recurse -Force -File -ErrorAction Stop | Measure-Object -Property Length -Sum -ErrorAction Stop).Sum
                if ($null -eq $sizeBytes) { $sizeBytes = 0 }
            } catch {
                Write-Warning "Unable to compute size for '$nodePath' ($($_.Exception.Message))"
                $logLines += "SIZE ERROR: $nodePath -- $($_.Exception.Message)"
            }

            $targets += [PSCustomObject]@{
                Root = $rootFullPath
                FullPath = $nodePath
                Depth = $relativeDepth
                SizeBytes = [double]$sizeBytes
            }

            Write-Host "  Found: $nodePath ($(Convert-Size -Bytes $sizeBytes))" -ForegroundColor Yellow
            $logLines += "FOUND: $nodePath | Size = $(Convert-Size -Bytes $sizeBytes)"
        }
    } catch {
        Write-Warning "Failed to enumerate '$rootFullPath' ($($_.Exception.Message))"
        $logLines += "ENUMERATION ERROR: $rootFullPath -- $($_.Exception.Message)"
    }

    $logLines += ""
}

if (-not $targets) {
    Write-Host "No node_modules folders were found inside the supplied roots." -ForegroundColor Green
    $logLines += "RESULT: No node_modules folders detected."
    $logLines | Out-File -FilePath $logPath -Encoding UTF8
    Write-Host "Log saved to: $logPath" -ForegroundColor Cyan
    return
}

# Remove nested duplicates (keep highest-level node_modules per branch)
$targets = $targets | Sort-Object { $_.FullPath.Length }
$deduped = New-Object System.Collections.Generic.List[object]
foreach ($item in $targets) {
    $isNested = $false
    foreach ($existing in $deduped) {
        if ($item.FullPath.Length -gt $existing.FullPath.Length -and
            $item.FullPath.StartsWith("$($existing.FullPath)\", [System.StringComparison]::OrdinalIgnoreCase)) {
            $isNested = $true
            break
        }
    }
    if (-not $isNested) {
        $deduped.Add($item)
    }
}
$targets = $deduped.ToArray()

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "NODE_MODULES CANDIDATES" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan

$targets | Sort-Object SizeBytes -Descending | Select-Object `
    @{Name = 'Size'; Expression = { Convert-Size -Bytes $_.SizeBytes } },
    @{Name = 'Depth'; Expression = { $_.Depth } },
    @{Name = 'Path'; Expression = { $_.FullPath } } | Format-Table -AutoSize

Write-Host ""

if ($DryRun -or $WhatIfPreference) {
    Write-Host "Dry run enabled. No folders were deleted." -ForegroundColor Yellow
    $logLines += "MODE: DRY RUN / WHATIF - No deletions performed."
    $logLines | Out-File -FilePath $logPath -Encoding UTF8
    Write-Host "Log saved to: $logPath" -ForegroundColor Cyan
    return
}

$totalCandidates = $targets.Count
$totalSizeBytes = ($targets | Measure-Object -Property SizeBytes -Sum).Sum
$logLines += "CANDIDATES: $totalCandidates folders ($(Convert-Size -Bytes $totalSizeBytes) total)"
$logLines += ""

$deleted = @()
$failed = @()

foreach ($target in $targets) {
    $sizeLabel = Convert-Size -Bytes $target.SizeBytes
    if ($PSCmdlet.ShouldProcess($target.FullPath, "Remove node_modules ($sizeLabel)")) {
        try {
            Remove-Item -LiteralPath $target.FullPath -Recurse -Force -ErrorAction Stop
            Write-Host "[OK] Deleted $target.FullPath ($sizeLabel)" -ForegroundColor Green
            $deleted += $target
            $logLines += "DELETED: $target.FullPath | $sizeLabel"
        } catch {
            Write-Warning "Failed to delete '$($target.FullPath)' ($($_.Exception.Message))"
            $failed += $target.FullPath
            $logLines += "FAILED: $($target.FullPath) -- $($_.Exception.Message)"
        }
    }
}

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Green
Write-Host "CLEANUP SUMMARY" -ForegroundColor Green
Write-Host ("=" * 80) -ForegroundColor Green
Write-Host "Candidates processed: $totalCandidates" -ForegroundColor White
Write-Host "Deleted folders:    $($deleted.Count)" -ForegroundColor Green
Write-Host "Failed deletions:   $($failed.Count)" -ForegroundColor ($(if ($failed.Count) { "Yellow" } else { "Green" }))
Write-Host "Estimated space freed: $(Convert-Size -Bytes (($deleted | Measure-Object -Property SizeBytes -Sum).Sum))" -ForegroundColor Green

if ($failed.Count) {
    Write-Host ""
    Write-Host "Failed paths:" -ForegroundColor Yellow
    $failed | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
}

$logLines += ""
$logLines += "SUMMARY: Deleted $($deleted.Count), Failed $($failed.Count), Estimated Freed $(Convert-Size -Bytes (($deleted | Measure-Object -Property SizeBytes -Sum).Sum))"
$logLines | Out-File -FilePath $logPath -Encoding UTF8
Write-Host ""
Write-Host "Log saved to: $logPath" -ForegroundColor Cyan
