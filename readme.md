# AppData Cleanup Toolkit

PowerShell scripts that help reclaim disk space by removing orphaned AppData folders and purging stale `node_modules` directories across your drives. The interactive AppData workflow is safe-by-default and guides you through every deletion, while legacy and auxiliary automation scripts remain available for power users.

## 🎯 Highlights

- Scans both AppData roots for folders left behind by uninstalled software
- Sweeps nested `node_modules` directories across multiple roots with depth limits
- Cross-references fuzzy matches against installed programs and Windows Store apps
- Ships with an extensive whitelist to guard system and common vendor folders
- Provides interactive selection, deletion previews, and detailed logs
- Works entirely with standard user permissions—no elevation required

## ⚙️ Requirements

- Windows 10 or Windows 11 (or equivalent Windows Server build)
- PowerShell 5.1 or later (preinstalled on supported systems)
- Standard user rights (script touches only your user profile)

## 📦 Scripts at a Glance

| Script | Purpose | Best For |
|--------|---------|----------|
| `Clean-AppData_interactive.ps1` | Interactive cleanup with menu-driven selection and optional auto-delete mode | Day-to-day manual cleanups |
| `Clean-NodeModules.ps1` | Recursive `node_modules` cleanup with dry-run logging and ShouldProcess support | Repo hygiene across drives |
| `Clean-AppData.old.ps1` | Non-interactive (WhatIf/Confirm) cleanup kept for backwards compatibility or automation | Scheduled tasks / power users |

## 🚀 Quick Start (Interactive Script)

1. **Download** `Clean-AppData_interactive.ps1` to a safe directory, e.g. `E:\My Documents\AppData_Cleaner`.
2. **Open** a non-admin PowerShell window and change to that folder:
   ```powershell
   cd "E:\My Documents\AppData_Cleaner"
   ```
3. **Adjust execution policy** if you have not previously enabled script execution:
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   ```
4. **Run the interactive scan** (default mode):
   ```powershell
   .\Clean-AppData_interactive.ps1
   ```
5. **Review the menu**:
   - Toggle individual folders by typing their number
   - Use `A` (select all), `N` (select none), `S` (show selection)
   - Type `D` then confirm with `DELETE` to remove the selected folders

The script saves a log named `AppDataCleanup_yyyyMMdd_HHmmss.log` in your user profile directory (e.g. `C:\Users\YourName`). Each entry records success/failure and folder sizes for easy auditing.

## 🔧 Parameter Reference (`Clean-AppData_interactive.ps1`)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-MinSizeMB` | Double | `1` | Minimum folder size (in MB) to consider during scanning |
| `-AdditionalWhitelist` | String[] | `@()` | Custom folder names to permanently protect (case-insensitive) |
| `-AutoDelete` | Switch | `False` | Skips the menu and deletes every orphaned folder found (dangerous—review logs first) |

### Auto-delete example

```powershell
.\Clean-AppData_interactive.ps1 -MinSizeMB 50 -AutoDelete
```

Use this mode only after validating the results interactively; it removes every candidate without prompting.

## 🧭 Interactive Workflow Notes

- All folders start **selected** for deletion to speed up review.
- Selections persist until you confirm or quit, enabling batch toggling.
- The script computes both estimated reclaimed size and the actual delta in free space on drive `C:` to highlight discrepancies caused by other system activity.

## 📁 Node Modules Cleanup Script (`Clean-NodeModules.ps1`)

Use this standalone utility to reclaim space consumed by accumulated `node_modules` folders across multiple repositories.

1. Save `Clean-NodeModules.ps1` alongside your other maintenance scripts.
2. Run a dry preview from any PowerShell window (no elevation required):
   ```powershell
   .\Clean-NodeModules.ps1 -Roots 'D:\Projects','E:\Playground' -DryRun
   ```
3. Inspect the summary table and log (`NodeModulesCleanup_yyyyMMdd_HHmmss.log`) created in your user profile or chosen `-LogDirectory`.
4. Re-run without `-DryRun` (or with `-Confirm:$false`) once you are confident in the candidate list.

### Parameter Reference (`Clean-NodeModules.ps1`)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Roots` | String[] | User profile (Desktop, Documents, Downloads, OneDrive, etc.) | One or more starting points to scan recursively |
| `-MaxDepth` | Int | `-1` | Limits recursion depth relative to each root (`-1` means unlimited) |
| `-DryRun` | Switch | `False` | Skips deletion and prints a preview (equivalent to `-WhatIf`) |
| `-LogDirectory` | String | User profile | Destination for the cleanup log; created automatically |

**Default Behavior (No `-Roots` Specified)**

The script auto-discovers scan locations:

1. **User profile directories:** Desktop, Documents, Downloads, OneDrive, source, repos, Projects, Code, dev, Development, Work, workspace, GitHub, git, Web, wwwroot
2. **Current working directory** (if not already included)
3. **Secondary drives (D:–Z:):** Scans the **entire drive root** for comprehensive coverage, plus specific common folders (dev, Projects, Repos, Code, source) for targeted cleanup

This ensures comprehensive coverage across all user directories and secondary drives without requiring manual path entry.

**Tips**

- Override defaults by passing explicit roots: `.\Clean-NodeModules.ps1 -Roots 'D:\','E:\'`
- The script deduplicates nested `node_modules` candidates so only the highest-level folder in each branch is deleted.
- Combine `-DryRun` (or `-WhatIf`) with `-MaxDepth` to preview before deletion.
- Use `-MaxDepth 1` to target only top-level dependencies (e.g., monorepo roots).

## 🛡️ Safety Features

1. **Extensive Whitelist** – 40+ protected vendors and system folders (Microsoft, NVIDIA, Steam, Adobe, Logitech, etc.) plus anything you pass through `-AdditionalWhitelist`.
2. **Size Threshold** – Ignores folders under `1 MB` unless you lower the threshold.
3. **Fuzzy Matching** – Bidirectional wildcard and word-level matching catches common naming differences between folders and installed programs.
4. **Interactive Confirmation** – Default mode requires explicit confirmation before deletions occur.
5. **Comprehensive Logging** – Every scan writes timestamped details (folders scanned, skipped reasons, deletions, failures) to the log file.

## 🧰 Legacy Automation Script (`Clean-AppData.old.ps1`)

The original script remains available when you prefer PowerShell’s native `-WhatIf` / `-Confirm` semantics or need to embed the cleanup into scheduled jobs. Key usage patterns:

```powershell
# Dry run preview
.\Clean-AppData.old.ps1 -WhatIf

# Verbose output with confirmation prompts
.\Clean-AppData.old.ps1 -Verbose -Confirm

# Focus on large folders and log details
.\Clean-AppData.old.ps1 -MinSizeMB 100 -Verbose -WhatIf
```

> **Tip:** The old script writes logs to your Desktop by default and honours `SupportsShouldProcess`, making it convenient for automation.

## 🛠️ Troubleshooting

| Symptom | Resolution |
|---------|------------|
| *Execution policy error* | Run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| *Access denied deleting folder* | Close apps using that folder or rerun later; entries remain in the log |
| *Many unexpected folders flagged* | Increase `-MinSizeMB`, use `-Verbose`, or extend the whitelist |
| *Strange characters in console* | Force UTF-8 output: ` [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 ` |
| *Actual space freed shows 0* | Another process may consume space simultaneously; rely on calculated freed space column |

## 🔄 Version History

- **v2.1** – New interactive menu, optional auto-delete switch, log saved to user profile root, enhanced statistics.
- **v2.0** – Bidirectional fuzzy matching, expanded whitelist, Windows Store app detection, improved logging.
- **v1.x** – Original non-interactive script (now archived as `Clean-AppData.old.ps1`).

---

Happy cleaning! 🧹
