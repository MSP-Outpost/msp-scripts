# Break-glass local admin - create or reset it

> Creates (or resets) a break-glass local administrator with a random 20-character password and stores the password in an RMM custom field.

| | |
|---|---|
| Script | `new-local-admin-account.ps1` |
| Type | Action |
| Category | Onboarding & provisioning |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, an RMM custom field (secure) to receive the password |
| Changes | Creates or resets a local user account, adds it to the local Administrators group, writes its password to the RMM custom field |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 15 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS. It makes sure a local administrator account named AccountName exists, as the MSP's emergency way in when the domain, Entra ID or the usual admin account is unreachable.

- Account missing: it creates it with a random 20-character password, enables it, and adds it to the local Administrators group (found by its SID, so it works in any language).
- Account exists, RotatePassword false (default): nothing changes. If this script created it (or reset it) earlier on this PC, whose password is therefore in your RMM field, the run reports OK and only warns when the account is disabled or not an administrator. If the account exists for any other reason the run says SKIPPED: "exists; password not managed by this script - set RotatePassword=true to store one". Accounts that Windows LAPS manages are skipped.
- Account exists, RotatePassword true: it sets a new random password, enables the account and puts it back in Administrators if it was removed.

PasswordNeverExpires (default true) is applied on create and on reset. The password comes from the operating system's cryptographic random number generator (RandomNumberGenerator) and has upper case, lower case, digits and symbols. The password is written to the RMM field BEFORE it is set on the account, so a failed field write changes nothing. Afterwards the script tries one test logon; security baselines often deny that, so a failed test is only a warning.

THE PASSWORD IS NEVER PRINTED. It is not in the output, the answer, the data rows, the change log or the exported file. It is written only to the RMM custom field named by ResultField (NinjaOne, Datto RMM and Syncro are supported). Make that a secure / secret field: the script writes the password as the field value. When the script has to set a password and ResultField is not set, or the RMM is not one it can write to, it refuses before changing anything ("set ResultField to a secure custom field so the password is not lost"). OutputFormat Answer is refused for the same reason. With a ResultField set the runtime never overwrites it with a status message. If the field write fails the run ends in ERROR before the account is touched.

It never touches the built-in Administrator (that is set-local-admin-password), domain accounts, or other administrators. A domain controller has no local accounts: it ends in ERROR.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `AccountName` | The account name, 1 to 20 letters, digits, dot, underscore or hyphen. Default msp-breakglass. | `msp-breakglass` | `AccountName` or `ACCOUNT_NAME` |
| `Description` | The account description, up to 48 characters. Default "MSP break-glass administrator". | `MSP break-glass administrator` | `Description` or `DESCRIPTION` |
| `RotatePassword` | true to set a new password on an account that already exists. Default false. | `false` | `RotatePassword` or `ROTATE_PASSWORD` |
| `PasswordNeverExpires` | true (default) so the break-glass password never expires; false to follow the PC's password policy. | `true` | `PasswordNeverExpires` or `PASSWORD_NEVER_EXPIRES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\new-local-admin-account.ps1 -ResultField BreakGlassPassword
```

Creates msp-breakglass as an administrator and stores its password in the BreakGlassPassword field.

```powershell
.\new-local-admin-account.ps1 -AccountName msp-rescue -RotatePassword true -ResultField BreakGlassPassword
```

Sets a new password on msp-rescue and stores it.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `AccountName`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Break-glass admin msp-breakglass created; password written to field BreakGlassPassword
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\new-local-admin-account.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/new-local-admin-account

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
