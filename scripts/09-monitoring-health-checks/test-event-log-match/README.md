# Something is logging errors - event ID and text match monitor

> Alerts when events that match an event ID, source or text appear in a Windows event log.

| | |
|---|---|
| Script | `test-event-log-match.ps1` |
| Type | Monitor |
| Category | Monitoring & health checks |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1; administrator rights |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 20 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It reads one event log for the last LookbackMinutes and counts the events that match every filter you set: event IDs, providers (sources), a piece of the message text, and a severity. It alerts (exit 1) when the count is more than MaxEvents. The 25 newest matches are listed.

Set at least one of EventIds, Providers, MessageMatch, or a Level other than Any. A filter left empty is not applied. At most 5000 events are read per run; narrow the filters if that is not enough.

A Providers name that is not registered on the PC produces a WARNING (it may be misspelled) and the run still ends OK when nothing matched.

Message text is matched as plain text, ignoring case. An unknown LogName is an error, so a typo cannot pass as "no events".

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `LogName` | The event log to read, e.g. System, Application, Security or "Microsoft-Windows-TaskScheduler/Operational". Default System. | `System` | `LogName` or `LOG_NAME` |
| `EventIds` | Event IDs to match, separated by commas, e.g. "41, 6008". At most 20. Default any. | (empty) | `EventIds` or `EVENT_IDS` |
| `Providers` | Event sources to match, separated by commas, e.g. "disk, Ntfs". Wildcards - and ? work. Default any. | (empty) | `Providers` or `PROVIDERS` |
| `MessageMatch` | Text the event message must contain. Default any. | (empty) | `MessageMatch` or `MESSAGE_MATCH` |
| `Level` | Severity: Critical, Error (Critical and Error), Warning (Critical, Error and Warning) or Any. Default Error. | `Error` | `Level` or `LEVEL` |
| `LookbackMinutes` | How far back to read. Whole number, 1 to 43200. Default 60. | `60` | `LookbackMinutes` or `LOOKBACK_MINUTES` |
| `MaxEvents` | Alert when more than this many events match. Whole number, 0 to 100000. Default 0 (any match alerts). | `0` | `MaxEvents` or `MAX_EVENTS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-event-log-match.ps1 -EventIds "7034, 7031" -Providers "Service Control Manager" -Level Any
```

Alerts when a service crashed in the last hour.

```powershell
.\test-event-log-match.ps1 -LogName Application -MessageMatch "backup failed" -LookbackMinutes 1440
```

Alerts when an Application event from the last day mentions "backup failed".

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `LogName`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
3 matching events in System in the last 60 min; latest 7034 Service Control Manager
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `TimeUtc`, `Level`, `EventId`, `Provider`, `Message`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-event-log-match

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
