# Change not showing in Microsoft 365 - force an Entra Connect sync

> Starts a Microsoft Entra Connect sync cycle (Delta or Initial) now, waits for it and reports how it ended.

| | |
|---|---|
| Script | `invoke-entra-delta-sync.ps1` |
| Type | Action |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows Server 2016+ (the Microsoft Entra Connect server) |
| Runs as | System |
| Requires | PowerShell 5.1; admin rights; Microsoft Entra Connect (ADSync module); ADSyncAdmins or local admin |
| Changes | Starts one Entra Connect sync cycle (Delta or Initial) |
| Risk | Low |
| Reboot | Never |
| Typical runtime | 1 to 10 minutes while it waits |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## What it does

THIS SCRIPT CHANGES THINGS. Run it ON the Microsoft Entra Connect server (the module ADSync is installed with Entra Connect; the Cloud Sync agent does not have it). It:

- reads the sync scheduler (Get-ADSyncScheduler) and refuses to start when a sync cycle is already running (SyncCycleInProgress), or when this server is in staging mode (a staging server does not export to Entra ID);
- starts one sync cycle with Start-ADSyncSyncCycle -PolicyType, Delta by default (only changes since the last cycle) or Initial (a full import and sync of every connector: much heavier, use it after changing sync rules or filters);
- waits up to TimeoutSeconds for the cycle to finish (0 = start it and do not wait);
- reads the run results that appeared during the wait with Get-ADSyncRunProfileResult and reports each connector run and its result. A result other than "success" ends the script as ERROR with the results listed. If that cmdlet is missing the script says so in a warning and reports only that the cycle finished.

It never changes sync rules, filters, the scheduler settings or any account. Nothing is changed by a dry run (DryRun=true or -WhatIf): it lists the cycle it would start.

A sync cycle is an event, not a state, so there is no "already done" run: a second run starts a second cycle. The script ends ERROR with the message that a cycle is running when one is, so an RMM can try again later. The header Risk is Low for Delta; an Initial cycle on a large directory can run for hours and use the server heavily, so start it in quiet hours.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `PolicyType` | Delta (default) or Initial. | `Delta` | `PolicyType` or `POLICY_TYPE` |
| `TimeoutSeconds` | How long to wait for the cycle to finish. Whole number, 0 to 7200; 0 = do not wait. Default 600. When the time runs out while the cycle is still running, the run still ends CHANGED (the cycle was started) and says it was still running. | `600` | `TimeoutSeconds` or `TIMEOUT_SECONDS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\invoke-entra-delta-sync.ps1
Starts a Delta sync cycle and waits up to 10 minutes for it.
```

```powershell
.\invoke-entra-delta-sync.ps1 -PolicyType Initial -TimeoutSeconds 0 -DryRun true
Shows that it would start a full sync and not wait; changes nothing.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `PolicyType`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Delta sync finished in 74 s: 4 connector run(s), all success
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\invoke-entra-delta-sync.log`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/invoke-entra-delta-sync

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
