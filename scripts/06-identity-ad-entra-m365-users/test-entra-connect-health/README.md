# Entra Connect server health

> Alerts when the Microsoft Entra Connect server's sync service is down, stale, failing, in the wrong mode or out of date.

| | |
|---|---|
| Script | `test-entra-connect-health.ps1` |
| Type | Monitor |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows Server 2016+ (the Microsoft Entra Connect server) |
| Runs as | System |
| Requires | PowerShell 5.1; administrator rights; Microsoft Entra Connect installed (module ADSync) |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## What it does

THIS SCRIPT IS READ-ONLY. Run it ON the Microsoft Entra Connect server (as SYSTEM from your RMM). On a computer without the ADSync PowerShell module it is SKIPPED. It checks:

1. the ADSync service: it must exist, be running and not be Disabled or Manual;
2. the scheduler (Get-ADSyncScheduler): SyncCycleEnabled must be true and SchedulerSuspended must not be true (Connect sets it during an upgrade); StagingModeEnabled must match ExpectedMode (a staging server imports and synchronizes but does not export to Entra ID);
3. the sync run history (Get-ADSyncRunProfileResult): the newest run of every connector must have the result "success"; any other result is an ALERT. The newest run of all must have started within MaxAgeHours (the default 3 covers the 30 minute cycle). An empty run history is an ALERT: Connect keeps seven days of it by default;
4. the installed Entra Connect version against MinimumVersion (default 2.6.84.0, the version Microsoft's version history says is required, with application-based authentication, by 7 April 2027). Empty MinimumVersion skips the check. It never starts a sync cycle, changes the scheduler or the staging mode, or touches the connectors; to start a cycle use invoke-entra-delta-sync.

Where each fact comes from: the scheduler properties SyncCycleEnabled, StagingModeEnabled, SchedulerSuspended and SyncCycleInProgress are described on the scheduler page. The run profile cmdlet is documented with its parameters only: the output property names read here (RunHistoryId, ConnectorId, RunProfileName, Result, StartDate) and the Result value "success" come from the Synchronization Service Manager and from the existing invoke-entra-delta-sync script, not from a Microsoft page. The installed version is read from the uninstall entry "Microsoft Azure AD Connect" (or "Microsoft Entra Connect") and, failing that, from the file version of the sync engine program of the ADSync service; Microsoft documents neither, so when neither is found the version is shown as not found and not alerted.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `ExpectedMode` | Active (default: this is the server that exports to Entra ID), Staging (this is the standby server) or Any. A mismatch is an ALERT. | `Active` | `ExpectedMode` or `EXPECTED_MODE` |
| `MaxAgeHours` | Alert when the newest sync run started more than this many hours ago. Whole number, 1 to 720. Default 3. | `3` | `MaxAgeHours` or `MAX_AGE_HOURS` |
| `MinimumVersion` | Alert when the installed Entra Connect version is lower than this, such as 2.6.84.0. Default 2.6.84.0. Empty skips the version check. | `2.6.84.0` | `MinimumVersion` or `MINIMUM_VERSION` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-entra-connect-health.ps1
Alerts unless this is the active Entra Connect server, its service and scheduler run, every connector's last run succeeded within 3 hours and the version is 2.6.84.0 or later.
```

```powershell
.\test-entra-connect-health.ps1 -ExpectedMode Staging -MinimumVersion ''
For the standby server: it must be in staging mode; the version is not checked.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `ExpectedMode`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Entra Connect 2.6.92.0, active; service running; 3 connectors, newest run 14 min ago, all success
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Check`, `Value`, `Healthy`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-19 First version (untested).

## More

Full page: https://mspoutpost.com/scripts/test-entra-connect-health

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
