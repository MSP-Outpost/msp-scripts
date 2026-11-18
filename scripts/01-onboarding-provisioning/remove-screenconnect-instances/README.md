# Remove ScreenConnect instances that are not yours

> Removes every ScreenConnect client instance that is not on your allow-list: uninstall, service and folder.

| | |
|---|---|
| Script | `remove-screenconnect-instances.ps1` |
| Type | Action |
| Category | Onboarding & provisioning |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | Uninstalls ScreenConnect client instances not on the allow-list and deletes their leftover services and folders |
| Risk | **High** |
| Reboot | May |
| Typical runtime | 1 to 5 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=remove-screenconnect-instances`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\remove-screenconnect-instances.log`.
- Before it edits or deletes configuration, it copies it to `%ProgramData%\MSPOutpost\Backups\remove-screenconnect-instances\<UTC time>\` and keeps the last 10 runs. If a backup fails, nothing is changed.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. Every ScreenConnect server an agent was ever installed from leaves its own "ScreenConnect Client (<instance id>)" service, installed program and folder on the PC. This script finds every instance, keeps the ones whose id is in AllowedInstanceIds (YOUR servers) and removes all the others, in this order for each:

- uninstalls the instance through its Windows Installer product code (msiexec /x {ProductCode} /qn /norestart);
- stops and deletes its Windows service if the uninstall left it;
- deletes its program folder if the uninstall left it.

Before it deletes a service it backs up the service's registry key (reg export) under %ProgramData%\MSPOutpost\Backups\remove-screenconnect-instances.

An allowed instance is never touched. AllowedInstanceIds is required: an empty list is refused, because it would remove YOUR OWN ScreenConnect too, unless you set RemoveAll true to remove every instance on purpose (then AllowedInstanceIds must be empty). If a removable instance is the agent running this script, the run stops before changing anything and tells you to add it to AllowedInstanceIds. This script is for Windows only: the macOS and Linux ScreenConnect clients have different names and are not handled.

Find the instance ids first with get-remote-access-tools (the Evidence column says "Instance <id>") or in your ScreenConnect server (the ScreenConnect Client service name ends with the id in brackets).

Risk is High: it changes nothing unless DryRun is false AND Approve is set to remove-screenconnect-instances. The dry run lists every instance and what would be removed. Exit codes 3010 and 1641 from an uninstaller count as success and mean a reboot is needed to finish: the answer says so and the script never reboots.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `AllowedInstanceIds` | Instance ids to KEEP, separated by commas, semicolons or new lines, for example 0123456789abcdef. The full service name "ScreenConnect Client (0123456789abcdef)" is accepted too. Required unless RemoveAll is true. | (empty) | `AllowedInstanceIds` or `ALLOWED_INSTANCE_IDS` |
| `RemoveAll` | true to remove every ScreenConnect instance, with an empty AllowedInstanceIds. Default false. | `false` | `RemoveAll` or `REMOVE_ALL` |
| `TimeoutSeconds` | How long to wait for each uninstaller. Whole number, 30 to 7200. Default 600. | `600` | `TimeoutSeconds` or `TIMEOUT_SECONDS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\remove-screenconnect-instances.ps1 -AllowedInstanceIds 0123456789abcdef
```

Dry run: lists the ScreenConnect instances that would be removed, keeping the one with that id.

```powershell
.\remove-screenconnect-instances.ps1 -AllowedInstanceIds 0123456789abcdef -DryRun false -Approve remove-screenconnect-instances
```

Removes every other ScreenConnect instance.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `AllowedInstanceIds`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `remove-screenconnect-instances`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Removed 2 ScreenConnect instances: 1a2b3c4d5e6f7a8b, 9f8e7d6c5b4a3f2e; kept 1: 0123456789abcdef; reboot needed
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\remove-screenconnect-instances.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/remove-screenconnect-instances

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
