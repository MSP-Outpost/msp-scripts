# Local admin password - rotate it and store it in a field

> Sets a new random password on a local administrator account (default: the built-in Administrator, whatever it is called) and stores it in an RMM custom field.

| | |
|---|---|
| Script | `set-local-admin-password.ps1` |
| Type | Action |
| Category | Security hardening & compliance |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, an RMM custom field (secure) to receive the password |
| Changes | Sets a new password on one local user account and writes it to the RMM custom field |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 15 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS. It sets a new random 20-character password on one local account:

- AccountName empty (default): the built-in Administrator, found by its SID (the local account whose SID ends in -500), even if it was renamed. It may be disabled; the script does not enable it or change anything except the password.
- AccountName set: that local account. It must exist on this PC.

Every run rotates the password, so running it twice sets two different passwords (the second replaces the first in the field). The password comes from the operating system's cryptographic random number generator and has upper case, lower case, digits and symbols. The password is written to the RMM field BEFORE it is set, so a failed field write changes nothing. Afterwards it checks the password change time, and for an enabled account tries one test logon (security baselines often deny that, so a failed test is only a warning). An account that Windows LAPS manages is skipped.

THE PASSWORD IS NEVER PRINTED. It is not in the output, the answer, the data rows, the change log or the exported file. It is written only to the RMM custom field named by ResultField (NinjaOne, Datto RMM and Syncro are supported). Make that a secure / secret field: the script writes the password as the field value. Without ResultField, or on an RMM it cannot write to, it refuses before changing anything ("set ResultField to a secure custom field so the password is not lost"). OutputFormat Answer is refused for the same reason. With a ResultField set the runtime never overwrites it with a status or error message. If the field write fails the run ends in ERROR before the account is touched.

Domain accounts and domain controllers: a domain controller has no local accounts and the script refuses to run there (ERROR). It changes only local accounts; it does not touch group membership, expiry settings or sessions. A user signed in as that account stays signed in. Programs, scheduled tasks and services that run as the account with the old password will fail to sign in, so use this on break-glass and built-in accounts, not on accounts something depends on.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `AccountName` | The local account to rotate. Default empty: the built-in Administrator (SID ending in -500). | (empty) | `AccountName` or `ACCOUNT_NAME` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\set-local-admin-password.ps1 -ResultField LocalAdminPassword
```

Rotates the built-in Administrator's password and stores it in the field.

```powershell
.\set-local-admin-password.ps1 -AccountName msp-breakglass -ResultField LocalAdminPassword
```

Rotates that account's password.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `AccountName`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Password for local account Administrator rotated; password written to field LocalAdminPassword
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\set-local-admin-password.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/set-local-admin-password

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
