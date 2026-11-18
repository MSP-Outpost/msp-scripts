# Remove remote-access tools that are not approved

> Removes remote-access tools (AnyDesk, TeamViewer, Splashtop and more) that are not on your allow-list.

| | |
|---|---|
| Script | `remove-remote-access-tools.ps1` |
| Type | Action |
| Category | Onboarding & provisioning |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | Uninstalls remote-access tools not on the allow-list, deletes their leftover services and program folders, and deletes portable copies in user folders |
| Risk | **High** |
| Reboot | May |
| Typical runtime | 1 to 10 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=remove-remote-access-tools`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\remove-remote-access-tools.log`.
- Before it edits or deletes configuration, it copies it to `%ProgramData%\MSPOutpost\Backups\remove-remote-access-tools\<UTC time>\` and keeps the last 10 runs. If a backup fails, nothing is changed.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. It looks for about 25 remote-access tools (the same detection table as get-remote-access-tools: AnyDesk, TeamViewer, Splashtop, RustDesk, LogMeIn, GoTo Resolve, ScreenConnect, the VNC family, Zoho Assist, BeyondTrust, Parsec, NoMachine, Radmin and more) and removes every tool that does not match AllowedTools, in three ways:

- Installed tools: the silent uninstaller from the installed-programs list (Windows Installer: msiexec /x {ProductCode} /qn /norestart; the entry's QuietUninstallString; or its UninstallString with the silent switch of a positively identified Inno Setup, NSIS or WiX installer; an entry whose uninstaller is already gone is removed as stale). Then its leftover Windows services and program folders are deleted.
- Portable copies (programs run straight from a folder, no installer) in each user's Downloads, Desktop, Documents and AppData: the running process is stopped, then the file is deleted. A running portable copy is only stopped when nobody is signed in or Force is true.
- Before a service is deleted its registry key is backed up (reg export) under %ProgramData%\MSPOutpost\Backups\remove-remote-access-tools.

AllowedTools is required: the tools to KEEP, by the names get-remote-access-tools reports (wildcards allowed, for example Splash*). An empty list is refused, because it would remove your own remote-support tool too, unless you set RemoveAll true to remove every tool on purpose (then AllowedTools must be empty). A tool that is the agent running this script is never removed: the run stops with an error before changing anything, unless Force is true.

Out of scope: it does not add a Microsoft Defender custom indicator or any other block to stop a removed tool being run or downloaded again. Do that in your endpoint-security tool. It also cannot remove a tool with no known silent uninstall method: it stops with an error naming it.

Risk is High: it changes nothing unless DryRun is false AND Approve is set to remove-remote-access-tools. The dry run lists everything it would remove.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `AllowedTools` | Tool names to KEEP, separated by commas, semicolons or new lines. Wildcards - and ? work. Required unless RemoveAll is true. | (empty) | `AllowedTools` or `ALLOWED_TOOLS` |
| `RemoveAll` | true to remove every remote-access tool, with an empty AllowedTools. Default false. | `false` | `RemoveAll` or `REMOVE_ALL` |
| `SearchPortable` | true (default) to also find and delete portable copies in user folders. | `true` | `SearchPortable` or `SEARCH_PORTABLE` |
| `Force` | true to stop a running portable copy while somebody is signed in, and to remove a tool that is running this script. Default false. | `false` | `Force` or `FORCE` |
| `TimeoutSeconds` | How long to wait for each uninstaller. Whole number, 30 to 7200. Default 600. | `600` | `TimeoutSeconds` or `TIMEOUT_SECONDS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\remove-remote-access-tools.ps1 -AllowedTools "Splashtop"
```

Dry run: lists every remote-access tool except Splashtop that would be removed.

```powershell
.\remove-remote-access-tools.ps1 -AllowedTools "Splashtop,ScreenConnect" -DryRun false -Approve remove-remote-access-tools
```

Removes every other remote-access tool, installed or portable.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `AllowedTools`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `remove-remote-access-tools`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Removed 2 remote-access tools: AnyDesk, TeamViewer; kept: Splashtop
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\remove-remote-access-tools.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/remove-remote-access-tools

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
