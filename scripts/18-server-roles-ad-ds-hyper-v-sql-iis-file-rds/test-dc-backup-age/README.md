# Domain controller backup too old

> Alerts when this domain controller's last Active Directory backup is older than N days.

| | |
|---|---|
| Script | `test-dc-backup-age.ps1` |
| Type | Monitor |
| Category | Server roles (AD DS, Hyper-V, SQL, IIS, file, RDS) |
| Platforms | Windows Server 2016+ (domain controller) |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, ActiveDirectory module (RSAT-AD-PowerShell), run on the domain controller |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 15 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## What it does

THIS SCRIPT IS READ-ONLY. A system-state or Active Directory backup stamps the dSASignature attribute on the head of every directory partition (naming context) the domain controller holds; that is what "repadmin /showbackup" reads. This script reads the replication metadata of that attribute for each naming context (domain, configuration, schema and any application partition such as DomainDnsZones) with Get-ADReplicationAttributeMetadata and takes the time it was last changed as the time of the last backup. It does not parse repadmin's text, which is translated on non-English servers.

One row per naming context: when it was last backed up (UTC), the age in days and OK or FAIL. ALERT when any naming context was last backed up more than MaxAgeDays days ago, has no backup recorded, or cannot be read. The answer names the oldest.

A domain controller that was never backed up may still show the time it was created for dSASignature; then the age is that of the installation. Backups taken by a product that does not call the Active Directory backup API (a file copy of the database) do not move this time.

Run it on each domain controller. On any other computer it ends SKIPPED; without the ActiveDirectory module it ends ERROR.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `MaxAgeDays` | The oldest acceptable last backup, in days. Whole number 1 to 365. Default 7. | `7` | `MaxAgeDays` or `MAX_AGE_DAYS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-dc-backup-age.ps1 -MaxAgeDays 3
```

Alerts when any partition on this domain controller was last backed up more than 3 days ago.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `MaxAgeDays`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Last AD backup 1.3 days ago (limit 7) on DC=contoso,DC=com; 5 naming context(s) checked
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `NamingContext`, `LastBackupUtc`, `AgeDays`, `Status`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/test-dc-backup-age

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
