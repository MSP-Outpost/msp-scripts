# Install Windows updates

> Searches for, downloads and installs Windows updates through the Windows Update Agent, and reports each one.

| | |
|---|---|
| Script | `install-windows-updates.ps1` |
| Type | Action |
| Category | Patching & Windows Update |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, Windows Update service, a reachable update source |
| Changes | Installs Windows updates; may restart the PC when RebootIfRequired is true and nobody is signed in |
| Risk | Low |
| Reboot | Restarts |
| Typical runtime | 5 to 120 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS. It uses the Windows Update Agent (Microsoft.Update.Session), the same engine as Windows Update, so it follows the PC's own update source (Microsoft, WSUS or Windows Update for Business policy). It searches for software updates that are not installed and not hidden, keeps the ones in Categories, drops ExcludeKBs, then downloads and installs them one at a time, one row each. It accepts the licence terms of the updates it installs. An update that needs a person to answer a prompt is skipped and said so. When a restart was already pending and some updates refuse to install until it happens, the run ends SKIPPED (restart, then run again), not ERROR.

Categories: Security (Security Updates, which include the monthly cumulative updates), Critical (Critical Updates) or All (every software update found). Default Security and Critical. Feature updates (Windows version upgrades) are never installed by this script. Drivers are left alone unless IncludeDrivers is true.

One failing update does not stop the others; the run ends in ERROR naming the failures. When TimeoutMinutes has passed, no further update is started and the run ends in ERROR saying how many are left, so run it again to continue.

Reboots: it never restarts the PC unless RebootIfRequired is true AND nobody is signed in; then it schedules a restart in 60 seconds. In every other case it finishes with "reboot needed" in the answer.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Categories` | Which updates to install, comma or semicolon separated: Security, Critical, All. Default Security,Critical. | `Security,Critical` | `Categories` or `CATEGORIES` |
| `IncludeDrivers` | true to also install pending driver updates. Default false. | `false` | `IncludeDrivers` or `INCLUDE_DRIVERS` |
| `ExcludeKBs` | KB numbers never to install, comma or semicolon separated, with or without the KB prefix. Default empty. | (empty) | `ExcludeKBs` or `EXCLUDE_K_BS` |
| `RebootIfRequired` | true to restart the PC when updates need it and nobody is signed in. Default false. | `false` | `RebootIfRequired` or `REBOOT_IF_REQUIRED` |
| `TimeoutMinutes` | No new update is started after this many minutes. Whole number, 5 to 1440. Default 120. | `120` | `TimeoutMinutes` or `TIMEOUT_MINUTES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\install-windows-updates.ps1 -DryRun true
```

Lists the security and critical updates that would be installed.

```powershell
.\install-windows-updates.ps1 -Categories All -ExcludeKBs KB5044284 -RebootIfRequired true
```

Installs every software update except one, and restarts if nobody is signed in.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Categories`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Installed 3 updates (KB5044284, KB5043145, KB5041587); reboot needed
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\install-windows-updates.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/install-windows-updates

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
