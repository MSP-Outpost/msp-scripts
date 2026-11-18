# Export all Active Directory users with key attributes

> Exports every Active Directory user with its status, last logon, password age, never-expires flag, OU and group count.

| | |
|---|---|
| Script | `get-ad-users.ps1` |
| Type | Report |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows Server 2016+ (domain controller or domain member) |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, ActiveDirectory module (RSAT-AD-PowerShell) |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute for 1,000 users |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. It lists the users of the domain this computer belongs to, one row per user: sign-in name, display name, UPN, enabled, last logon, when the password was last set, whether the password never expires, the OU (or container) the user sits in, and how many groups the user is a direct member of.

Last logon is the lastLogonTimestamp attribute. Active Directory only refreshes it when it is more than about 14 days old, so it can be up to 14 days behind the real last logon: right for "who has not signed in for months", wrong for "who signed in today". It is empty for a user who has never signed in. GroupCount counts the memberOf groups; the user's primary group (normally Domain Users) is not included.

Disabled users are left out unless IncludeDisabled is true. Run it on a domain controller or on a member server with the ActiveDirectory module (RSAT). If the module is missing it ends ERROR; on a computer that is not in a domain it ends SKIPPED.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `SearchBase` | Only list users under this OU or container, as a distinguished name, e.g. "OU=Staff,DC=contoso,DC=com". Default empty: the whole domain. The OU must exist. | (empty) | `SearchBase` or `SEARCH_BASE` |
| `IncludeDisabled` | Also list disabled users. true or false. Default false. | `false` | `IncludeDisabled` or `INCLUDE_DISABLED` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-ad-users.ps1 -ExportPath C:\Temp\ad-users.csv
```

Lists the enabled users of the domain and also saves them to a CSV file.

```powershell
.\get-ad-users.ps1 -SearchBase "OU=Staff,DC=contoso,DC=com" -IncludeDisabled true
```

Lists every user, enabled or not, under the Staff OU.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `SearchBase`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Listed 152 user(s): 140 enabled, 12 disabled; 5 with a password that never expires
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `SamAccountName`, `DisplayName`, `Upn`, `Enabled`, `LastLogonUtc`, `PasswordLastSetUtc`, `PasswordNeverExpires`, `Ou`, `GroupCount`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/get-ad-users

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
