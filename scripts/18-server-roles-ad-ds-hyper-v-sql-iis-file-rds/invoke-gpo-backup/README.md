# Back up all GPOs with HTML reports

> Backs up every Group Policy Object to a dated folder with an HTML report per GPO, and keeps the newest N backups.

| | |
|---|---|
| Script | `invoke-gpo-backup.ps1` |
| Type | Action |
| Category | Server roles (AD DS, Hyper-V, SQL, IIS, file, RDS) |
| Platforms | Windows Server 2016+ (DC, or a member with GPMC) |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, GroupPolicy module (GPMC), rights to read all GPOs |
| Changes | Creates a dated backup folder with the GPO backups and HTML reports, and deletes this script's own backups beyond KeepBackups |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 2 minutes for 100 GPOs |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## What it does

THIS SCRIPT CHANGES THINGS (it adds files and deletes its own old backups; it never changes a GPO). It does this, in order:

1. Reads every GPO (Get-GPO -All) with its modification time and its user and computer version numbers.
2. Compares them with the newest backup this script made. When no GPO was added, removed or changed since, it stops: OK "Already backed up". Set ForceBackup=true to back up anyway.
3. Makes a new folder named for the UTC time (yyyyMMdd-HHmmss) under BackupFolder and runs Backup-GPO -All into it (one {id} folder per GPO and manifest.xml, which Import-GPO and Restore-GPO read).
4. Unless IncludeReports is false, writes one HTML report per GPO (Get-GPOReport) into the Reports folder inside the new backup.
5. Checks the backup holds one folder per GPO (and one report per GPO), then writes outpost-gpo-backup.json, the list of GPO ids, names, times and versions, which marks the folder as complete and is what step 2 compares with next time.
6. Deletes the oldest backups so that KeepBackups remain. Only folders that are named like a dated backup AND hold outpost-gpo-backup.json are ever deleted; anything else in BackupFolder is left alone.

Risk is Low because nothing outside the backup folder is changed and the deleted folders are this script's own old backups. Schedule it daily.

Where it goes: BackupFolder, default %ProgramData%\MSPOutpost\GpoBackups on the machine that runs it. That folder is readable by local users like the rest of MSPOutpost; GPO content is readable by every domain user in SYSVOL anyway, but a GPO can hold scripts or settings you want kept private: point BackupFolder at a protected folder or share for real use. Copy backups off the server: a backup on the machine it protects is not a backup.

Run it on a domain controller or a member server with the Group Policy Management feature (GPMC, module GroupPolicy). Without the module it ends ERROR; on a computer that is not in a domain it ends SKIPPED.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `BackupFolder` | The folder that holds the dated backups. Absolute path. Default empty: %ProgramData%\MSPOutpost\GpoBackups. Created when missing. | (empty) | `BackupFolder` or `BACKUP_FOLDER` |
| `KeepBackups` | How many dated backups to keep (this one included). Whole number 1 to 365. Default 14. | `14` | `KeepBackups` or `KEEP_BACKUPS` |
| `IncludeReports` | true to write an HTML report per GPO. Default true. | `true` | `IncludeReports` or `INCLUDE_REPORTS` |
| `ForceBackup` | true to back up even when no GPO changed since the last backup. Default false. | `false` | `ForceBackup` or `FORCE_BACKUP` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\invoke-gpo-backup.ps1 -BackupFolder D:\GpoBackups -KeepBackups 30
```

Backs up all GPOs to a new dated folder in D:\GpoBackups and keeps 30 backups.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `BackupFolder`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Backed up 24 GPO(s) with 24 HTML report(s) to 20261119-020000; kept 14 backup(s), removed 1 old
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\invoke-gpo-backup.log`.

## Changelog

- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/invoke-gpo-backup

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
