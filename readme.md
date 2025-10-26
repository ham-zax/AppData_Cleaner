# AppData Cleanup Toolkit

PowerShell scripts to reclaim disk space: orphaned AppData folders, `node_modules`, temp files, and package caches.

## Quick Start

```powershell
# Set execution policy (first time only)
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

# Clean orphaned AppData (interactive)
.\Clean-AppData_interactive.ps1

# Clean node_modules everywhere (auto-discovers drives)
.\Clean-NodeModules.ps1 -DryRun

# Clean temp files and caches
.\Clean-TempFiles.ps1 -DryRun
```

---

## Scripts Overview

| Script | What It Does | When To Use |
|--------|--------------|-------------|
| **Clean-AppData_interactive.ps1** | Finds orphaned AppData folders with menu-driven selection | Daily cleanup, safe exploration |
| **Clean-NodeModules.ps1** | Removes `node_modules` across all drives | Before backups, freeing dev space |
| **Clean-TempFiles.ps1** | Clears Windows temp, browser/IDE caches | Quick space recovery |
| **Clean-AppData.old.ps1** | Legacy automation script with `-WhatIf` | Scheduled tasks, scripts |

**Requirements:** Windows 10/11, PowerShell 5.1+, standard user rights

---

## 1. Clean-AppData_interactive.ps1

**Interactive menu to review and delete orphaned application data folders.**

### Basic Usage
```powershell
.\Clean-AppData_interactive.ps1                    # Interactive mode
.\Clean-AppData_interactive.ps1 -MinSizeMB 50      # Only show folders > 50 MB
.\Clean-AppData_interactive.ps1 -AutoDelete        # Skip menu (dangerous!)
```

### Key Features
- ✅ 40+ vendor whitelist (Microsoft, NVIDIA, Steam, Adobe, etc.)
- ✅ Fuzzy matching against installed programs
- ✅ Menu-driven: toggle selections, review before delete
- ✅ Logs: `AppDataCleanup_yyyyMMdd_HHmmss.log` in user profile

### Parameters
- `-MinSizeMB` (default: 1) – Minimum folder size
- `-AdditionalWhitelist` – Protect custom folders
- `-AutoDelete` – Skip interactive menu (use with caution)

---

## 2. Clean-NodeModules.ps1

**Recursively finds and removes `node_modules` folders across drives.**

### Basic Usage
```powershell
.\Clean-NodeModules.ps1 -DryRun                    # Preview only
.\Clean-NodeModules.ps1                             # Delete (with confirmation)
.\Clean-NodeModules.ps1 -Roots 'D:\','E:\'         # Scan specific drives
.\Clean-NodeModules.ps1 -MaxDepth 2                 # Limit recursion depth
```

### Auto-Discovery (No `-Roots` Specified)
Scans automatically:
- User dirs: Desktop, Documents, Downloads, OneDrive, Projects, Code, dev, repos, GitHub
- Secondary drives: Entire D:–Z: drive roots
- Current working directory

### Key Features
- ✅ Deduplicates nested `node_modules` (keeps highest-level only)
- ✅ Parallel scanning and depth limits
- ✅ Logs: `NodeModulesCleanup_yyyyMMdd_HHmmss.log`

### Parameters
- `-Roots` (default: auto) – Scan paths
- `-MaxDepth` (default: -1 unlimited) – Recursion limit
- `-DryRun` – Preview without deletion

---

## 3. Clean-TempFiles.ps1

**Clears Windows temp, browser caches, and package manager caches.**

### Basic Usage
```powershell
.\Clean-TempFiles.ps1 -DryRun                      # Preview
.\Clean-TempFiles.ps1                               # Standard cleanup
.\Clean-TempFiles.ps1 -Aggressive                   # Include package caches (requires confirmation)
.\Clean-TempFiles.ps1 -MinimumSizeMB 10             # Only folders > 10 MB
```

### What Gets Cleaned

| Mode | Targets |
|------|---------|
| **Standard** | Windows temp (`%TEMP%`, `%WINDIR%\Temp`), browser caches (Chrome, Edge, Firefox, Brave), crash dumps, thumbnails |
| **Aggressive** | Standard + npm cache (`.npm\_cacache`), Cargo cache, NuGet v3-cache, Gradle cache, JetBrains caches, VS component cache |

⚠️ **Aggressive mode requires confirmation** – targets package manager caches (safe but causes re-downloads)

### Key Features
- ✅ Parallel deletion (PS 7+) for 2–3x speedup
- ✅ Gracefully skips locked files (e.g., open browser)
- ✅ Admin check with warnings
- ✅ Logs: `TempCleanup_yyyyMMdd_HHmmss.log`

### Parameters
- `-Aggressive` – Include package caches
- `-DryRun` – Preview only
- `-MinimumSizeMB` (default: 1) – Size threshold
- `-NoParallel` – Disable parallel deletion

---

## Common Workflows

### First-Time Setup
```powershell
# Enable script execution
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

# Preview everything
.\Clean-AppData_interactive.ps1       # Interactive review
.\Clean-NodeModules.ps1 -DryRun       # Preview node_modules
.\Clean-TempFiles.ps1 -DryRun         # Preview temp files
```

### Weekly Cleanup
```powershell
# Quick temp cleanup
.\Clean-TempFiles.ps1

# Review AppData (if space low)
.\Clean-AppData_interactive.ps1-MinSizeMB 50
```

### Pre-Backup
```powershell
# Max space recovery
.\Clean-NodeModules.ps1               # Clears dev dependencies
.\Clean-TempFiles.ps1 -Aggressive     # Clears all caches
```

### Scheduled Task (Automation)
```powershell
.\Clean-AppData.old.ps1 -MinSizeMB 100 -WhatIf -Verbose  # Preview
.\Clean-TempFiles.ps1 -Confirm:$false                     # Auto-run
```

---

## Safety Features

| Feature | Description |
|---------|-------------|
| **Dry-Run Modes** | Preview before deletion (all scripts) |
| **Whitelisting** | Protected system/vendor folders |
| **Fuzzy Matching** | Matches folder ↔ installed app names |
| **Confirmation** | Interactive/explicit prompts |
| **Logging** | Timestamped, detailed logs |
| **Locked File Handling** | Skips in-use files gracefully |

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| "Execution policy" error | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| "Access denied" | Close apps using the folder, or skip with warning |
| Too many folders flagged | Increase `-MinSizeMB`, add to `-AdditionalWhitelist` |
| Parallel deletion errors | Use `-NoParallel` (PS 5.1) or upgrade to PS 7+ |

---

## Advanced Examples

```powershell
# AppData: Large folders only, auto-delete
.\Clean-AppData_interactive.ps1 -MinSizeMB 100 -AutoDelete

# node_modules: Specific drives, depth limit
.\Clean-NodeModules.ps1 -Roots 'E:\Projects','F:\Work' -MaxDepth 3

# Temp: Aggressive with size threshold
.\Clean-TempFiles.ps1 -Aggressive -MinimumSizeMB 50

# Legacy: Scheduled task with logging
.\Clean-AppData.old.ps1 -MinSizeMB 100 -Confirm:$false -Verbose
```

---

## Contributing

Found a bug or want to add a feature? PRs welcome!

## License

MIT
