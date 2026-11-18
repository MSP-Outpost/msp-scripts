# Privileged AD groups - nested membership and change alerts

> Alerts when someone unapproved is in a privileged Active Directory group, or when a privileged group's membership changed.

| | |
|---|---|
| Script | `test-privileged-ad-groups.ps1` |
| Type | Monitor |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows Server 2016+ (domain controller or domain member) |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, ActiveDirectory module (RSAT-AD-PowerShell) |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY, apart from the one baseline file it keeps (see below). It reads the recursive membership (members of nested groups included) of the ten groups that can take over a domain:

Domain Admins, Enterprise Admins, Schema Admins, Administrators, Account Operators, Backup Operators, Server Operators, Print Operators, DnsAdmins and Group Policy Creator Owners.

Groups are found by their well-known SID, not their name, so a renamed or translated group is still found. Enterprise Admins and Schema Admins live in the forest root domain and are read there. A group that does not exist (DnsAdmins on a domain without DNS) is skipped.

It ends ALERT when:

- AllowedMembers is set and a member of any of these groups is not on it; or
- the membership of any group changed since the last run: a member was added (the answer names who and where) or removed.

The first run has nothing to compare with: it saves the baseline, reports OK and says so. Every later run compares with the previous run and then saves the new state, so a change alerts once; an approved change needs no reset. AllowedMembers keeps alerting for as long as an unapproved member stays in a group. Leave AllowedMembers empty to alert on changes only.

The baseline is the file test-privileged-ad-groups\baseline.json under %ProgramData%\MSPOutpost\State. Delete it to start over. A run that ends ERROR does not change it.

Run it on a domain controller or a member server with the ActiveDirectory module (RSAT). If the module is missing it ends ERROR; on a computer that is not in a domain it ends SKIPPED.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `AllowedMembers` | Accounts that may be in these groups, separated by commas or semicolons: the sign-in name (Administrator), DOMAIN\name, or a SID. * and ? are wildcards with at least 3 literal characters. Default empty: only changes alert. (Named AllowedMembers, not ApprovedMembers: PowerShell would read the runtime's -Approve as a short form of a parameter beginning with "Approve".) | (empty) | `AllowedMembers` or `ALLOWED_MEMBERS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-privileged-ad-groups.ps1
```

First run saves the baseline; later runs alert on any membership change.

```powershell
.\test-privileged-ad-groups.ps1 -AllowedMembers "Administrator, CONTOSO\ITAdmin1"
```

Also alerts when anyone but those two accounts is in a privileged group.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `AllowedMembers`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
2 problem(s): jdoe added to Domain Admins; tmp-admin is not an allowed member of Administrators
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Group`, `Member`, `MemberType`, `Allowed`, `Change`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/test-privileged-ad-groups

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
