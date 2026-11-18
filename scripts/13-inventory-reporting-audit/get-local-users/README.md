# Local user accounts on this PC

> Lists every local account on this PC with its status, last logon, password settings and administrator membership.

| | |
|---|---|
| Script | `get-local-users.ps1` |
| Type | Report |
| Category | Inventory, reporting & audit |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 15 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It reads every local account (not domain or Entra accounts) and writes one row each: name, SID, enabled, last logon, when the password was last set, whether the password never expires, whether a password is required, whether it is a member of the local Administrators group, and its description. The Flags column names what needs a look:

- BuiltinAdminEnabled - the built-in Administrator (the account whose SID ends in -500, whatever it is renamed to) is enabled.
- PasswordNeverExpires - an ENABLED account whose password never expires.
- Stale - an ENABLED account whose last logon on this PC was more than StaleDays ago, or that has never logged on and whose password was set (or never set) more than StaleDays ago. The last logon is the last time the account logged on to THIS PC; it is not replicated.
- NoPasswordRequired - an ENABLED account that may have an empty password.

The custom field receives the number of enabled local accounts that are members of the Administrators group. The status is OK: a Report does not alert (use test-local-user-hygiene for that). Times are UTC.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `StaleDays` | Days without a logon before an enabled account is flagged Stale. Whole number, 1 to 3650. Default 90. | `90` | `StaleDays` or `STALE_DAYS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-local-users.ps1
```

Lists all local accounts and flags the ones that need a look.

```powershell
.\get-local-users.ps1 -StaleDays 30 -ExportPath C:\Temp\users.csv
```

Flags accounts idle for 30 days and also writes the table to a CSV file.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `StaleDays`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
6 local accounts (2 enabled); 1 enabled administrator; flagged: 1 password never expires, 1 stale
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Name`, `Sid`, `Enabled`, `LastLogonUtc`, `PasswordLastSetUtc`, `PasswordNeverExpires`, `PasswordRequired`, `IsAdministrator`, `Description`, `Flags`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/get-local-users

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
