# How many days since this PC was patched

> Alerts when the last successful Windows update install is older than the number of days you set.

| | |
|---|---|
| Script | `test-patch-age.ps1` |
| Type | Monitor |
| Category | Patching & Windows Update |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1; Windows Update Agent |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 20 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It reads the Windows Update history through the Windows Update Agent (Microsoft.Update.Session) and finds the newest update that installed successfully. It alerts (exit 1) when that was more than MaxDays ago. The rows are the five newest history entries, including failed ones, so a stuck update is visible.

Only quality and security updates count (titles with Cumulative Update, Security Update, Monthly Rollup or Security Only; previews do not). Drivers, .NET and platform updates, antivirus definitions and the Malicious Software Removal Tool do not reset the clock. The date used is the newer of the history and Get-HotFix. When neither has anything the PC counts as unpatched since Windows was installed.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `MaxDays` | Alert when the last successful update install is older than this many days. Whole number, 0 to 3650. Default 35. 0 alerts on any age (useful for testing). | `35` | `MaxDays` or `MAX_DAYS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-patch-age.ps1 -MaxDays 45
```

Alerts when the PC has gone more than 45 days without a successful update.

```powershell
.\test-patch-age.ps1 -OutputFormat Json
```

Prints one JSON object with the five newest update entries.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `MaxDays`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Last patched 41 days ago (2026-10-06, KB5044284); limit 35
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Title`, `Date`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-patch-age

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
