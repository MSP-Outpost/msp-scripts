# Restart a PC - now, at a set time or if pending

> Restarts the PC with a visible countdown: now, at a set time, or only when a restart is pending.

| | |
|---|---|
| Script | `restart-computer.ps1` |
| Type | Action |
| Category | End-user communication & self-service |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | Schedules a restart with a warning countdown (shutdown.exe), or cancels a scheduled one |
| Risk | **High** |
| Reboot | Restarts |
| Typical runtime | Under 10 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=restart-computer`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\restart-computer.log`.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. It schedules a Windows restart with shutdown.exe /r /t <seconds> /c "<message>". Windows shows the message and a countdown to anyone signed in, so nobody is restarted without warning. It never signs anybody out by itself before the countdown ends, and it changes nothing else: no settings, no files, no services.

When decides whether to restart:

- IfPending (default) restarts only when Windows says a restart is pending: component servicing (CBS), Windows Update, the Configuration Manager client (only when installed) or a pending computer rename. Queued file renames alone do not count (antivirus and drivers leave them set on healthy PCs).
- Now restarts after DelaySeconds.
- At restarts at the next HH:mm (24-hour, local time): today if that time is still ahead, otherwise tomorrow. DelaySeconds is ignored.

SkipIfUserActive (default true): when somebody is signed in and the session is Active (not locked, not disconnected), nothing is scheduled and the run ends SKIPPED with "user active". When=At ignores it, because the restart happens later, when the countdown warns whoever is there then. Windows closes apps without asking when the countdown ends, so unsaved work can be lost: keep SkipIfUserActive on unless you mean it.

Servers: the script does not restart a server or domain controller unless AllowServers is true.

CancelPending=true cancels a scheduled restart (shutdown.exe /a) and does nothing else. If a restart is already scheduled, running it again says OK and leaves that restart alone.

The script cannot see a restart that somebody else scheduled, except that Windows refuses a second one: that case ends OK "already scheduled".

This is a High-risk Action: it is a dry run until DryRun=false and Approve=restart-computer are both set. Reboot: the PC restarts when the countdown ends, unless cancelled.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `When` | IfPending (default), Now or At. | `IfPending` | `When` or `WHEN` |
| `At` | Time of day for When=At, HH:mm, 24-hour, local (for example 02:30). | (empty) | `At` or `AT` |
| `DelaySeconds` | Countdown before a restart for When=Now or IfPending. Whole number, 0 to 86400. Default 300. | `300` | `DelaySeconds` or `DELAY_SECONDS` |
| `Message` | Text Windows shows to signed-in users, up to 512 characters, no double quotes. | `Your IT provider is restarting this computer to finish updates. Please save your work now.` | `Message` or `MESSAGE` |
| `SkipIfUserActive` | true (default) to skip when a user is signed in and active. When=At ignores it. | `true` | `SkipIfUserActive` or `SKIP_IF_USER_ACTIVE` |
| `AllowServers` | true to allow a restart on a server or domain controller. Default false. | `false` | `AllowServers` or `ALLOW_SERVERS` |
| `CancelPending` | true to cancel a scheduled restart and do nothing else. Default false. | `false` | `CancelPending` or `CANCEL_PENDING` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\restart-computer.ps1 -When IfPending -DelaySeconds 600 -DryRun false -Approve restart-computer
```

Restarts in 10 minutes if Windows is waiting for a restart and nobody is using the PC.

```powershell
.\restart-computer.ps1 -When At -At 02:30 -DryRun false -Approve restart-computer
```

Schedules a restart for 02:30 (tonight, or tomorrow if 02:30 has passed).

```powershell
.\restart-computer.ps1 -CancelPending true -DryRun false -Approve restart-computer
```

Cancels a restart scheduled earlier.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `When`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `restart-computer`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Restart scheduled for 2026-11-17 02:30 -07:00 (in 5 hours); signed-in users see the Windows warning
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\restart-computer.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/restart-computer

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
