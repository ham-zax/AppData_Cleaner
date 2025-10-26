# AppData Cleanup Script

A safe and intelligent PowerShell script to identify and remove orphaned application data folders in Windows AppData directories.

## 🎯 What Does It Do?

Over time, Windows accumulates leftover folders in `AppData\Local` and `AppData\Roaming` from uninstalled applications. This script:

- Scans both AppData directories for orphaned folders
- Compares folder names against currently installed applications
- Protects system and common folders with a comprehensive whitelist
- Provides detailed logging and safe deletion options
- Can reclaim gigabytes of wasted disk space

## ⚙️ Requirements

- **Windows 10/11** (or Windows Server)
- **PowerShell 5.1+** (comes pre-installed)
- **NO admin rights required** - runs with standard user permissions
- Script operates only on current user's AppData folders

## 📋 Quick Start Guide

### Step 1: Download and Prepare

1. Save `Clean-AppData.ps1` to a folder (e.g., `E:\Scripts`)
2. Open PowerShell (regular, not admin)
3. Navigate to the script folder:
   ```powershell
   cd "E:\My Documents\AppData_Cleaner"
   ```

### Step 2: Enable Script Execution (First Time Only)

If you get an execution policy error, run:
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```
Type `Y` and press Enter.

### Step 3: Run in Preview Mode (RECOMMENDED)

**Always start with `-WhatIf` to see what would be deleted:**
```powershell
.\Clean-AppData.ps1 -WhatIf -Verbose
```

This shows you:
- Which folders would be deleted
- How much space you'd reclaim
- NO actual deletions occur

### Step 4: Review the Results

- Check the console output carefully
- Review the log file saved to your Desktop
- Look for any folders you recognize and want to keep

### Step 5: Add Custom Whitelist (Optional)

If you see folders that should NOT be deleted, add them:
```powershell
.\Clean-AppData.ps1 -WhatIf -AdditionalWhitelist @('MyApp', 'ImportantFolder')
```

### Step 6: Run the Actual Cleanup

Once satisfied with the preview:
```powershell
.\Clean-AppData.ps1
```

Or for individual confirmation per folder:
```powershell
.\Clean-AppData.ps1 -Confirm
```

## 📖 Usage Examples

### Basic Dry Run
```powershell
.\Clean-AppData.ps1 -WhatIf
```
Shows what would be deleted without actually deleting anything.

### Detailed Preview
```powershell
.\Clean-AppData.ps1 -WhatIf -Verbose
```
Shows detailed scanning process with matching logic.

### Only Large Folders
```powershell
.\Clean-AppData.ps1 -MinSizeMB 50 -WhatIf
```
Only considers folders larger than 50 MB.

### Custom Whitelist
```powershell
.\Clean-AppData.ps1 -AdditionalWhitelist @('OBS', 'MyCustomApp') -WhatIf
```
Protects specific folders from deletion.

### Delete with Confirmation
```powershell
.\Clean-AppData.ps1 -Confirm
```
Prompts you to approve each deletion individually.

### Silent Deletion (Advanced)
```powershell
.\Clean-AppData.ps1 -Confirm:$false
```
Deletes all orphaned folders without prompting. **Use with caution!**

## 🛡️ Safety Features

### 1. Comprehensive Whitelist
The script protects 40+ common system and publisher folders:
- Microsoft, Windows, NVIDIA, Intel, AMD, Google
- Steam, Discord, Spotify, Adobe, Mozilla
- Hardware manufacturers (Dell, HP, Logitech, etc.)

### 2. Size Threshold
By default, only folders **≥ 1 MB** are considered (configurable with `-MinSizeMB`).

### 3. Intelligent Matching
- Bidirectional fuzzy matching (folder ↔ app name)
- Word-level comparison for complex names
- Checks both Registry and Windows Store apps

### 4. Built-in PowerShell Safety
- `-WhatIf`: Preview mode (no actual changes)
- `-Confirm`: Prompts before each deletion
- Error handling for in-use or protected folders

### 5. Detailed Logging
Every scan creates a timestamped log on your Desktop with:
- Complete list of orphaned folders
- Scan statistics
- Matching details (verbose mode)

## 🚫 Do I Need Admin Rights?

**NO!** This script does **NOT** require administrator privileges because:

- It only accesses your user's AppData folders
- These folders are owned by your user account
- No system-wide changes are made
- No registry modifications

**When you might need admin:**
- If you want to clean AppData for OTHER users (not recommended)
- If specific folders have unusual permission issues (rare)

In 99% of cases, run as a **regular user**.

## 📊 Understanding the Output

### Console Output
```
Found 3 potential orphaned folders
Total reclaimable space: 1,234.56 MB (1.23 GB)

⚠️  REVIEW THIS LIST CAREFULLY BEFORE DELETING ⚠️

Size (MB)  Location  Folder Name
---------  --------  -----------
   856.32  Local     OldGameEngine
   234.12  Roaming   UninstalledApp
   144.12  Local     AbandonedTool
```

### Log File Location
```
Desktop\AppDataCleanup_20251026_143052.log
```

### Scan Statistics
- **Total Folders Scanned**: All folders checked
- **Whitelisted**: Protected by safety list
- **Too Small**: Below size threshold
- **Matched to Apps**: Found corresponding installed app
- **Potential Orphans**: Candidates for deletion

## ⚠️ Important Notes

### What Gets Deleted
- Folders with NO matching installed application
- NOT on the whitelist
- Larger than the size threshold (default 1 MB)

### What's Protected
- All whitelisted system/common folders
- Folders matching installed apps
- Folders smaller than threshold
- Folders added via `-AdditionalWhitelist`

### False Positives
The script is conservative, but may miss matches if:
- App names differ significantly from folder names
- Portable apps (not in registry or Store)
- Custom/renamed installations

**Always review with `-WhatIf` first!**

### Recovering Deleted Folders
- Check your **Recycle Bin** (folders may be recoverable)
- Use the log file to see what was deleted
- Consider backup software for important data

## 🐛 Troubleshooting

### "Execution Policy" Error
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

### "Access Denied" Errors
- Normal for folders in use by running programs
- Close applications and retry
- Some system folders may be protected (script skips them)

### Script Finds Nothing
Your AppData is already clean! Reasons:
- Recent Windows installation
- Regular manual cleanup
- Most apps properly uninstall

### Script Finds Too Much
- Increase `-MinSizeMB` to focus on larger folders
- Add folders to whitelist: `-AdditionalWhitelist @('Folder1', 'Folder2')`
- Review with `-Verbose` to understand matching

### Strange Characters in Output
PowerShell encoding issue. Run:
```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
```

## 📝 Parameters Reference

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-MinSizeMB` | Double | 1 | Minimum folder size in MB to consider |
| `-AdditionalWhitelist` | String[] | Empty | Custom folders to protect |
| `-WhatIf` | Switch | False | Preview mode (no actual deletions) |
| `-Confirm` | Switch | False | Prompt before each deletion |
| `-Verbose` | Switch | False | Detailed output during scanning |

## 🔧 Advanced Usage

### Clean AppData for Specific Apps
If you want to remove data from specific uninstalled apps:
1. Run with `-WhatIf -Verbose`
2. Find the app folders in the output
3. Manually delete those specific folders

### Automated Cleanup (Advanced)
Add to Task Scheduler for monthly cleanup:
```powershell
.\Clean-AppData.ps1 -MinSizeMB 100 -Confirm:$false
```
**Warning**: Only do this after testing thoroughly!

### Integration with Other Scripts
```powershell
# Get orphaned folders for custom processing
$orphans = .\Clean-AppData.ps1 -WhatIf | Out-String
```

## 📄 License & Disclaimer

This script is provided as-is without warranty. While designed with safety in mind:
- Always review with `-WhatIf` before deleting
- Keep backups of important data
- The author is not responsible for accidental data loss
- Use at your own risk

## 🆘 Support

If you encounter issues:
1. Run with `-WhatIf -Verbose` and check the log
2. Verify PowerShell version: `$PSVersionTable.PSVersion`
3. Check if specific folders are in use by running programs
4. Review the whitelist to ensure important folders are protected

## 🔄 Version History

**v2.0** (Current)
- Enhanced bidirectional matching logic
- Added Windows Store app detection
- Expanded whitelist (40+ entries)
- Improved error handling and logging
- Better user experience with color-coded output

---

**Happy Cleaning!** 🧹✨