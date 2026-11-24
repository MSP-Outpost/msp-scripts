# Is SQL Server healthy

> Alerts when SQL Server is unhealthy: service or Agent stopped, a database not online, a full log, a failed job, an old backup.

| | |
|---|---|
| Script | `test-sql-server-health.ps1` |
| Type | Monitor |
| Category | Server roles (AD DS, Hyper-V, SQL, IIS, file, RDS) |
| Platforms | Windows Server 2016+ with SQL Server 2012+ installed locally |
| Runs as | System |
| Requires | PowerShell 5.1; SQL Server on this server; a Windows login with VIEW SERVER STATE and msdb read |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. It finds every SQL Server database engine instance installed on this server (the registry key Instance Names\SQL) and, for each, raises an alert (exit 1) when

- the SQL Server service is not running (the other checks are then not possible and are skipped for that instance);
- the SQL Server Agent service exists, is not disabled, and is not running (SQL Server Express has no working Agent and is not flagged);
- a database is not ONLINE (sys.databases state: OFFLINE, SUSPECT, RECOVERY_PENDING, EMERGENCY, RESTORING and so on). A log-shipping secondary or mirror is RESTORING by design: put it in ExcludeDatabases;
- a database's transaction log is more than MaxLogUsedPercent full (DBCC SQLPERF(LOGSPACE)), counting only logs of MinLogSizeMB or more, because a tiny log at 99% simply grows;
- an Agent job had a failed run (job outcome, not a single step) in the last FailedJobHours hours (msdb.dbo.sysjobhistory);
- an ONLINE database other than tempdb has no FULL backup within MaxFullHours (msdb.dbo.backupset; copy-only backups do not count; a database created less than MaxFullHours ago is not alerted).

It connects with Windows authentication through the .NET class System.Data.SqlClient (no SqlServer module needed) and writes nothing. Backups made by tools that do not write to msdb are invisible here. Failover cluster instances: run it on the active node (a passive node shows its service stopped).

WHO RUNS IT: the script connects as the account that runs it, normally NT AUTHORITY\SYSTEM from an RMM. Whether SYSTEM may log in depends on the SQL Server version and on how it was installed: older installations made SYSTEM a sysadmin; newer ones may not, and some hardened servers remove it. When the login or a read is refused, the script ends ERROR and prints SQL Server's own message and the account name. Give that account a login with VIEW SERVER STATE, VIEW ANY DATABASE, read access to msdb, and (for the failed-job check) membership of the msdb role SQLAgentReaderRole, or run the script as a user that has them.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `MaxLogUsedPercent` | Alert when a transaction log is more than this percent full. Whole number, 1 to 99. Default 90. | `90` | `MaxLogUsedPercent` or `MAX_LOG_USED_PERCENT` |
| `MinLogSizeMB` | Only logs at least this big (MB) are checked for fullness. Whole number, 0 to 10000000. Default 100. | `100` | `MinLogSizeMB` or `MIN_LOG_SIZE_MB` |
| `FailedJobHours` | Look for failed Agent jobs this many hours back. Whole number, 1 to 720. Default 24. | `24` | `FailedJobHours` or `FAILED_JOB_HOURS` |
| `MaxFullHours` | Alert when a database has no FULL backup within this many hours. Whole number, 1 to 8760. Default 26. | `26` | `MaxFullHours` or `MAX_FULL_HOURS` |
| `ExcludeDatabases` | Exact database names to leave out of every database check, separated by commas or semicolons. No wildcards. Default empty. | (empty) | `ExcludeDatabases` or `EXCLUDE_DATABASES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-sql-server-health.ps1
Checks every local instance with the defaults.
```

```powershell
.\test-sql-server-health.ps1 -MaxLogUsedPercent 80 -FailedJobHours 12 -ExcludeDatabases "ReportsStandby" -OutputFormat Json
A stricter log limit, 12 hours of job history, one secondary left out, one JSON object.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `MaxLogUsedPercent`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
SQL01: Agent service stopped; database Sales is SUSPECT; Orders log 96% full (8192 MB); 2 failed job(s) in 24 h
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Instance`, `ServiceState`, `AgentState`, `DatabasesNotOnline`, `WorstLogUsedPercent`, `FailedJobs`, `OldFullBackups`, `Problem`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/test-sql-server-health

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
