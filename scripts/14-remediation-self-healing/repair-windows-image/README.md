# Windows corrupted or SFC fails - DISM then SFC repair

> Repairs a corrupted Windows image: DISM component store check and repair, then SFC.

| | |
|---|---|
| Script | `repair-windows-image.ps1` |
| Type | Action |
| Category | Remediation & self-healing |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, internet or a Source for DISM |
| Changes | Repairs the Windows component store (DISM) and replaces corrupt protected system files (SFC) |
| Risk | Low |
| Reboot | May |
| Typical runtime | 10 to 40 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS. It checks first and repairs only what is broken:

- DISM ScanHealth reads the component store state (Healthy, Repairable or NonRepairable) and sfc /verifyonly checks the protected system files. Both only read.
- When the component store is damaged, DISM RestoreHealth repairs it from Windows Update, or from Source when you give one (an install.wim or install.esd of the SAME Windows build; LimitAccess then stops it contacting Windows Update).
- When system files are damaged, or the store was just repaired, it runs sfc /scannow, then re-checks with sfc /verifyonly.

Results come from the DISM health state, sfc's own output (decoded from UTF-16) and the [SR] lines sfc adds to C:\Windows\Logs\CBS\CBS.log.

Mode Auto (default) checks and repairs what it finds. Mode Scan only checks and changes nothing: damage found is reported as an ERROR so the RMM flags it. Mode Repair runs RestoreHealth and sfc /scannow even when the checks look clean.

Takes 10 to 40 minutes. Set your RMM script timeout to at least 60 minutes. Each sfc run is stopped after 60 minutes; the DISM step is not timed. It never reboots; when files are replaced on the next boot the answer says "reboot needed".

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Mode` | Auto (check, then repair what is damaged), Scan (check only) or Repair (always run RestoreHealth and sfc /scannow). Default Auto. | `Auto` | `Mode` or `MODE` |
| `Source` | Optional repair source for DISM, for example wim:D:\sources\install.wim:1 or esd:D:\sources\install.esd:1 (image index after the last colon). Must match the installed Windows build. Default empty (use Windows Update). | (empty) | `Source` or `SOURCE` |
| `LimitAccess` | true to stop DISM using Windows Update (use with Source). Default false. | `false` | `LimitAccess` or `LIMIT_ACCESS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\repair-windows-image.ps1 -Mode Scan
```

Checks the component store and system files and changes nothing.

```powershell
.\repair-windows-image.ps1 -Source wim:D:\sources\install.wim:1 -LimitAccess true
```

Repairs from a mounted Windows ISO without using Windows Update.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Mode`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Repaired: DISM restored the component store; SFC fixed 3 files
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\repair-windows-image.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/repair-windows-image

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
