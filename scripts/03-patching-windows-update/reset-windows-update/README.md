# Windows Update stuck or failing - reset the update stack

> Resets the Windows Update stack: renames its caches, clears BITS jobs, restarts the services, starts a scan.

| | |
|---|---|
| Script | `reset-windows-update.ps1` |
| Type | Action |
| Category | Patching & Windows Update |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | Stops and starts the update services; renames SoftwareDistribution and catroot2; cancels BITS jobs; deletes older .old-* copies |
| Risk | Low |
| Reboot | Never |
| Typical runtime | 1 to 3 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS. It:

- records the state of the Windows Update (wuauserv), BITS (bits), Cryptographic (cryptsvc) and Windows Installer (msiserver) services, and stops them,
- renames C:\Windows\SoftwareDistribution and C:\Windows\System32\catroot2 to <name>.old-<yyyyMMddHHmmss>. It renames; it never deletes the copy it just made, so the reset can be rolled back by hand,
- starts wuauserv, bits and cryptsvc, puts msiserver back as it was, and checks they run,
- cancels every BITS transfer job (other programs' downloads restart on their own),
- asks Windows to scan for updates (UsoClient StartScan) when present.

With ClearOldBackups (default true) it then deletes older SoftwareDistribution.old-* and catroot2.old-* copies from earlier runs, keeping only the one just made. Windows Update history shown in Settings starts empty after a reset and rebuilds on the next scan. Installed updates are not touched.

It does not re-register DLLs, reset Winsock or edit service permissions. Do not run it while an update is installing; wait or reboot first.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `ClearOldBackups` | true to delete .old-* copies from earlier runs, keeping the newest one. Default true. | `true` | `ClearOldBackups` or `CLEAR_OLD_BACKUPS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\reset-windows-update.ps1 -DryRun true
```

Lists the renames and service restarts it would make.

```powershell
.\reset-windows-update.ps1 -ClearOldBackups false
```

Resets the stack and keeps the .old-* copies from earlier runs.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `ClearOldBackups`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Reset the update stack: SoftwareDistribution and catroot2 renamed; 3 services running; scan requested
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\reset-windows-update.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/reset-windows-update

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
