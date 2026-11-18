# Did last night's backup succeed?

> Alerts when last night's backup failed or is older than you allow, for the backup products that leave evidence on this PC.

| | |
|---|---|
| Script | `test-backup-status.ps1` |
| Type | Monitor |
| Category | Backup & DR |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1; administrator rights (event logs) |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 20 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. It looks for the backup products below, reads the evidence each one leaves on this machine, and writes one row per product found: when it last succeeded and how its newest run ended. It alerts (exit 1) when a product's newest run failed, when its last success is older than MaxAgeHours, or when the service of a product it cannot read is set to start automatically but is not running. It is SKIPPED when no supported product is found.

A run that finished with a warning counts as a completed backup and is shown as Warning; it does not alert. Results are read per product, not per job: if one product runs several jobs, a failed job followed by a successful job of the same product reads as the newest result.

Only event IDs, event levels, provider names and service names are used, never message text, so it works on any Windows language. The evidence used and how far to trust it, per product:

Veeam Agent for Windows - Veeam event logs other than "Veeam Backup" (the agent's own log, for example "Veeam Agent"): job-finished event 190, its level gives the result (information = success, warning, error = failed). Detected by that log having job events or by the service VeeamEndpointBackupSvc. Confidence: medium (levels follow what Veeam documents for B&R job sessions; not confirmed on every agent version).

Veeam Backup & Replication server - the "Veeam Backup" log, event 190 with the same level rule. Detected by that log having job events or by the service VeeamBackupSvc. Backup copy jobs and the configuration backup are not read. Confidence: medium.

Windows Server Backup (wbadmin) - the Microsoft-Windows-Backup log: events 4 and 14 are success; 5, 8, 9, 20, 21, 22, 49, 517, 521, 561 and 564 are failure. Detected only when the log holds one of those events, so a schedule that has never run is not seen. Confidence: high for 4, 5 and 49; medium for the rest.

Macrium Reflect - Application log events whose provider name starts with "Macrium": the level gives the result (information = success, warning, error = failed). Reflect also logs other information events, so a start event can read as a success. Confidence: low. Without such events the product is read like the service-only products below.

Acronis Cyber Protect, Datto Windows Agent / Datto Cloud Continuity, Synology Active Backup for Business agent - only the service is read (running, and whether it starts automatically). The last backup result is not readable locally: the row says so and the script does not alert on it. For Acronis the row also notes error events from an "Acronis" provider in the Application log within MaxAgeHours, without alerting on them. Confidence: service only.

When every product found is service-only the answer says that results could not be read, with status OK: check those products in their consoles.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `MaxAgeHours` | Alert when a product's newest successful backup is older than this many hours. Whole number, 1 to 8760. Default 26 (a nightly backup plus slack). | `26` | `MaxAgeHours` or `MAX_AGE_HOURS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-backup-status.ps1
```

Checks every supported backup product found; alerts when one failed or is more than 26 hours old.

```powershell
.\test-backup-status.ps1 -MaxAgeHours 50 -OutputFormat Json
```

Allows a backup that runs every other night and prints one JSON object.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `MaxAgeHours`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Veeam Agent for Windows: last success 5 h ago; Windows Server Backup: last success 19 h ago
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Product`, `LastSuccess`, `LastResult`, `Evidence`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/test-backup-status

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
