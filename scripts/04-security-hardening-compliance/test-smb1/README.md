# SMBv1 still enabled - find where and who uses it

> Alerts when the old, unsafe SMBv1 protocol is still switched on (server, optional feature or client), and lists who still uses it.

| | |
|---|---|
| Script | `test-smb1.ps1` |
| Type | Monitor |
| Category | Security hardening & compliance |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1; SmbShare and DISM modules; administrator rights |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It checks three places SMB1 can be on:

- the SMB server setting (Get-SmbServerConfiguration, EnableSMB1Protocol),
- the Windows optional features SMB1Protocol, SMB1Protocol-Client and SMB1Protocol-Server (Enabled or EnablePending is on),
- the SMB1 client driver mrxsmb10 (its driver file is present and its service is not disabled).

Any of them on is an alert. With AuditDays above 0 it also reads the SMB server audit log (Microsoft-Windows-SMBServer/Audit, event 3000, "SMB1 access") for that many days and lists the client addresses that still used SMB1, with how many times. Turning that auditing on is not this script's job: when it is off the script says so, and an empty list then means "unknown", not "nobody". Enable it with Set-SmbServerConfiguration -AuditSmb1Access $true, wait a few weeks, then read this list before running disable-smb1.

After disable-smb1 the SMB1 client driver file stays until the next restart, so the client line can still alert until then.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `AuditDays` | How many days of the SMB1 access audit log to read. Whole number 0 to 365; 0 skips the audit. Default 7. | `7` | `AuditDays` or `AUDIT_DAYS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-smb1.ps1
```

Alerts when SMB1 is on anywhere, and lists clients seen using it in the last 7 days.

```powershell
.\test-smb1.ps1 -AuditDays 30 -OutputFormat Json
```

Reads 30 days of the audit log and prints one JSON object.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `AuditDays`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
SMB1 server is enabled; SMB1 optional feature SMB1Protocol is enabled; 2 clients used SMB1 in the last 7 days (10.0.0.5, 10.0.0.9)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Check`, `Item`, `Detail`, `Problem`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-smb1

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
