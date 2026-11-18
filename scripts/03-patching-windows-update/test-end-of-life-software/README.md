# End-of-life software installed

> Alerts when software past its end of support is installed, and says what to do about each one.

| | |
|---|---|
| Script | `test-end-of-life-software.ps1` |
| Type | Monitor |
| Category | Patching & Windows Update |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1 |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It compares the machine-wide installed-programs list (64-bit and 32-bit) with a built-in list of products whose vendor stopped issuing security fixes, and checks the Windows version itself.

The built-in list is deliberately short and clear-cut: Adobe Flash Player, Adobe Shockwave Player, Microsoft Silverlight, Apple QuickTime for Windows, consumer Skype (retired 2025-05-05), Adobe Reader older than DC, Java 6 and Java 7, Python 2, Skype for Business, Microsoft Office, Visio and Project 2007, 2010 and 2013, Office 2016 and 2019 (support ended 2025-10-14), and Internet Explorer 11 when its Windows feature is still switched on (not on Windows 10 LTSC or IoT, where IE11 is supported with the OS). The Windows row appears for Windows 11 releases past end of service (21H2, 22H2, 23H2 and 24H2, Home/Pro and Enterprise/Education dates differ), Windows 10 (support ended 2025-10-14, except the LTSC editions), Windows 8.1 and older, and Windows Server 2012 R2 and older. Set IncludeOs to false for PCs that have bought Extended Security Updates.

ExtraNames adds your own names (for example a line-of-business tool that is retired); a match there says the software is on your own list.

ALERT when anything is found; every finding is a row with what to do. OK otherwise. Per-user installs are not in the list this reads.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `ExtraNames` | Extra application names to treat as end-of-life, comma or semicolon separated. * and ? work; a name without a wildcard matches anywhere in the name. Each needs at least 3 letters besides wildcards. Default empty. | (empty) | `ExtraNames` or `EXTRA_NAMES` |
| `IncludeOs` | true to also alert when Windows itself is out of support. Default true. | `true` | `IncludeOs` or `INCLUDE_OS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-end-of-life-software.ps1
```

Checks the built-in list and Windows itself.

```powershell
.\test-end-of-life-software.ps1 -ExtraNames "OldCrm*;LegacyScan" -IncludeOs false
```

Also flags the two named programs, and ignores the Windows version.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `ExtraNames`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
2 end-of-life items: Adobe Flash Player 32 (ended 2020-12-31); Windows 10 (ended 2025-10-14)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Product`, `Found`, `SupportEnded`, `WhatToDo`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-end-of-life-software

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
