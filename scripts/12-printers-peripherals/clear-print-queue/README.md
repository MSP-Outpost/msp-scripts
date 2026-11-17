# Print queue stuck - clear the spooler

> Clears stuck print jobs by stopping the Print Spooler, deleting its queued files and starting it again.

| | |
|---|---|
| Script | `clear-print-queue.ps1` |
| Type | Action |
| Category | Printers & peripherals |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | Stops and starts the Print Spooler; deletes queued print jobs |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS. When there are queued jobs older than MinAgeMinutes, it:

- stops the Print Spooler service (and the services that depend on it),
- deletes those queued job files from the spool folder,
- starts the Print Spooler again and checks it is running.

It never removes a printer, a driver or a port, and never deletes a job newer than MinAgeMinutes. Every job in the queue, on every printer, is cancelled: tell the users first.

If nothing is queued and the spooler is running, it changes nothing and says so. If the spooler is stopped with nothing queued, it starts it.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `MinAgeMinutes` | Only delete job files at least this many minutes old, so a job being printed right now survives. Whole number, 0 to 1440. Default 0 (all). | `0` | `MinAgeMinutes` or `MIN_AGE_MINUTES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\clear-print-queue.ps1 -DryRun true
```

Lists the jobs it would delete and changes nothing.

```powershell
.\clear-print-queue.ps1 -MinAgeMinutes 10
```

Clears every job queued more than ten minutes ago.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `MinAgeMinutes`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Cleared 4 stuck print jobs; Print Spooler running
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\clear-print-queue.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/clear-print-queue

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
