# OneDrive not syncing - reset it

> Resets OneDrive for the signed-in user (OneDrive.exe /reset) and makes sure it is running again; files are not deleted, OneDrive re-syncs.

| | |
|---|---|
| Script | `reset-onedrive.ps1` |
| Type | Action |
| Category | Remediation & self-healing |
| Platforms | Windows 10, Windows 11 |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, a user signed in at the console |
| Changes | Runs OneDrive.exe /reset for the signed-in user (OneDrive stops, clears its sync state and re-syncs); starts OneDrive again if it did not restart |
| Risk | Low |
| Reboot | Never |
| Typical runtime | 1 to 3 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS. As the user who is signed in at the console (the script runs from SYSTEM and starts the steps in that user's own session), it:

- finds OneDrive.exe: %LOCALAPPDATA%\Microsoft\OneDrive, then Program Files\Microsoft OneDrive, then Program Files (x86)\Microsoft OneDrive,
- runs OneDrive.exe /reset, which stops OneDrive and clears its sync settings and cache,
- waits up to RestartWaitSeconds for OneDrive to start again by itself,
- if it did not, starts it again with OneDrive.exe /background,
- checks that OneDrive is running for that user.

WARNING FOR THE USER: after a reset OneDrive scans and re-syncs everything. On a large library that can take hours and use bandwidth. No file is deleted from the PC or from the cloud, but OneDrive may forget folder choices (selective sync) and the user may have to confirm their account. Tell the user first.

It never touches the files in the OneDrive folders, other users, or a user who is not signed in. Nobody signed in: SKIPPED. OneDrive not installed for that user: SKIPPED. Running it twice resets twice: a reset is not something that can already be done.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `RestartWaitSeconds` | How long to wait for OneDrive to restart by itself after the reset before starting it with /background. Whole number, 5 to 300. Default 60. | `60` | `RestartWaitSeconds` or `RESTART_WAIT_SECONDS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\reset-onedrive.ps1 -DryRun true
```

Says which OneDrive.exe it would reset and for whom; changes nothing.

```powershell
.\reset-onedrive.ps1 -RestartWaitSeconds 90
```

Resets OneDrive and gives it 90 seconds to restart by itself.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `RestartWaitSeconds`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Reset OneDrive for PC01\jsmith; it restarted on its own and is running. It re-syncs; no files are deleted.
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\reset-onedrive.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/reset-onedrive

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
