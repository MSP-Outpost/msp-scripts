# Is Active Directory healthy - services, replication, FSMO, dcdiag

> Alerts when this domain controller's Active Directory services, replication, FSMO roles, shares or dcdiag tests are unhealthy.

| | |
|---|---|
| Script | `test-ad-health.ps1` |
| Type | Monitor |
| Category | Server roles (AD DS, Hyper-V, SQL, IIS, file, RDS) |
| Platforms | Windows Server 2016+ (domain controller) |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, ActiveDirectory module (RSAT-AD-PowerShell), dcdiag.exe |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 2 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. Run it on a domain controller. It checks, in order:

1. Services: NTDS, Netlogon, KDC and W32Time must be running. DNS and DFSR must be running when they are installed (a domain controller that does not host DNS, or still uses the old FRS for SYSVOL, is not an alert).
2. Shares: SYSVOL and NETLOGON must be shared.
3. FSMO roles: the five role holders (schema master, domain naming master, PDC emulator, RID master, infrastructure master) must answer on the directory port (TCP 389).
4. Replication: every replication partner of this domain controller must show a last result of success, no consecutive failures, and a last success newer than MaxReplicationAgeHours. This reads the same data as repadmin /replsummary, but through typed values instead of text, so it works in every Windows language. A single-domain-controller forest has no partners: that is healthy, not an alert.
5. dcdiag: runs "dcdiag /q" (quiet: prints only what failed) and alerts when it prints anything or exits non-zero. The event-log tests (SystemLog, DFSREvent, KccEvent, FrsEvent) are skipped: they fail on any warning event of the last 24 hours, so one restart alerts for a day.

Each check is one row. On a computer that is not a domain controller it ends SKIPPED. If the ActiveDirectory module is missing it ends ERROR.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `MaxReplicationAgeHours` | Alert when a replication partner's last successful replication is older than this many hours. Whole number, 1 to 720. Default 24. | `24` | `MaxReplicationAgeHours` or `MAX_REPLICATION_AGE_HOURS` |
| `RunDcdiag` | Run the dcdiag check. true or false. Default true. Set false when dcdiag takes too long for your RMM's script timeout. | `true` | `RunDcdiag` or `RUN_DCDIAG` |
| `DcdiagTimeoutSeconds` | Stop dcdiag after this many seconds and count that as a failure. Whole number, 30 to 1800. Default 300. | `300` | `DcdiagTimeoutSeconds` or `DCDIAG_TIMEOUT_SECONDS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-ad-health.ps1
```

Checks this domain controller and alerts on any failed check.

```powershell
.\test-ad-health.ps1 -MaxReplicationAgeHours 6 -RunDcdiag false
```

Stricter replication age, without the slow dcdiag run.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `MaxReplicationAgeHours`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
AD healthy on DC01: 6 services, 2 shares, 5 FSMO roles, replication OK (2 partners), dcdiag clean
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Check`, `Target`, `Status`, `Detail`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/test-ad-health

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
