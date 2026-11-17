# PC never rebooted - uptime and pending-reboot monitor

> Alerts when a PC has not restarted in too many days or is waiting for a restart.

| | |
|---|---|
| Script | `test-pending-reboot.ps1` |
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

THIS SCRIPT IS READ-ONLY. It reads the time of the last boot and every place Windows records that a restart is pending: component servicing (CBS), Windows Update, queued file renames, the Configuration Manager client (only when its service is present) and a pending computer rename. It writes one row per check and alerts (exit 1) when uptime is over MaxUptimeDays, or when a restart is pending and AlertOnPendingReboot is true.

Fast Startup: when Fast Startup is on, Shut down does not reset the uptime clock; only Restart does. The Fast Startup row says which applies. Queued file renames (PendingFileRenameOperations) are set permanently on many healthy PCs by antivirus and drivers, so they are listed but do not alert unless IncludeFileRenames is true. Set AlertOnPendingReboot to false to watch uptime only.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `MaxUptimeDays` | Alert when the PC has been up longer than this many days. Whole number, 0 to 3650. Default 14. 0 alerts on any uptime (useful for testing). | `14` | `MaxUptimeDays` or `MAX_UPTIME_DAYS` |
| `AlertOnPendingReboot` | Alert when a restart is pending. true or false. Default true. | `true` | `AlertOnPendingReboot` or `ALERT_ON_PENDING_REBOOT` |
| `IncludeFileRenames` | Also alert when file renames are queued for the next restart. true or false. Default false. | `false` | `IncludeFileRenames` or `INCLUDE_FILE_RENAMES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-pending-reboot.ps1 -MaxUptimeDays 21
```

Alerts when the PC has been up more than 21 days or a restart is pending.

```powershell
.\test-pending-reboot.ps1 -AlertOnPendingReboot false -OutputFormat Json
```

Watches uptime only and prints one JSON object.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `MaxUptimeDays`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Up 23 days (limit 14); reboot pending (Windows Update)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Check`, `Value`, `Pending`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-pending-reboot

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
