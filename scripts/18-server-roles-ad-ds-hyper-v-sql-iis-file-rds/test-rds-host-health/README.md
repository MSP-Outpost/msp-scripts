# Is the RDS session host healthy

> Alerts when a Remote Desktop Session Host has a problem: service down, old disconnected sessions, licensing not set up, broker unreachable.

| | |
|---|---|
| Script | `test-rds-host-health.ps1` |
| Type | Monitor |
| Category | Server roles (AD DS, Hyper-V, SQL, IIS, file, RDS) |
| Platforms | Windows Server 2016+ with the Remote Desktop Session Host role |
| Runs as | System |
| Requires | PowerShell 5.1; administrator rights; the Remote Desktop Session Host role on this server |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. It runs ON a Remote Desktop Session Host (RDSH). A PC or server without the Session Host role is SKIPPED (the WMI class Win32_TerminalServiceSetting reports TerminalServerMode 1 only when the role is installed). It alerts (exit 1) when

- the Remote Desktop Services service (TermService) is not running, or the host refuses Remote Desktop connections (fDenyTSConnections);
- a session has been disconnected for more than MaxDisconnectedHours hours (sessions are read with the Windows Terminal Services API, not by parsing the localized text of quser);
- licensing is not set up, meaning the licensing mode is not Per User or Per Device, or no Remote Desktop licence server is configured (the WMI method GetSpecifiedLicenseServerList, or the group policy value LicenseServers), AND the grace period (WMI method GetGracePeriodDays) has MinGraceDays days or fewer left, or cannot be read. While the grace period is long, the gap is shown but is not an alert;
- a Connection Broker is configured (SessionDirectoryActive and SessionDirectoryLocation, from the local setting or the group policy) and this host cannot open a TCP connection to it on port 135 (the RPC endpoint mapper, which the broker's own RPC services also need). This is a reachability check, not proof that the broker's services are healthy.

The table lists the active and disconnected session counts, the licensing mode, licence server and grace period, the broker, and every session that is over the limit. The script does not count Client Access Licences: those are held by the licence server, which this host cannot read. It changes nothing, signs nobody out and ends no session.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `MaxDisconnectedHours` | Alert on a session that has been disconnected for more than this many hours. Whole number, 1 to 8760. Default 24. | `24` | `MaxDisconnectedHours` or `MAX_DISCONNECTED_HOURS` |
| `MinGraceDays` | When licensing is not set up, alert once the grace period has this many days or fewer left. Whole number, 0 to 365. Default 30. | `30` | `MinGraceDays` or `MIN_GRACE_DAYS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-rds-host-health.ps1
Alerts on sessions disconnected over 24 hours and on licensing with 30 days or less of grace.
```

```powershell
.\test-rds-host-health.ps1 -MaxDisconnectedHours 8 -MinGraceDays 14 -OutputFormat Json
Stricter session limit, shorter licensing warning, one JSON object.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `MaxDisconnectedHours`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Sessions CONTOSO\jsmith (session 3) disconnected 41.2 h (limit 24 h); Licensing Grace period 12 days left; no licence server configured
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Check`, `Item`, `Value`, `IsProblem`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/test-rds-host-health

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
