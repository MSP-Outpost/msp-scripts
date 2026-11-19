# RMM agent stopped, disabled or missing - start it again

> Starts the RMM agent's Windows services again when they are stopped or disabled, and installs the agent when it is missing and you gave a checked installer.

| | |
|---|---|
| Script | `repair-rmm-agent.ps1` |
| Type | Action |
| Category | Remediation & self-healing |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights; internet access to InstallerUrl only when you set it |
| Changes | Starts services; sets a disabled service to Automatic; optionally restarts running services; optionally installs the agent from a checked installer |
| Risk | Low |
| Reboot | May |
| Typical runtime | Under 1 minute (installer time extra) |
| Version | 1.0.0 |
| Updated | 2026-11-18 |

## What it does

THIS SCRIPT CHANGES THINGS. For each service name in AgentServices it reads the service and then:

- missing: reports it. It installs the agent only when BOTH InstallerUrl and InstallerSha256 are set: it downloads the file over HTTPS into the secured MSP Outpost data folder, checks the SHA-256, and only then runs it (an .msi with msiexec /i /qn /norestart, an .exe directly), passing InstallerArguments. A wrong hash deletes the file and stops the run;
- stopped and Disabled: sets the startup type to Automatic, then starts it;
- stopped: starts it and waits for Running;
- running: leaves it alone. Whether a running agent is actually talking to the RMM cannot be seen from here, so a hung agent is NOT detected; set RestartRunning to true only when you know that is the fault (it then restarts each running service once). It never deletes anything, never touches a service you did not name, and accepts no wildcards.

RUN IT FROM OUTSIDE THE AGENT. Most RMMs run scripts through the agent itself, and an agent that is stopped cannot run a script. Run this from a Windows scheduled task (as SYSTEM, for example every 15 minutes), from a second management tool, or from the RMM's own "watchdog" feature. The script also protects itself: it finds its own chain of parent processes, and if a service named in AgentServices is the process that started this run, it will not restart that service (it says so and moves on).

Risk is Low (it starts services and, only with a hash you supply, installs one program); the standard's Medium level does not exist.

Where each fact comes from: Set-Service documents StartupType values Automatic and Disabled and that Name accepts no wildcards. Service state, start mode and process id are read from the Win32_Service CIM class (State, StartMode, ProcessId), which does not depend on the Windows language. Not confirmed in the documentation read here: Win32_Service.ProcessId is 0 for a stopped service (true in practice).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `AgentServices` | The agent's Windows service NAMES (not display names), separated by comma, semicolon or new line, for example CagService for Datto RMM or NinjaRMMAgent for NinjaOne. Required. No wildcards. | (empty) | `AgentServices` or `AGENT_SERVICES` |
| `RestartRunning` | true to restart services that are running (for a hung agent). Default false. | `false` | `RestartRunning` or `RESTART_RUNNING` |
| `InstallerUrl` | HTTPS address of the agent installer (.exe or .msi) to run when a named service is missing. Needs InstallerSha256. Default empty (never installs). | (empty) | `InstallerUrl` or `INSTALLER_URL` |
| `InstallerSha256` | The SHA-256 of the installer file, 64 hex characters. Required with InstallerUrl. | (empty) | `InstallerSha256` or `INSTALLER_SHA256` |
| `InstallerArguments` | Arguments passed to the installer (for an .msi they follow /i "file" /qn /norestart). They are visible on the process command line, so keep a secret site key out of them where the vendor offers another way. Default empty. | (empty) | `InstallerArguments` or `INSTALLER_ARGUMENTS` |
| `TimeoutSeconds` | How long to wait for a service to reach Running, and for a new service to appear after an install. Whole number, 5 to 600. Default 30. | `30` | `TimeoutSeconds` or `TIMEOUT_SECONDS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\repair-rmm-agent.ps1 -AgentServices CagService
Starts the Datto RMM agent service if it is stopped or disabled.
```

```powershell
.\repair-rmm-agent.ps1 -AgentServices "NinjaRMMAgent" -InstallerUrl https://example.com/agent.msi -InstallerSha256 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef -DryRun true
Shows what it would do, including installing the agent if the service is missing.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `AgentServices`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Repaired 1 of 2 agent service(s): started CagService
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\repair-rmm-agent.log`.

## Changelog

- 1.0.0 2026-11-18 First version.

## More

Full page: https://mspoutpost.com/scripts/repair-rmm-agent

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
