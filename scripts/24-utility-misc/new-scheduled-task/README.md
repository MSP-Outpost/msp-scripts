# Create or update a scheduled task

> Creates or updates a scheduled task that runs a program at startup, at logon, daily or once.

| | |
|---|---|
| Script | `new-scheduled-task.ps1` |
| Type | Action |
| Category | Utility / misc |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | Creates or updates one scheduled task; saves the old definition as XML before an update |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 10 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS. It registers one scheduled task in the root folder of Task Scheduler with one trigger and one action, and nothing else: it never runs the task, never deletes a task and never touches another one.

The task is defined by the inputs: TaskName, the program (Command) and its Arguments, a Trigger (Startup, Logon, Daily or Once, with At for the last two), who it runs as (System, or Users: the BUILTIN\Users group, so it runs in the session of whoever signs in) and whether it is Hidden in Task Scheduler.

Running it again with the same inputs changes nothing and says OK. With different inputs it updates the task: the old definition is exported to XML (Export-ScheduledTask) and copied to %ProgramData%\MSPOutpost\Backups\new-scheduled-task\ first.

Names: TaskName must start with MSPOutpost- so this script only ever manages its own tasks. Set AllowAnyName=true to use another name; that can replace an existing task of that name (after the backup).

Privilege-escalation guard: a task that runs as System executes its program with full rights, so when RunAs is System the script refuses a program (or a file named in Arguments) that standard users could change: the file or its folder is writable by Users, Authenticated Users, Everyone or Interactive, or it is owned by an ordinary user, or a parent folder lets users delete or re-permission it. Fix the permissions or put the program under C:\Program Files or C:\Windows.

The Command is stored as a full path (a bare name such as powershell.exe is resolved first). A .ps1 file is refused: run powershell.exe with Arguments "-NoProfile -File <script>" instead.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TaskName` | Task name, required, no \ / : * ? " < > \|. Must start with MSPOutpost- unless AllowAnyName is true. | (empty) | `TaskName` or `TASK_NAME` |
| `Command` | Program to run: a full path or a name found on PATH. Required. | (empty) | `Command` or `COMMAND` |
| `Arguments` | Arguments passed to the program. Optional. | (empty) | `Arguments` or `ARGUMENTS` |
| `Trigger` | Startup (default), Logon, Daily or Once. | `Startup` | `Trigger` or `TRIGGER` |
| `At` | Start time for Daily and Once: HH:mm (24-hour, local) or, for Once only, yyyy-MM-ddTHH:mm. With Once and HH:mm the next such time is used. Ignored for Startup and Logon. | (empty) | `At` or `AT` |
| `RunAs` | System (default) or Users (the BUILTIN\Users group, interactive; use with Logon, Daily or Once). | `System` | `RunAs` or `RUN_AS` |
| `Hidden` | true to hide the task in Task Scheduler. Default false. | `false` | `Hidden` or `HIDDEN` |
| `AllowAnyName` | true to allow a TaskName without the MSPOutpost- prefix. Default false. | `false` | `AllowAnyName` or `ALLOW_ANY_NAME` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\new-scheduled-task.ps1 -TaskName MSPOutpost-Cleanup -Command C:\Windows\System32\cleanmgr.exe -Arguments /AUTOCLEAN -Trigger Daily -At 03:00
```

Runs the program every day at 03:00 as SYSTEM.

```powershell
.\new-scheduled-task.ps1 -TaskName MSPOutpost-Welcome -Command C:\Windows\System32\msg.exe -Arguments "* Welcome" -Trigger Logon -RunAs Users
```

Runs for whoever signs in, in their session.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `TaskName`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Created task MSPOutpost-Cleanup: daily at 03:00 as SYSTEM, C:\Windows\System32\cleanmgr.exe
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\new-scheduled-task.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/new-scheduled-task

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
