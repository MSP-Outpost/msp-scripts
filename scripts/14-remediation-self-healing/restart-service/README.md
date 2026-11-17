# Service stopped or hung - restart it

> Restarts a stopped or hung Windows service and checks it is running again.

| | |
|---|---|
| Script | `restart-service.ps1` |
| Type | Action |
| Category | Remediation & self-healing |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | Stops and starts the named service and its running dependents; ends a hung service process |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 3 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS. It finds the service by its service name or its display name, stops it, starts it again and checks it is Running. It never changes a service's start type or settings.

A service stuck in "Stopping" is the usual reason to run this. If the service does not stop within TimeoutSeconds, the script ends the service's own process (found from its process id) and says so in the answer. A service that shares its process with other running services (a shared svchost) is never killed: that would stop the others too, so the script reports an ERROR instead.

Services that depend on it are handled by IncludeDependents. With true (the default) the running dependents are stopped with it and started again afterwards. With false the script stops with an ERROR when a dependent is running, rather than stopping it.

Protected services: the script refuses to restart the service whose process is its own parent chain (the RMM agent that is running it), and refuses the services of known RMM and remote-support agents (the list in get-rmm-agents) unless Force is true. Restarting your own agent mid-run can end the script before it reports.

A service that is already stopped is started. A running service is always restarted, so unlike most Actions a second run restarts it again. A service whose start type is Disabled cannot be started: ERROR.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Name` | The service name (for example Spooler) or the display name (for example Print Spooler). Required. | (empty) | `Name` or `NAME` |
| `TimeoutSeconds` | How long to wait for the service to stop, and again to start. Whole number, 5 to 600. Default 60. | `60` | `TimeoutSeconds` or `TIMEOUT_SECONDS` |
| `IncludeDependents` | true to stop running dependent services with it and start them again; false to fail instead. Default true. | `true` | `IncludeDependents` or `INCLUDE_DEPENDENTS` |
| `Force` | true to allow restarting a known RMM or remote-support agent service. Never lets it restart the agent that is running this script. Default false. | `false` | `Force` or `FORCE` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\restart-service.ps1 -Name Spooler
```

Restarts the Print Spooler and checks it runs.

```powershell
.\restart-service.ps1 -Name "Windows Update" -TimeoutSeconds 120 -DryRun true
```

Shows what a restart of the Windows Update service would do.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Name`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Restarted Spooler (Print Spooler); Running
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\restart-service.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/restart-service

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
