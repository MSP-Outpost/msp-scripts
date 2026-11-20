# Who is in this AD group - list its members

> Lists the members of an Active Directory group, with the members of nested groups when you ask for them.

| | |
|---|---|
| Script | `get-ad-group-members.ps1` |
| Type | Report |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows Server 2016+ (domain controller or domain member) |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, ActiveDirectory module (RSAT-AD-PowerShell) |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## What it does

THIS SCRIPT IS READ-ONLY. It lists one row per member of the group in GroupName: sign-in name, name, object class (user, computer, group or foreignSecurityPrincipal), whether the account is enabled (users and computers), whether the member is a DIRECT member, and its distinguished name.

By default only direct members are listed (a nested group is one row of class group). With Recursive true the members of nested groups are listed too, in place of the nested groups themselves, and the Direct column says which members were not direct. A group with more than about 5,000 members may be refused by Active Directory Web Services; the script then ends ERROR.

Run it on a domain controller or a member server with the ActiveDirectory module (RSAT). Without the module it ends ERROR; on a computer that is not in a domain it ends SKIPPED.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `GroupName` | The group's sign-in name (sAMAccountName). Required. | (empty) | `GroupName` or `GROUP_NAME` |
| `Recursive` | true to include the members of nested groups. Default false. | `false` | `Recursive` or `RECURSIVE` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-ad-group-members.ps1 -GroupName Sales-Staff
```

Lists the direct members of Sales-Staff.

```powershell
.\get-ad-group-members.ps1 -GroupName "Domain Admins" -Recursive true -ExportPath C:\Temp\admins.csv
```

Lists every person who is an administrator through nesting and saves the list.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `GroupName`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Sales-Staff has 12 member(s): 10 user(s), 1 computer(s), 1 group(s); 3 through nested groups
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `SamAccountName`, `Name`, `ObjectClass`, `Enabled`, `Direct`, `DistinguishedName`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/get-ad-group-members

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
