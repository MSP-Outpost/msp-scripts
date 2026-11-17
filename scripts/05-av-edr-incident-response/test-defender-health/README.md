# Is Microsoft Defender actually protecting this PC - end-to-end health

> Alerts when Microsoft Defender is off, out of date, unscanned or not really protecting the PC.

| | |
|---|---|
| Script | `test-defender-health.ps1` |
| Type | Monitor |
| Category | AV / EDR & incident response |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1; Microsoft Defender; administrator rights |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 15 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It reads Get-MpComputerStatus and Get-MpPreference and checks, one row each: antivirus enabled, real-time protection on, tamper protection on, signature age, time since the last scan, and the engine and platform versions (shown, never alerted on).

When another antivirus is active Defender runs in passive mode (or EDR block mode), or is simply not running. Whenever Defender is not the active antivirus the script reads Windows Security Center on workstations, reports which product protects the PC and whether its signatures are up to date, and skips the Defender-only checks. No other active antivirus, or one with out-of-date signatures, is an alert. Windows Security Center does not exist on servers, so a passive server is reported but not alerted on.

SKIPPED on a Windows Server where Microsoft Defender is not installed.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `MaxSignatureAgeHours` | Alert when the antivirus signatures are older than this many hours. Whole number, 0 to 87600. Default 48. 0 alerts on any age (useful for testing). | `48` | `MaxSignatureAgeHours` or `MAX_SIGNATURE_AGE_HOURS` |
| `MaxScanAgeDays` | Alert when the newest quick or full scan is older than this many days, or no scan is recorded. Whole number, 0 to 3650. Default 14. 0 turns the scan check off. | `14` | `MaxScanAgeDays` or `MAX_SCAN_AGE_DAYS` |
| `RequireTamperProtection` | Alert when tamper protection is off. true or false. Default true. Applies to workstations only; Windows Server before 2022 has no tamper protection. | `true` | `RequireTamperProtection` or `REQUIRE_TAMPER_PROTECTION` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-defender-health.ps1 -MaxSignatureAgeHours 24
```

Alerts when signatures are more than a day old, or Defender is off.

```powershell
.\test-defender-health.ps1 -MaxScanAgeDays 0 -OutputFormat Json
```

Skips the scan-age check and prints one JSON object.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `MaxSignatureAgeHours`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Defender on: real-time on, signatures 6 h old, last scan 2 days ago
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Check`, `Value`, `Healthy`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-defender-health

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
