# Windows LAPS not configured or not backing up

> Alerts when Windows LAPS is not configured on this PC or has stopped backing the local admin password up to Entra ID or Active Directory.

| | |
|---|---|
| Script | `test-windows-laps.ps1` |
| Type | Monitor |
| Category | Security hardening & compliance |
| Platforms | Windows 11, Windows 10 April 2023+, Server 2019+ |
| Runs as | System |
| Requires | PowerShell 5.1; administrator rights; Windows LAPS (laps.dll) |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 10 seconds |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## What it does

THIS SCRIPT IS READ-ONLY. Run it on the device itself (as SYSTEM from your RMM). It reads, locally:

1. whether this Windows has Windows LAPS at all (laps.dll in the Windows system folder); when it does not, it is SKIPPED;
2. the ACTIVE Windows LAPS policy: Windows LAPS looks at four registry roots in a fixed order (LAPS CSP, Group Policy, local configuration, legacy Microsoft LAPS) and uses the first root that has at least one value. It reads BackupDirectory (0 disabled, 1 Microsoft Entra ID, 2 Active Directory), AdministratorAccountName and PasswordAgeDays (default 30) from that root. No policy, or BackupDirectory 0, is an ALERT. When the legacy Microsoft LAPS root is the active one the directory is taken to be Active Directory (the event log example for legacy policy says so) and the legacy value names are not read;
3. the Windows LAPS event log (Microsoft-Windows-LAPS/Operational), by event ID only: the newest success event for the directory (10029 for Entra ID, 10018 for Active Directory), and the newest policy-processing result (10004 succeeded, 10005 failed). It ALERTS when there is no success event, when the newest one is older than PasswordAgeDays plus 2 days, or when the newest policy-processing result is a failure. It never reads, prints or resets a password and never changes the policy. The event log keeps a limited history: a quiet device whose log has rolled over can show "no success event" even though backups work; the answer says so.

Microsoft says the managed password is rotated when it expires and Windows LAPS checks its policy every hour, so a healthy device logs a success event at least every PasswordAgeDays.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `ExpectedDirectory` | Where the password must be backed up: Any (default; any enabled directory is fine), EntraId or ActiveDirectory. A different directory is an ALERT. | `Any` | `ExpectedDirectory` or `EXPECTED_DIRECTORY` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-windows-laps.ps1
Alerts unless Windows LAPS is configured and its last password backup is recent.
```

```powershell
.\test-windows-laps.ps1 -ExpectedDirectory EntraId
Also alerts when the policy backs the password up to Active Directory instead of Entra ID.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `ExpectedDirectory`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Windows LAPS backs up to Entra ID; last backup 3 days ago; password age 30 days
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

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/test-windows-laps

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
