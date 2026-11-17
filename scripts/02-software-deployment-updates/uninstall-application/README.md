# Uninstall an application silently by name

> Uninstalls an application silently by name, and checks it is gone.

| | |
|---|---|
| Script | `uninstall-application.ps1` |
| Type | Action |
| Category | Software deployment & updates |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | Runs the silent uninstaller of each matching application |
| Risk | **High** |
| Reboot | May |
| Typical runtime | 1 to 10 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=uninstall-application`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\uninstall-application.log`.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. It finds installed applications whose name matches Name (the machine-wide installed-programs list, 64-bit and 32-bit), runs each one's silent uninstaller and checks the entry is gone. It never touches per-user installs, Microsoft Store apps, updates or hotfixes, entries marked as system components, or entries marked as not removable.

How each application is uninstalled:

- Windows Installer (MSI): msiexec /x {ProductCode} /qn /norestart.
- The entry's own QuietUninstallString, when it has one.
- Otherwise its UninstallString plus the silent switch of an installer type the script positively identifies: NSIS (/S, run in place with _?= so the script can wait for it), Inno Setup (/VERYSILENT /SUPPRESSMSGBOXES /NORESTART) or a WiX bundle (/quiet /norestart).
- No known silent method: ERROR naming the application. The script never starts an interactive uninstaller.

Exit codes 0, 3010 and 1641 are success. 3010 and 1641 mean a reboot is needed to finish; the script says so and does not reboot.

Name without a wildcard (* or ?) matches anywhere in the name. With ExactMatch true the whole name must match, ignoring case. More than one match is an ERROR that lists them, unless AllowMultiple is true. A name with fewer than 3 letters outside wildcards is refused.

Risk is High: it changes nothing unless DryRun is false AND Approve is set to uninstall-application. It refuses to remove more than MaxChanges applications (default 25) in one run. The dry run still lists the applications and fails if one has no silent method.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Name` | Application name to remove, as shown in Apps & features. Wildcards * and ? work. Required. | (empty) | `Name` or `NAME` |
| `ExactMatch` | true to require the whole name to match instead of a part of it. Default false. | `false` | `ExactMatch` or `EXACT_MATCH` |
| `Publisher` | Only applications whose publisher contains this text. Default empty. | (empty) | `Publisher` or `PUBLISHER` |
| `AllowMultiple` | true to remove every match instead of stopping when there are several. Default false. | `false` | `AllowMultiple` or `ALLOW_MULTIPLE` |
| `TimeoutSeconds` | How long to wait for each uninstaller. Whole number, 30 to 7200. Default 600. | `600` | `TimeoutSeconds` or `TIMEOUT_SECONDS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\uninstall-application.ps1 -Name "Zoom" -ExactMatch true
```

Dry run: shows what removing the application named exactly Zoom would do.

```powershell
.\uninstall-application.ps1 -Name "Java*" -Publisher Oracle -AllowMultiple true -DryRun false
```

Removes every Oracle application whose name starts with Java.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Name`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `uninstall-application`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Uninstalled Zoom 6.2.5; reboot needed
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\uninstall-application.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/uninstall-application

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
