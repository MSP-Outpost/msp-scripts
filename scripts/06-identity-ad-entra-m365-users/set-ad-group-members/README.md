# AD security group - create it, add or remove members

> Adds and removes members of an Active Directory security group, and creates the group when you say so.

| | |
|---|---|
| Script | `set-ad-group-members.ps1` |
| Type | Action |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows Server 2016+ (domain controller or domain member) |
| Runs as | System |
| Requires | PowerShell 5.1; admin rights; ActiveDirectory module; rights to change group membership |
| Changes | Optionally creates one security group, adds and removes direct members (before-state saved) |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 15 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## What it does

THIS SCRIPT CHANGES THINGS. For the one group in GroupName it can:

1. Create the group (a security group of scope GroupScope in GroupOu), only when CreateGroup is true and the group does not exist.
2. Add every name in AddMembers that is not already a direct member.
3. Remove every name in RemoveMembers that is a direct member.

Names in AddMembers and RemoveMembers are sign-in names (sAMAccountName) of users, groups or computers (a computer with or without the trailing $); separate them with a comma, semicolon or new line. Every name is looked up and checked BEFORE anything is changed: a name that is not found, matches more than one object, is in both lists or is the group itself ends the run ERROR with nothing changed. Only direct membership is changed.

Before a change the group's current direct members are saved as a JSON list under %ProgramData%\MSPOutpost\Backups\set-ad-group-members\ so the old membership can be restored. The change limit (MaxChanges) is checked before anything is done.

Never touched: privileged groups. The script refuses any group that is a built-in group (Administrators, Account/Server/Backup/Print Operators ...), Domain Admins, Enterprise Admins, Schema Admins, Domain Controllers, Group Policy Creator Owners, read-only DCs, Key Admins, or has adminCount 1. Change those in Active Directory Users and Computers.

Second run: when the group exists and already has every member to add and none to remove, it ends OK "Already as wanted". To only LIST members, use get-ad-group-members.

Run it on a domain controller or a member server with the ActiveDirectory module (RSAT). Without the module it ends ERROR; on a computer that is not in a domain it ends SKIPPED.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `GroupName` | The group's sign-in name (sAMAccountName). Required. Up to 63 letters, digits, spaces, dots, dashes or underscores. | (empty) | `GroupName` or `GROUP_NAME` |
| `AddMembers` | Names to add. Default empty. | (empty) | `AddMembers` or `ADD_MEMBERS` |
| `RemoveMembers` | Names to remove. Default empty. | (empty) | `RemoveMembers` or `REMOVE_MEMBERS` |
| `CreateGroup` | true to create the group when it does not exist. Default false: a missing group is an error. | `false` | `CreateGroup` or `CREATE_GROUP` |
| `GroupScope` | The scope of a group this run creates: Global (default), DomainLocal or Universal. Ignored when the group exists. | `Global` | `GroupScope` or `GROUP_SCOPE` |
| `GroupOu` | Distinguished name of the OU or container for a group this run creates. Default empty: the domain's Users container. | (empty) | `GroupOu` or `GROUP_OU` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\set-ad-group-members.ps1 -GroupName Sales-Staff -AddMembers "jsmith, mlee" -RemoveMembers bold
```

Adds jsmith and mlee to Sales-Staff and removes bold.

```powershell
.\set-ad-group-members.ps1 -GroupName Project-X -CreateGroup true -GroupOu "OU=Groups,DC=contoso,DC=com" -AddMembers jsmith
```

Creates the group Project-X when needed and adds jsmith.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `GroupName`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Group Sales-Staff: added 2 member(s), removed 1 member(s)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\set-ad-group-members.log`.

## Changelog

- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/set-ad-group-members

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
