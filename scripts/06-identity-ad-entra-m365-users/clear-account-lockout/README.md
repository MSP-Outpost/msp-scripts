# User locked out - unlock the account

> Unlocks one or more locked-out Active Directory user accounts.

| | |
|---|---|
| Script | `clear-account-lockout.ps1` |
| Type | Action |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows Server 2016+ (domain controller or domain member) |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, ActiveDirectory module (RSAT-AD-PowerShell), rights to unlock AD accounts |
| Changes | Unlocks the named Active Directory user accounts |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 15 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT CHANGES THINGS. For each user named in AccountName it unlocks the account if, and only if, the account is locked out now, then reads the account again to check it is unlocked. It changes nothing else: not the password, not the enabled state, not the group memberships. An account that is not locked out is left alone and reported as already unlocked, so running it twice is safe. A disabled account that is locked is unlocked but stays disabled, and a warning says so.

Unlocking is Risk Low: it only lets the user try to sign in again. If the lockouts come back, something is still sending the old password; find it with test-account-lockout-source first. Every name is looked up before anything is changed, so one misspelled name stops the run with nothing unlocked.

Run it on a domain controller or a member server with the ActiveDirectory module (RSAT). If the module is missing it ends ERROR; on a computer that is not in a domain it ends SKIPPED.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `AccountName` | The users to unlock, separated by commas or semicolons: the sign-in name (jsmith), DOMAIN\jsmith, or the user principal name. Required. (Named AccountName, not UserName: Windows already has an environment variable called USERNAME, which the runtime would read.) | (empty) | `AccountName` or `ACCOUNT_NAME` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\clear-account-lockout.ps1 -AccountName jsmith
```

Unlocks jsmith if the account is locked out.

```powershell
.\clear-account-lockout.ps1 -AccountName "jsmith, CONTOSO\mjones" -DryRun true
```

Shows which of the two accounts are locked and would be unlocked.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `AccountName`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Unlocked 1 account(s): jsmith
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\clear-account-lockout.log`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/clear-account-lockout

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
