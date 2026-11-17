# PC crashed or blue-screened - unexpected shutdown monitor

> Alerts when the PC crashed, blue-screened or lost power in the last few days.

| | |
|---|---|
| Script | `test-unexpected-shutdown.ps1` |
| Type | Monitor |
| Category | Monitoring & health checks |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1; administrator rights |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 15 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It reads the System event log for the last LookbackDays and counts three kinds of event: Kernel-Power 41 (the PC restarted without a clean shutdown), EventLog 6008 (the previous shutdown was unexpected) and BugCheck 1001 (a blue screen). It alerts (exit 1) when the count is more than MaxEvents.

One crash usually writes all three events, so a single blue screen counts as three. The bugcheck code (for example 0x0000009f) is shown when the event carries one. The 50 newest events are listed.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `LookbackDays` | How many days of the System log to read. Whole number, 1 to 365. Default 7. | `7` | `LookbackDays` or `LOOKBACK_DAYS` |
| `MaxEvents` | Alert when more than this many events are found. Whole number, 0 to 100000. Default 0 (any event alerts). | `0` | `MaxEvents` or `MAX_EVENTS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-unexpected-shutdown.ps1 -LookbackDays 14
```

Alerts when any crash event is found in the last 14 days.

```powershell
.\test-unexpected-shutdown.ps1 -MaxEvents 3 -OutputFormat Json
```

Tolerates one crash (three events) and prints one JSON object.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `LookbackDays`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
3 crash events in 7 days; latest 2026-11-14 bugcheck 0x0000009f
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `TimeUtc`, `EventId`, `Source`, `Detail`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-unexpected-shutdown

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
