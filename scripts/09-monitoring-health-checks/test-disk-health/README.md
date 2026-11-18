# Drive about to fail - SMART health and SSD wear

> Alerts when a physical disk reports failing health, predicts failure or is worn out.

| | |
|---|---|
| Script | `test-disk-health.ps1` |
| Type | Monitor |
| Category | Monitoring & health checks |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1; administrator rights; Storage module |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 20 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. For each physical disk it reads:

- Get-PhysicalDisk: HealthStatus and OperationalStatus,
- Get-StorageReliabilityCounter: wear (percent of the drive's rated life used), temperature, uncorrected read errors and power-on hours,
- the SMART failure prediction flag (MSStorageDriver_FailurePredictStatus in root\wmi, matched to the disk by its PnP device id).

It alerts when a disk's health is Warning or Unhealthy, its operational status is anything other than OK or In Service, SMART predicts failure, or wear is at or above WearPercent.

What is not reported is shown as "not reported", never as zero. Virtual disks (virtual machines), many USB enclosures, some RAID controllers and many NVMe drives report little or nothing: the reliability counters and the SMART flag come from the drive and its driver, not from Windows. Such a disk is still checked for health status, and the answer says how many disks reported no reliability data. Set RequireReliabilityData to true to alert on a disk that reports nothing, when you cannot accept a blind spot. The SMART flag only exists for ATA and SCSI-attached drives. Needs administrator rights.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `WearPercent` | Alert when a disk reports that this percent or more of its rated life is used. Whole number, 1 to 100. Default 80. | `80` | `WearPercent` or `WEAR_PERCENT` |
| `RequireReliabilityData` | Alert on a disk that reports no reliability data at all (no wear, temperature, error count, power-on hours or SMART flag). true or false. Default false. | `false` | `RequireReliabilityData` or `REQUIRE_RELIABILITY_DATA` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-disk-health.ps1
```

Alerts on a failing, predicted-to-fail or 80%-worn disk.

```powershell
.\test-disk-health.ps1 -WearPercent 70 -RequireReliabilityData true
```

A stricter check that also alerts on disks that report nothing.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `WearPercent`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Disk 0 (Samsung SSD 970): wear 86% (limit 80%); SMART predicts failure
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Disk`, `Model`, `Health`, `WearPercent`, `TemperatureC`, `ReadErrors`, `PowerOnHours`, `SmartFailure`, `Concern`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-disk-health

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
