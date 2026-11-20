# Reset an AD user's password - random, forced change at logon

> Resets an Active Directory user's password to a random value, stores it in a secure RMM field and makes the user change it at next sign-in.

| | |
|---|---|
| Script | `reset-ad-user-password.ps1` |
| Type | Action |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows Server 2016+ (domain controller or domain member) |
| Runs as | System |
| Requires | PowerShell 5.1; admin rights; ActiveDirectory module; rights to reset passwords; a secure RMM field |
| Changes | Sets a new random password on one AD user, can require a change at next sign-in and unlock the account, and writes the password to the RMM custom field |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 15 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## What it does

THIS SCRIPT CHANGES THINGS. For the one user in AccountName it:

1. Sets a new random 20-character password (upper and lower case letters, digits and symbols, from the operating system's cryptographic random number generator).
2. When ChangePasswordAtLogon is true (the default), makes the user choose a new password at the next sign-in (pwdLastSet = 0).
3. When UnlockAccount is true (the default) and the account is locked out, unlocks it.

THE PASSWORD IS NEVER PRINTED. It is not in the output, the answer, the data rows, the change log or an exported file. It is written only to the RMM custom field named by ResultField (NinjaOne, Datto RMM and Syncro are supported); make that a secure / secret field. Without ResultField, or on an RMM it cannot write to, the script refuses before changing anything. OutputFormat Answer is refused for the same reason. The password is written to the field BEFORE it is set, so a failed field write changes nothing.

Second run: with ChangePasswordAtLogon true, an account that already must change its password at next sign-in is left alone and the script ends OK "Already pending" (the password in the field is still the one that works). Set ForceReset=true to issue a new password anyway. With ChangePasswordAtLogon false there is no such state, so every run issues a new password.

Never touched: the built-in accounts (RIDs 500 to 503, including krbtgt) and anything marked as a critical system object. A password-never-expires account cannot be forced to change at next sign-in (Active Directory refuses): set ChangePasswordAtLogon=false for those. A disabled account gets the new password and stays disabled; the script never enables it.

This script resets domain accounts only. For a local account use set-local-admin-password. Run it on a domain controller or a member server with the ActiveDirectory module (RSAT). Without the module it ends ERROR; on a computer that is not in a domain it ends SKIPPED.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `AccountName` | The user: the sign-in name (jsmith), DOMAIN\jsmith, or the user principal name. Required. (Named AccountName, not UserName: Windows already has an environment variable called USERNAME.) | (empty) | `AccountName` or `ACCOUNT_NAME` |
| `ChangePasswordAtLogon` | true to make the user change the password at next sign-in. Default true. | `true` | `ChangePasswordAtLogon` or `CHANGE_PASSWORD_AT_LOGON` |
| `UnlockAccount` | true to also unlock a locked-out account. Default true. | `true` | `UnlockAccount` or `UNLOCK_ACCOUNT` |
| `ForceReset` | true to issue a new password even when the user already must change it at next sign-in. Default false. | `false` | `ForceReset` or `FORCE_RESET` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\reset-ad-user-password.ps1 -AccountName jsmith -ResultField UserPassword
```

Resets jsmith's password, stores it in the field and forces a change at next sign-in.

```powershell
.\reset-ad-user-password.ps1 -AccountName svc-scan -ChangePasswordAtLogon false -ResultField 5
```

Resets a service account's password without forcing a change.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `AccountName`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Password for jsmith reset; must change at next sign-in; password written to field UserPassword
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\reset-ad-user-password.log`.

## Changelog

- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/reset-ad-user-password

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
