# Windows 10 PC needs Windows 11 - check eligibility and start the in-place upgrade

> Checks that a Windows 10 PC can run Windows 11, then starts the in-place upgrade (apps and files are kept).

| | |
|---|---|
| Script | `update-windows-10-to-11.ps1` |
| Type | Action |
| Category | Patching & Windows Update |
| Platforms | Windows 10 |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, Windows 11 media or internet access to Microsoft |
| Changes | Starts the Windows 11 in-place upgrade (Windows Setup or the Installation Assistant), which later restarts the PC and replaces Windows 10 |
| Risk | **High** |
| Reboot | May |
| Typical runtime | Under 1 minute to start; the upgrade then runs 30 to 90 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=update-windows-10-to-11`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\update-windows-10-to-11.log`.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. It is a High-risk Action: it only reports what it would do until BOTH DryRun=false AND Approve=update-windows-10-to-11 are set.

Step 1, already done? A PC that already runs Windows 11 answers OK "Already Windows 11" and nothing else happens. A PC where an upgrade is already running (Windows 11 Installation Assistant or Windows Setup) answers OK. Windows Server is skipped.

Step 2, eligibility, one row per requirement: 64-bit Windows 10 version 2004 (build 19041) or later; UEFI firmware (Secure Boot capable; its current state is reported); TPM 2.0 present and enabled; a 64-bit processor with 2 or more cores at 1 GHz or faster; RAM of at least MinRamGB; a system disk of at least MinDiskGB; FreeSpaceGB free on the system drive; and no restart waiting. A PC that fails any row is SKIPPED, and the answer names every reason. Microsoft's list of supported CPU models and its compatibility "safeguard holds" are NOT checked here: Windows Setup checks them itself and refuses to upgrade an unsupported PC.

Step 3, the upgrade, only when approved and eligible:

- MediaPath set: runs setup.exe from that folder (extracted Windows 11 media, a mounted ISO drive such as E:\ or a network share) with /auto upgrade /quiet. The file must be signed by Microsoft. Unless AllowReboot is true it adds /noreboot, so Setup prepares everything and then WAITS for a restart that you choose (restart-computer).
- MediaPath empty: downloads Microsoft's Windows 11 Installation Assistant (go.microsoft.com/fwlink/?linkid=2171764), checks that it is signed by Microsoft, and runs it silently. The Assistant restarts the PC itself when it has finished, and cannot be stopped from doing so, so this only runs when AllowReboot is true. Otherwise the script stops and says to set AllowReboot=true or to give a MediaPath.

The script never restarts the PC itself. AllowReboot=true only lets the upgrade restart it, which interrupts a signed-in user without warning: the answer names the signed-in user when there is one. The upgrade runs in the background for 30 to 90 minutes; the script returns as soon as Setup has started. Setup's own log is in C:\$WINDOWS.~BT\Sources\Panther\setupact.log.

Nothing in the Windows 10 install is deleted by this script. The upgrade keeps files, apps and settings, and Windows keeps the old Windows for 10 days so the user can go back (Settings, System, Recovery). Back up first.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `MediaPath` | Folder that contains Windows 11 setup.exe. Default empty = use the Installation Assistant (needs AllowReboot=true). | (empty) | `MediaPath` or `MEDIA_PATH` |
| `AllowReboot` | true lets the upgrade restart the PC by itself (required for the Installation Assistant). Default false: with MediaPath, Setup waits for a restart you start. | `false` | `AllowReboot` or `ALLOW_REBOOT` |
| `MinRamGB` | Minimum RAM in GB. Whole number, 1 to 4096. Default 4 (Microsoft's minimum). | `4` | `MinRamGB` or `MIN_RAM_GB` |
| `MinDiskGB` | Minimum size of the system disk in GB. Whole number, 1 to 100000. Default 64 (Microsoft's minimum). | `64` | `MinDiskGB` or `MIN_DISK_GB` |
| `FreeSpaceGB` | Minimum free space on the system drive in GB. Whole number, 1 to 100000. Default 30. | `30` | `FreeSpaceGB` or `FREE_SPACE_GB` |
| `IncludeWindows11` | true runs the eligibility checks on a PC that already runs Windows 11, for a dry run to test the checks. A real upgrade is refused on Windows 11. Default false. | `false` | `IncludeWindows11` or `INCLUDE_WINDOWS11` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\update-windows-10-to-11.ps1
```

Dry run: checks the PC and says whether and how it would start the upgrade.

```powershell
.\update-windows-10-to-11.ps1 -DryRun false -Approve update-windows-10-to-11 -MediaPath E:\
```

Starts the upgrade from the mounted Windows 11 media on E: and leaves the restart to you.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `MediaPath`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `update-windows-10-to-11`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Started the Windows 11 upgrade from setup media; it waits for a restart
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\update-windows-10-to-11.log`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/update-windows-10-to-11

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
