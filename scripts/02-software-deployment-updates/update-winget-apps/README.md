# Update apps with winget

> Upgrades every application winget can update, one by one, skipping the ones you exclude.

| | |
|---|---|
| Script | `update-winget-apps.ps1` |
| Type | Action |
| Category | Software deployment & updates |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, winget (App Installer), internet access |
| Changes | Upgrades each application winget lists as upgradable |
| Risk | Low |
| Reboot | May |
| Typical runtime | 1 to 30 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS. It finds winget (App Installer) the way SYSTEM can run it: the newest winget.exe in the Microsoft.DesktopAppInstaller folder under Program Files\WindowsApps. If winget is not there the run is SKIPPED and says so; the script never installs winget.

It lists the applications with an upgrade available (winget upgrade), drops the ones in ExcludeIds and a built-in never-upgrade list (RMM and remote-support agents such as ScreenConnect, TeamViewer, AnyDesk and Splashtop; virtual-machine guest tools such as QEMU, VirtIO, SPICE/UTM, VMware Tools and Hyper-V; and Microsoft.AppInstaller, which would replace winget itself in the middle of the run), then upgrades each remaining application on its own with winget upgrade --id <Id> --exact --silent and the package and source agreement switches, with prompts off. Each application is one row; one failing application does not stop the others, and the run ends in ERROR naming the ones that failed. Afterwards it lists again and warns about any application still shown as upgradable.

When somebody is signed in, an application that appears to be running for them (a process in a user session named like the application's Id or name) is skipped and listed, because a silent upgrade closes it. Set Force to true to upgrade those too. A winget process that runs longer than TimeoutMinutes is stopped. If winget cannot list upgrades (source error), the run ends in ERROR rather than saying "up to date". A winget result that means "restart needed" counts as success and is reported.

As SYSTEM, winget sees machine-wide applications only; per-user installs are not listed. An installer may close a running copy of its application, so schedule this outside working hours. It never changes applications that are not in winget's list, and it never reboots.

MaxChanges (optional) refuses to run when more applications than that would be upgraded.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `ExcludeIds` | Winget package Ids never to upgrade, comma or semicolon separated; - and ? work (for example Google.Chrome;Mozilla.*). Default empty. | (empty) | `ExcludeIds` or `EXCLUDE_IDS` |
| `Force` | true to upgrade applications that appear to be running for the signed-in user (their windows close). Default false. | `false` | `Force` or `FORCE` |
| `TimeoutMinutes` | How long to wait for each application's upgrade. Whole number, 1 to 240. Default 30. | `30` | `TimeoutMinutes` or `TIMEOUT_MINUTES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\update-winget-apps.ps1 -DryRun true
```

Lists what would be upgraded.

```powershell
.\update-winget-apps.ps1 -ExcludeIds "Google.Chrome;Microsoft.Teams*" -TimeoutMinutes 15
```

Upgrades everything except Chrome and Teams.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `ExcludeIds`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Upgraded 3 of 3 winget apps: Git.Git, 7zip.7zip, VideoLAN.VLC
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\update-winget-apps.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/update-winget-apps

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
