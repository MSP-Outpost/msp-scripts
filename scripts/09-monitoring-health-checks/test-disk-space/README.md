# Disk space below threshold

> Alerts when a fixed drive has less free space than the threshold you set.

| | |
|---|---|
| Script | `test-disk-space.ps1` |
| Type | Monitor |
| Category | Monitoring & health checks |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | Either |
| Requires | PowerShell 5.1 |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 10 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It reads every fixed drive's size and free space and compares the free percentage with ThresholdPercent. It writes one row per drive and alerts (exit 1) when any drive is below the threshold.

Removable drives are skipped unless IncludeRemovable is true. Network drives, CD drives and drives without a size (a locked BitLocker volume) are always skipped.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `ThresholdPercent` | Alert when free space is below this percentage. Whole number, 1 to 99. Default 10. | `10` | `ThresholdPercent` or `THRESHOLD_PERCENT` |
| `IncludeRemovable` | Also check removable drives (USB disks). true or false. Default false. | `false` | `IncludeRemovable` or `INCLUDE_REMOVABLE` |
| `ExcludeDrives` | Drive letters to skip, separated by commas, e.g. "D:, E:". Default none. | (empty) | `ExcludeDrives` or `EXCLUDE_DRIVES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-disk-space.ps1 -ThresholdPercent 15
```

Alerts if any fixed drive has less than 15% free.

```powershell
.\test-disk-space.ps1 -ExcludeDrives "D:" -OutputFormat Json
```

Checks every fixed drive except D: and prints one JSON object.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `ThresholdPercent`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
C: 8% free (31 GB of 400 GB); threshold 10%
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Drive`, `Label`, `FreeGB`, `SizeGB`, `FreePercent`, `BelowThreshold`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-disk-space

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
