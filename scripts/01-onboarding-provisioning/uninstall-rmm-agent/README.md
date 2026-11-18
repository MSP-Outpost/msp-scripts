# Remove the previous provider's RMM agent

> Removes one named RMM agent (the previous provider's) cleanly: its uninstaller, services, tasks and folders.

| | |
|---|---|
| Script | `uninstall-rmm-agent.ps1` |
| Type | Action |
| Category | Onboarding & provisioning |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | Runs the agent's silent uninstaller, deletes its leftover services, scheduled tasks and program folders |
| Risk | **High** |
| Reboot | May |
| Typical runtime | 1 to 10 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=uninstall-rmm-agent`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\uninstall-rmm-agent.log`.
- Before it edits or deletes configuration, it copies it to `%ProgramData%\MSPOutpost\Backups\uninstall-rmm-agent\<UTC time>\` and keeps the last 10 runs. If a backup fails, nothing is changed.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. It removes ONE named RMM or remote-management agent, picked from the same list get-rmm-agents reports (Datto RMM, NinjaOne, N-able N-central and N-sight, Kaseya VSA, ConnectWise Automate and RMM, Atera, Syncro, Tactical RMM, Action1, Pulseway, Level and more). There is no "all": one product per run. In this order it:

- runs the product's silent uninstaller from the installed-programs list (Windows Installer: msiexec /x {ProductCode} /qn /norestart; the entry's QuietUninstallString; or its UninstallString with the silent switch of a positively identified Inno Setup, NSIS or WiX installer). An entry whose uninstaller file is already gone is removed as a stale entry;
- stops and deletes the product's leftover Windows services;
- removes its leftover scheduled tasks (by name, or because they run a program from the product's folder);
- deletes its program folders (and stops any process still running from them).

Before it removes a service, a stale entry or a scheduled task it backs up that registry key or the task (reg export, Export-ScheduledTask) under %ProgramData%\MSPOutpost\Backups\uninstall-rmm-agent. It never touches a product other than the one named, Microsoft Intune or ScreenConnect (use remove-screenconnect-instances), and it never removes the product whose agent is running this script: if the product's service or program folder belongs to this script's own process chain, the run stops with an error unless Force is true (and then the script is probably cut off half way).

Tamper-protected agents: put the vendor's removal key in the environment variable RemovalKey (a secret/hidden field in your RMM; it is never taken as an argument and never printed). It is passed to the uninstaller only for products whose documented uninstall takes one (NinjaOne: disableUninstallPrevention=TRUE UNINSTALL_KEY=<key>); for any other product it is ignored with a warning. NinjaOne documents no file or environment alternative, so the key is passed on the msiexec command line: if you audit process creation with command lines (event 4688, Sysmon, EDR), it is recorded. Use a removal key you can rotate afterwards.

Risk is High: it changes nothing unless DryRun is false AND Approve is set to uninstall-rmm-agent. The dry run lists every step and fails when the product has no known silent uninstall method.

Make sure the new RMM agent is installed and checking in BEFORE removing the old one: this script cannot undo an uninstall.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Product` | The agent to remove, as get-rmm-agents names it, for example "Datto RMM" or NinjaOne. Spaces, case and punctuation do not matter (DattoRMM works). Required. | (empty) | `Product` or `PRODUCT` |
| `Force` | true to remove the product even when it is the agent running this script. Default false. | `false` | `Force` or `FORCE` |
| `TimeoutSeconds` | How long to wait for the uninstaller. Whole number, 30 to 7200. Default 600. | `600` | `TimeoutSeconds` or `TIMEOUT_SECONDS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\uninstall-rmm-agent.ps1 -Product "Datto RMM"
```

Dry run: lists what removing the Datto RMM agent would do.

```powershell
.\uninstall-rmm-agent.ps1 -Product NinjaOne -DryRun false -Approve uninstall-rmm-agent
```

Removes the NinjaOne agent (set the environment variable RemovalKey first when the agent is tamper-protected).

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Product`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `uninstall-rmm-agent`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Removed Datto RMM (1 uninstaller, 1 service, 0 tasks, 2 folders)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\uninstall-rmm-agent.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/uninstall-rmm-agent

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
