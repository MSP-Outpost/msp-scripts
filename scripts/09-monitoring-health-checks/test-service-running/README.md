# Service stopped - monitor

> Alerts when a service you name is not running.

| | |
|---|---|
| Script | `test-service-running.ps1` |
| Type | Monitor |
| Category | Monitoring & health checks |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | Either |
| Requires | PowerShell 5.1 |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 10 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It looks up each service in Names, by service name or display name (wildcards * and ? work), and alerts (exit 1) when any of them is not Running. It writes one row per service found.

With OnlyAutomatic true (the default) a service whose start type is Manual or Disabled is shown but never alerts, because those services are meant to be stopped most of the time. A service that is stopped on purpose until something triggers it (some Automatic ones are "trigger start") will alert: leave those out of Names.

A name that matches no service is a warning, not an alert. When none of the names match anything on this PC the result is SKIPPED, because the software is not installed here.

The repair twin is restart-service.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Names` | Services to watch, separated by commas, e.g. "Spooler, MSSQLSERVER". Service names or display names; wildcards work. Required. | (empty) | `Names` or `NAMES` |
| `OnlyAutomatic` | true to alert only for services whose start type is Automatic (including delayed start). Default true. | `true` | `OnlyAutomatic` or `ONLY_AUTOMATIC` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-service-running.ps1 -Names "Spooler,W32Time"
```

Alerts if the Print Spooler or the Windows Time service is stopped.

```powershell
.\test-service-running.ps1 -Names "MSSQL*" -OnlyAutomatic false -OutputFormat Json
```

Alerts if any SQL Server service is not running, whatever its start type.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Names`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
1 service(s) not running: Spooler (Stopped)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Name`, `DisplayName`, `StartMode`, `State`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-service-running

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
