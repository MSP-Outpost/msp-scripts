# Laptop battery worn out - capacity and cycle count

> Alerts when a laptop battery holds too little of its original capacity.

| | |
|---|---|
| Script | `test-battery-health.ps1` |
| Type | Monitor |
| Category | Monitoring & health checks |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1; administrator rights |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 15 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. For each battery it compares the full-charge capacity (what the battery holds today) with the design capacity (what it held new), as a health percent, and shows the charge cycle count. It alerts when any battery's health is below MinHealthPercent.

Capacity comes from the battery's WMI classes in root\wmi (BatteryStaticData, BatteryFullChargedCapacity, BatteryCycleCount). When those return nothing, the script writes the Windows battery report (powercfg /batteryreport /xml) to a temporary file, reads it, and deletes it. Cycle counts are shown as "not reported" when the battery does not report one, which many do not.

SKIPPED on PCs with no battery (desktops, servers, virtual machines), and when a battery is present but reports no capacity (a UPS attached over USB shows up as a battery on a desktop). Needs administrator rights.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `MinHealthPercent` | Alert when a battery's full-charge capacity is below this percent of its design capacity. Whole number, 1 to 100. Default 60. | `60` | `MinHealthPercent` or `MIN_HEALTH_PERCENT` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-battery-health.ps1
```

Alerts when the battery holds under 60% of its design capacity.

```powershell
.\test-battery-health.ps1 -MinHealthPercent 70 -OutputFormat Json
```

A stricter limit, as JSON.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `MinHealthPercent`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Battery 1 at 54% of design capacity, 612 cycles; limit 60%
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Battery`, `DesignMWh`, `FullChargeMWh`, `HealthPercent`, `CycleCount`, `Healthy`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-battery-health

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
