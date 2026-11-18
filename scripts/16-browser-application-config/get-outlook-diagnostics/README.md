# Outlook slow or crashing - first-aid report

> Outlook first-aid report: Office build and channel, profiles, OST and PST files, add-ins and recent crashes.

| | |
|---|---|
| Script | `get-outlook-diagnostics.ps1` |
| Type | Report |
| Category | Browser & application config |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1; a signed-in user for the profile, file and add-in sections |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It reports what a technician checks first when classic Outlook is slow, hangs or crashes:

- Office version, update channel and Outlook.exe build (from the Click-to-Run configuration, or the installed file for an MSI install),
- the signed-in user's Outlook profiles, the default profile and how many accounts each holds,
- OST and PST files with their sizes: an OST over OstWarningGB (default 50 GB) is flagged because Outlook slows and can corrupt, and a PST or OST on a network path is flagged because Microsoft does not support it,
- Cached Exchange Mode: the Cached Mode policy value, and whether an OST exists (an OST means Outlook is working from a local cache),
- COM add-ins with their LoadBehavior, and the ones Outlook disabled itself (Resiliency: DisabledItems, CrashingAddinList and any list with Slow in its name),
- Outlook crashes (Application Error, event 1000) and hangs (Application Hang, event 1002) in the last CrashDays days, newest first, up to 10.

The user's registry and folders are read in the signed-in user's session (Invoke-OutpostAsUser); the Office install and the event log are read as SYSTEM. With nobody signed in the user part is left out with a WARNING.

It covers classic Outlook (OUTLOOK.EXE). The new Outlook for Windows is not covered. Outlook not installed ends SKIPPED. The Flagged column marks what to look at first.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `OstWarningGB` | Flag an OST or NST file larger than this many GB. Whole number, 1 to 10000. Default 50. | `50` | `OstWarningGB` or `OST_WARNING_GB` |
| `CrashDays` | Look back this many days for Outlook crashes and hangs. Whole number, 1 to 365. Default 14. | `14` | `CrashDays` or `CRASH_DAYS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-outlook-diagnostics.ps1
```

Reports on Outlook for the signed-in user.

```powershell
.\get-outlook-diagnostics.ps1 -OstWarningGB 30 -CrashDays 30 -ExportPath C:\Temp\outlook.csv
```

Flags OST files over 30 GB, looks back 30 days and also saves the rows as CSV.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `OstWarningGB`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Outlook 16.0.17328.20162 (Current Channel); 1 profile(s); OST 3.2 GB; 1 add-in disabled; 2 crashes in 14 days
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Section`, `Item`, `Value`, `Flagged`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/get-outlook-diagnostics

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
