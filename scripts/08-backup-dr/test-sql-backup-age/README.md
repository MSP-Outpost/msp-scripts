# SQL Server backups too old

> Alerts when a SQL Server database has no recent FULL backup, or a FULL-recovery database has no recent log backup.

| | |
|---|---|
| Script | `test-sql-backup-age.ps1` |
| Type | Monitor |
| Category | Backup & DR |
| Platforms | Windows Server 2016+ with SQL Server 2012+ installed locally |
| Runs as | System |
| Requires | PowerShell 5.1; SQL Server on this server; a Windows login for the run account with msdb read access |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. It finds every SQL Server database engine instance installed on this server (the registry key Instance Names\SQL), connects to each running one with Windows authentication through the .NET class System.Data.SqlClient (no SqlServer module needed), and reads msdb.dbo.backupset for every ONLINE database except tempdb: the last FULL, the last DIFFERENTIAL and the last LOG backup. It alerts (exit 1) when

- the last FULL backup is older than MaxFullHours, or there is none, or
- a database in FULL or BULK_LOGGED recovery has no LOG backup within MaxLogHours (it has not yet had a FULL backup: the log chain has not started, so only the FULL problem is reported).

Rules that avoid false alerts: a database created less than MaxFullHours ago with no backup yet is not alerted; copy-only backups do not count (they are not part of the regular backup chain); database snapshots, the model database's log, and read-only databases' logs are not checked; the ExcludeDatabases input lists exact names to leave out (a test database). Backups taken by another tool that does not write to msdb (some third-party and image-level backups) are invisible here, as is a backup history that was cleaned from msdb. Availability group secondaries are not handled: run it where the backups are taken. Failover cluster instances: run it on the active node.

WHO RUNS IT: the script connects as the account that runs it, normally NT AUTHORITY\SYSTEM from an RMM. Whether SYSTEM may log in depends on the SQL Server version and on how it was installed: older installations made SYSTEM a sysadmin; newer ones may not, and some hardened servers remove it. When the login or a read is refused, the script ends ERROR and prints SQL Server's own message and the account name. Create a login for that account with read access to msdb (the backup history tables) and the permission VIEW ANY DATABASE, or run the script as a user that has them. Nothing is written to SQL Server.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `MaxFullHours` | Alert when the last FULL backup is older than this many hours. Whole number, 1 to 8760. Default 26 (a nightly backup plus two hours). | `26` | `MaxFullHours` or `MAX_FULL_HOURS` |
| `MaxLogHours` | Alert when a FULL or BULK_LOGGED recovery database has no LOG backup within this many hours. Whole number, 1 to 8760. Default 4. | `4` | `MaxLogHours` or `MAX_LOG_HOURS` |
| `ExcludeDatabases` | Exact database names to leave out, separated by commas or semicolons. No wildcards. Default empty. | (empty) | `ExcludeDatabases` or `EXCLUDE_DATABASES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-sql-backup-age.ps1
Alerts on a FULL backup older than 26 hours or a missing log backup older than 4 hours.
```

```powershell
.\test-sql-backup-age.ps1 -MaxFullHours 170 -MaxLogHours 1 -ExcludeDatabases "ReportsTest;Scratch"
A weekly FULL schedule, hourly log backups, two databases left out.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `MaxFullHours`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
2 database(s) with backup problems: SQL01 Sales FULL backup 41 h old; SQL01 Orders no LOG backup within 4 h
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Instance`, `Database`, `Recovery`, `LastFullUtc`, `FullAgeHours`, `LastDiffUtc`, `LastLogUtc`, `LogAgeHours`, `Problem`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/test-sql-backup-age

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
