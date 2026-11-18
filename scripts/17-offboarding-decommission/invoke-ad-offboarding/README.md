# Employee left - disable in AD, strip groups, move, log off

> Offboards a departed employee in Active Directory: disables the account, resets the password, removes groups, moves it and logs off sessions.

| | |
|---|---|
| Script | `invoke-ad-offboarding.ps1` |
| Type | Action |
| Category | Offboarding & decommission |
| Platforms | Windows Server 2016+ (domain controller or domain member) |
| Runs as | System |
| Requires | PowerShell 5.1, admin rights, ActiveDirectory module (RSAT-AD-PowerShell), rights to change AD users and groups |
| Changes | Disables the user, resets the password, removes group memberships (saved first), stamps the description, moves the account, hides it from address lists and logs off its sessions on this computer |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=invoke-ad-offboarding`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\invoke-ad-offboarding.log`.
- Before it edits or deletes configuration, it copies it to `%ProgramData%\MSPOutpost\Backups\invoke-ad-offboarding\<UTC time>\` and keeps the last 10 runs. If a backup fails, nothing is changed.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. Risk is High, so it is a dry run unless you set BOTH DryRun=false AND Approve=invoke-ad-offboarding (typing the script name is the deliberate step), and it refuses to run when the plan is more than MaxChanges (default 25) separate changes: each group removal counts as one. First look at the dry-run list, then run it for real.

For the one user in AccountName it does, in this order:

1. Disables the account.
2. Resets the password to a long random value that is never printed, logged or stored (nobody, including you, can sign in with it).
3. Removes the user from every group except Domain Users. Each removal is its own row with the group's distinguished name, and the full list is saved as a CSV (original location, description, enabled state, every group) under %ProgramData%\MSPOutpost\Backups\invoke-ad-offboarding\, so memberships can be restored.
4. Writes "Offboarded by MSP Outpost on <date>" in front of the description (the old text is kept after it).
5. Moves the account to DisabledOu, when you set it.
6. Hides the user from address lists (msExchHideFromAddressLists = true), when HideFromAddressLists is true AND the directory has that attribute (it exists only where Exchange has extended the schema; otherwise this step is skipped with a note).
7. Logs off the user's sessions on the computer running the script, when LogOffSessions is true (a named job of this script). Sessions on other servers are not touched.

Not done here, so do it separately: Microsoft 365 or Entra ID offboarding (licences, mailbox, sign-in sessions), a directory sync, and anything outside Active Directory. The account is not deleted.

Never touched: the built-in accounts (RIDs 500 to 503) and anything marked as a critical system object.

Second run: an account that is disabled, stamped, in no group but Domain Users, and already in DisabledOu has nothing left to do: it says OK "Already offboarded". The password is reset only once (while the account is still enabled or not yet stamped).

Run it on a domain controller or a member server with the ActiveDirectory module (RSAT). If the module is missing it ends ERROR; on a computer that is not in a domain it ends SKIPPED.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `AccountName` | The user to offboard: the sign-in name (jsmith), DOMAIN\jsmith, or the user principal name. Required. (Named AccountName, not UserName: Windows already has an environment variable called USERNAME, which the runtime would read.) | (empty) | `AccountName` or `ACCOUNT_NAME` |
| `DisabledOu` | The OU or container to move the account to, as a distinguished name, e.g. "OU=Disabled Users,DC=contoso,DC=com". Default empty: the account is not moved. When set, it must exist; the script never creates it. | (empty) | `DisabledOu` or `DISABLED_OU` |
| `HideFromAddressLists` | Hide the user from address lists when the directory has the msExchHideFromAddressLists attribute. true or false. Default true. | `true` | `HideFromAddressLists` or `HIDE_FROM_ADDRESS_LISTS` |
| `LogOffSessions` | Log the user off any session on this computer. true or false. Default true. | `true` | `LogOffSessions` or `LOG_OFF_SESSIONS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\invoke-ad-offboarding.ps1 -AccountName jsmith -DisabledOu "OU=Disabled Users,DC=contoso,DC=com"
```

Dry run: lists every change that would be made for jsmith.

```powershell
.\invoke-ad-offboarding.ps1 -AccountName jsmith -DisabledOu "OU=Disabled Users,DC=contoso,DC=com" -DryRun false -Approve invoke-ad-offboarding -ExportPath C:\Temp\jsmith-groups.csv
```

Offboards jsmith for real and keeps the list of removed groups in a CSV.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `AccountName`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `invoke-ad-offboarding`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Offboarded jsmith: disabled, password reset, removed from 4 group(s), description stamped, moved to OU=Disabled Users,DC=contoso,DC=com
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\invoke-ad-offboarding.log`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/invoke-ad-offboarding

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
