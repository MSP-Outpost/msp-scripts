# Too many local admins - remove the unapproved ones

> Removes everyone from the local Administrators group who is not on your approved list.

| | |
|---|---|
| Script | `remove-local-admin-members.ps1` |
| Type | Action |
| Category | Security hardening & compliance |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | Removes members from the local Administrators group; saves the member list first |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | Under 15 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=remove-local-admin-members`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\remove-local-admin-members.log`.
- Before it edits or deletes configuration, it copies it to `%ProgramData%\MSPOutpost\Backups\remove-local-admin-members\<UTC time>\` and keeps the last 10 runs. If a backup fails, nothing is changed.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. Risk is High, so it is a dry run unless you set BOTH DryRun=false AND Approve=remove-local-admin-members (typing the script name is the deliberate step), and it refuses to remove more members than MaxChanges (default 25) in one run. First look at the dry-run list, then run it for real.

It reads the members of the built-in Administrators group (found by its SID S-1-5-32-544, so it works in any language) and removes each member that is not in AllowedMembers. Only the group membership changes: the account itself is not deleted, disabled or signed out, and it keeps working as a standard user. Before removing anyone it saves the full member list (name, type, source, SID) as a CSV in %ProgramData%\MSPOutpost\Backups\remove-local-admin-members\, so any member can be added back.

Always kept, whatever AllowedMembers says: the built-in Administrator (any SID ending in -500), Domain Admins (SID ending in -512), the account running the script, every system principal (SIDs that are not local, domain or Entra ID accounts), every account a Windows service logs on as (Win32_Service StartName), and the account Windows LAPS or legacy LAPS (AdmPwd) manages. A real run also refuses, changing nothing, when no enabled approved (or LAPS) administrator would remain, so the PC is never left without one; the dry run only warns. A person who is an administrator only through a domain or Entra group is not visible here: approve the group, or removing the group removes them too (the row says so). A domain controller is skipped: there the Administrators group is the domain's. Entra ID roles that Windows adds to the group on an Entra-joined PC (Global Administrator, Device Administrator) are S-1-12-1-... members: approve them by SID or they are removed too. Domain and Entra groups in the Administrators group are removed as one member and their own members are not expanded.

An approved entry matches the full name (PC\admin), the short name (admin) or a SID, ignoring case; * and ? work as wildcards (a [ is literal) but a wildcard needs at least 3 literal characters. Names are also resolved to SIDs, so PC01\admin matches however Windows spells the member. A member whose SID no longer resolves (a deleted domain account) is listed and removed by SID. An approved entry that matches nobody on this PC is only a warning, so one list can serve many PCs. Check a typo with the dry run before approving.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `AllowedMembers` | Members allowed to stay local administrators (named AllowedMembers, not ApprovedMembers: PowerShell would read the runtime's -Approve as a short form of a parameter beginning with "Approve"), separated by commas or semicolons, e.g. "outpost, CONTOSO\Desk Techs, S-1-12-1-111-222-333-444". Default empty: only the always-kept members stay. | (empty) | `AllowedMembers` or `ALLOWED_MEMBERS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\remove-local-admin-members.ps1 -AllowedMembers "outpost, CONTOSO\Desk Techs"
```

Dry run: lists the administrators that would be removed.

```powershell
.\remove-local-admin-members.ps1 -AllowedMembers "outpost" -DryRun false -Approve remove-local-admin-members
```

Removes every local administrator except outpost and the always-kept accounts.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `AllowedMembers`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `remove-local-admin-members`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Removed 2 of 2 unapproved local administrator(s): PC01\jsmith, PC01\temp-admin
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\remove-local-admin-members.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/remove-local-admin-members

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
