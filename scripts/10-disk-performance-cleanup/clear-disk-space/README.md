# Disk full first aid - silent cleanup

> Frees disk space on the system drive by clearing temp files, update and crash leftovers, and (on request) browser caches and the Recycle Bin.

| | |
|---|---|
| Script | `clear-disk-space.ps1` |
| Type | Action |
| Category | Disk, performance & cleanup |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | Deletes temp, update-cache, crash-dump and error-report files; optionally browser caches and DISM component leftovers; briefly stops and restarts Windows Update |
| Risk | Low |
| Reboot | Never |
| Typical runtime | 1 to 10 minutes (longer with ComponentCleanup) |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS. It looks at these places, measures what it could free, and (when at least MinimumMB would be freed) deletes:

- Windows\Temp and every user's AppData\Local\Temp,
- the Windows Update download cache (SoftwareDistribution\Download): it stops the Windows Update service first and puts it back as it found it,
- the Delivery Optimization cache (Delete-DeliveryOptimizationCache),
- crash dumps (Windows\Minidump and MEMORY.DMP),
- Windows Error Reporting queues and archives,
- only with IncludeBrowserCaches: the cache folders of Chrome, Edge and Firefox in every profile (never cookies, passwords or history),
- only with ComponentCleanup: DISM component store cleanup (slow; its size is only known afterwards).

Files are only deleted when they have not changed for MinAgeDays days (the Delivery Optimization and DISM steps take everything). It never empties the Recycle Bin: that is users' data. A file that is in use is skipped silently and counted. It never touches documents, desktops, downloads, application settings or installed programs.

The table has one row per category. The answer says how much was freed on the system drive and the free space before and after. When less than MinimumMB would be freed it changes nothing and says so.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `MinAgeDays` | Only delete files that have not been modified for at least this many days, so files a program is using right now survive. Whole number, 0 to 3650. Default 2. | `2` | `MinAgeDays` or `MIN_AGE_DAYS` |
| `MinimumMB` | Do nothing unless at least this many MB can be freed. Whole number, 0 to 1048576. Default 50. | `50` | `MinimumMB` or `MINIMUM_MB` |
| `IncludeBrowserCaches` | true to also clear the Chrome, Edge and Firefox cache folders of every profile. Default false. | `false` | `IncludeBrowserCaches` or `INCLUDE_BROWSER_CACHES` |
| `ComponentCleanup` | true to also run DISM component store cleanup (can take many minutes). Default false. | `false` | `ComponentCleanup` or `COMPONENT_CLEANUP` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\clear-disk-space.ps1 -DryRun true
```

Shows what a cleanup would delete and how much it would free.

```powershell
.\clear-disk-space.ps1 -MinAgeDays 7 -IncludeBrowserCaches true
```

Also clears browser caches, but only files untouched for a week.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `MinAgeDays`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Freed 6.2 GB on C: (was 4% free, now 9%)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\clear-disk-space.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/clear-disk-space

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
