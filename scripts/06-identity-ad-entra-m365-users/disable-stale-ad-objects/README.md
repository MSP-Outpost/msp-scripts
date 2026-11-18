# Disable stale AD users and computers and move them to a holding OU

> Disables stale Active Directory users and computers, stamps their description and moves them to a holding OU.

| | |
|---|---|
| Script | `disable-stale-ad-objects.ps1` |
| Type | Action |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows Server 2016+ (domain controller or domain member) |
| Runs as | System |
| Requires | PowerShell 5.1, admin rights, ActiveDirectory module (RSAT-AD-PowerShell), rights to disable and move AD accounts |
| Changes | Disables stale user and computer accounts, moves them to TargetOu and stamps their description; saves their original location first |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=disable-stale-ad-objects`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\disable-stale-ad-objects.log`.
- Before it edits or deletes configuration, it copies it to `%ProgramData%\MSPOutpost\Backups\disable-stale-ad-objects\<UTC time>\` and keeps the last 10 runs. If a backup fails, nothing is changed.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. Risk is High, so it is a dry run unless you set BOTH DryRun=false AND Approve=disable-stale-ad-objects (typing the script name is the deliberate step), and it refuses to touch more accounts than MaxChanges (default 25) in one run. First run get-stale-ad-objects or this script as a dry run, read the list, then run it for real.

It selects exactly the accounts get-stale-ad-objects lists: enabled users and computers whose lastLogonTimestamp is older than InactiveDays, or that never signed in and were created more than InactiveDays ago. For each one it (1) writes "Disabled by MSP Outpost on <date> ..." in front of the description (the old description is kept after it), (2) moves the account to TargetOu, and (3) disables it. The disable is last on purpose: if a step fails the account is still enabled and still stale, so the next run picks it up again. Nothing is deleted, and the account keeps its SID and its group memberships, so re-enabling it and moving it back restores it. Before any change it saves a CSV of every account's original location, description and last logon under %ProgramData%\MSPOutpost\Backups\disable-stale-ad-objects\.

Never touched, whatever the inputs: the built-in accounts (RIDs 500 to 503), anything marked as a critical system object, domain controllers, the computer running this script, managed service accounts, trust accounts, and every account named in ExcludeAccounts. Put your service accounts in ExcludeAccounts first.

TargetOu is required and must already exist (an OU or a container): the script never creates it. InactiveDays 0 is refused unless SearchBase limits the run.

Second run: the accounts are disabled now, so nothing is selected and it says OK "Already clean".

lastLogonTimestamp is refreshed only when it is more than about 14 days old, so use an InactiveDays of 30 or more in real use.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TargetOu` | Where disabled accounts go, as a distinguished name, e.g. "OU=Disabled Accounts,DC=contoso,DC=com". Required. It must exist. | (empty) | `TargetOu` or `TARGET_OU` |
| `InactiveDays` | Days without a sign-in before an account is stale. Whole number, 0 to 3650. Default 90. 0 needs SearchBase. | `90` | `InactiveDays` or `INACTIVE_DAYS` |
| `SearchBase` | Only look under this OU or container (distinguished name). Default empty: the whole domain. It must exist. | (empty) | `SearchBase` or `SEARCH_BASE` |
| `ExcludeAccounts` | Sign-in names (SamAccountName) never to touch, separated by commas or semicolons, e.g. "svc-backup, svc-sql, PRINTSRV01". * and ? are wildcards with at least 3 literal characters. Default empty. | (empty) | `ExcludeAccounts` or `EXCLUDE_ACCOUNTS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\disable-stale-ad-objects.ps1 -TargetOu "OU=Disabled Accounts,DC=contoso,DC=com"
```

Dry run: lists the accounts idle for 90 days or more that would be disabled and moved.

```powershell
.\disable-stale-ad-objects.ps1 -TargetOu "OU=Disabled Accounts,DC=contoso,DC=com" -InactiveDays 120 -ExcludeAccounts "svc-backup" -DryRun false -Approve disable-stale-ad-objects
```

Disables and moves every account idle for 120 days or more, except svc-backup.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `TargetOu`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `disable-stale-ad-objects`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Disabled and moved 6 stale account(s) (4 user(s), 2 computer(s)) to OU=Disabled Accounts,DC=contoso,DC=com
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\disable-stale-ad-objects.log`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/disable-stale-ad-objects

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
