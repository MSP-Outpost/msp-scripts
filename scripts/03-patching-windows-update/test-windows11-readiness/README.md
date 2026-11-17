# Can this PC run Windows 11?

> Checks whether this PC meets the hardware requirements for Windows 11.

| | |
|---|---|
| Script | `test-windows11-readiness.ps1` |
| Type | Monitor |
| Category | Patching & Windows Update |
| Platforms | Windows 10, Windows 11 |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 15 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. On a Windows 10 PC it checks, one row each:

- Operating system: 64-bit Windows 10 version 2004 (build 19041) or later.
- UEFI firmware, and whether Secure Boot is on. Windows 11 needs a PC that is Secure Boot CAPABLE (UEFI), not one with it switched on, so Secure Boot "Off" passes and the row says it can be enabled.
- TPM 2.0, present and enabled.
- Processor: 64-bit, 2 or more cores, 1 GHz or faster. The CPU name is reported. Microsoft's list of supported CPU models is NOT checked and no guess is made: compare the name with the list yourself.
- RAM of at least MinRamGB (installed memory from the memory modules, rounded to a whole GB; falls back to the usable amount Windows reports).
- System disk of at least MinDiskGB (decimal GB, the whole physical disk).

It alerts (exit 1) when any row fails. A PC already running Windows 11 answers OK straight away, without the checks, unless IncludeWindows11 is true. Windows Server is skipped. Microsoft's compatibility "safeguard holds" are not checked. Needs administrator rights (TPM query).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `MinRamGB` | Minimum RAM in GB. Whole number, 1 to 4096. Default 4 (Microsoft's minimum). | `4` | `MinRamGB` or `MIN_RAM_GB` |
| `MinDiskGB` | Minimum size of the system disk in GB. Whole number, 1 to 100000. Default 64 (Microsoft's minimum). | `64` | `MinDiskGB` or `MIN_DISK_GB` |
| `IncludeWindows11` | true to run the checks on a PC that already runs Windows 11 (default false: it answers OK without checking). | `false` | `IncludeWindows11` or `INCLUDE_WINDOWS11` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-windows11-readiness.ps1
```

Alerts when a Windows 10 PC fails a Windows 11 hardware requirement.

```powershell
.\test-windows11-readiness.ps1 -MinRamGB 8 -IncludeWindows11 true
```

Also fails PCs with less than 8 GB of RAM, and checks Windows 11 PCs too.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `MinRamGB`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Not ready for Windows 11: TPM 2.0 missing; RAM 2 GB (needs 4)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Requirement`, `Value`, `Pass`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-windows11-readiness

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
