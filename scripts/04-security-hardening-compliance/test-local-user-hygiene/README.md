# Risky local accounts on this PC

> Alerts on an enabled built-in Administrator or Guest, passwords that are old or not required, and accounts with look-like-leftover names.

| | |
|---|---|
| Script | `test-local-user-hygiene.ps1` |
| Type | Monitor |
| Category | Security hardening & compliance |
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

THIS SCRIPT IS READ-ONLY. It reads every local account and writes one row per finding (Account, Sid, Finding, Detail), alerting (exit 1) when there is any:

- BuiltinAdministratorEnabled - the built-in Administrator (the account whose SID ends in -500, whatever it is renamed to) is enabled, unless AllowBuiltinAdmin is true.
- GuestEnabled - the Guest account (SID ending -501) is enabled.
- NoPasswordRequired - an enabled local account that may have an empty password.
- PasswordTooOld - an enabled local account whose password was set more than MaxPasswordAgeDays ago. Accounts that sign in with a Microsoft account are left out of this and the previous check: their password is not managed on this PC.
- SuspectName - an enabled account (other than the built-in Administrator, which has its own finding) whose name matches one of SuspectPatterns, a sign of an old IT provider's leftover account, unless its name matches AllowedAccounts. AllowedAccounts affects only this finding: an approved account with no password or an old password is still reported.

Patterns are case-insensitive PowerShell wildcards (* and ?) and must keep at least 3 letters or digits, so "*" or "a*" is refused. Domain accounts are not looked at.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `AllowBuiltinAdmin` | true when the built-in Administrator is allowed to be enabled (default false). | `false` | `AllowBuiltinAdmin` or `ALLOW_BUILTIN_ADMIN` |
| `MaxPasswordAgeDays` | Oldest password age allowed, in days. Whole number, 1 to 36500. Default 365. | `365` | `MaxPasswordAgeDays` or `MAX_PASSWORD_AGE_DAYS` |
| `SuspectPatterns` | Comma, semicolon or newline separated name patterns that look like a former provider's account. Default "*admin*,itsupport*,msp*,localadmin*,support*". | `*admin*,itsupport*,msp*,localadmin*,support*` | `SuspectPatterns` or `SUSPECT_PATTERNS` |
| `AllowedAccounts` | Account names (wildcards allowed) that are approved and never reported as SuspectName. Default empty. | (empty) | `AllowedAccounts` or `ALLOWED_ACCOUNTS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-local-user-hygiene.ps1
```

Alerts on any of the findings above, using the defaults.

```powershell
.\test-local-user-hygiene.ps1 -AllowedAccounts "msp-rescue,helpdesk*" -MaxPasswordAgeDays 180
```

Approves two names and tightens the password age to 180 days.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `AllowBuiltinAdmin`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
3 local account findings: Administrator: BuiltinAdministratorEnabled; msp-old: SuspectName; tech1: NoPasswordRequired
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Account`, `Sid`, `Finding`, `Detail`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-local-user-hygiene

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
