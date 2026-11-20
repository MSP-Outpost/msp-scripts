# New employee - create the AD user like a template user

> Creates Active Directory users, one or from a CSV, copying OU, groups and attributes from a template user; the first password goes to a secure RMM field.

| | |
|---|---|
| Script | `new-ad-user.ps1` |
| Type | Action |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows Server 2016+ (domain controller or domain member) |
| Runs as | System |
| Requires | PowerShell 5.1; admin rights; ActiveDirectory module; rights to create users; a secure RMM field for the password |
| Changes | Creates AD users, adds them to the template's non-privileged groups and writes the first password to the RMM custom field |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 20 seconds per user |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## What it does

THIS SCRIPT CHANGES THINGS. For each user it creates, in this order:

1. The user account in the OU: TargetOu when set, else the template user's OU, else the domain's default Users container. The sign-in name is AccountName; the user principal name is AccountName@UpnSuffix (default: the template's suffix, else the domain's DNS name); the common name is the display name, which is DisplayName or "GivenName Surname".
2. A random 20-character password (cryptographic random number generator), enabled, with "must change password at next sign-in".
3. From the template user (TemplateUser, optional): Description, Department, Company, Title, Office, Manager, street address, city, state, postal code and logon script path, and every group the template is a direct member of. Never copied: name, sign-in name, UPN, mail, password, account flags, and any group that is privileged (adminCount 1, Domain Admins, Enterprise Admins, Schema Admins, a built-in group): those are skipped with a warning, so a template can never hand out admin rights.

THE PASSWORD IS NEVER PRINTED. In single-user mode (AccountName) it is written only to the RMM custom field named by ResultField (a secure / secret field; NinjaOne, Datto RMM and Syncro are supported) before the account is created. The script refuses without one. OutputFormat Answer is refused for the same reason. A field holds one password, so CSV mode (CsvPath) cannot use it: every user from the CSV gets a random password nobody knows, and you issue the first real password with reset-ad-user-password, one user at a time.

CSV mode: a header line then one user per row. Columns: AccountName (required), GivenName, Surname, DisplayName, TemplateUser, TargetOu. An empty cell uses the matching input. At most 200 rows. A row that fails does not stop the others; the run ends ERROR listing the failures.

Second run: a user whose sign-in name already exists is left alone: OK "Already exists". Nothing existing is changed, not even its groups.

Run it on a domain controller or a member server with the ActiveDirectory module (RSAT). Without the module it ends ERROR; on a computer that is not in a domain it ends SKIPPED.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `AccountName` | The new sign-in name (sAMAccountName): 1 to 20 letters, digits, dot, dash or underscore. Required unless CsvPath is set. (Named AccountName, not UserName: Windows already has an environment variable called USERNAME.) | (empty) | `AccountName` or `ACCOUNT_NAME` |
| `GivenName` | First name. Default empty. | (empty) | `GivenName` or `GIVEN_NAME` |
| `Surname` | Last name. Default empty. | (empty) | `Surname` or `SURNAME` |
| `DisplayName` | Display name and common name. Default: "GivenName Surname", else AccountName. May not contain , = + < > # ; " or a backslash. | (empty) | `DisplayName` or `DISPLAY_NAME` |
| `TemplateUser` | Sign-in name of an existing user to copy the OU, groups and attributes from. Default empty: nothing is copied. | (empty) | `TemplateUser` or `TEMPLATE_USER` |
| `TargetOu` | Distinguished name of the OU or container for the new user, e.g. "OU=Staff,DC=contoso,DC=com". Default empty: the template's OU, else the domain's Users container. It must exist. | (empty) | `TargetOu` or `TARGET_OU` |
| `UpnSuffix` | The part after the @ in the user principal name. Default empty: the template's suffix, else the domain's DNS name. | (empty) | `UpnSuffix` or `UPN_SUFFIX` |
| `CsvPath` | Path of a CSV file of users to create (see above). Default empty: create the one user in AccountName. | (empty) | `CsvPath` or `CSV_PATH` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\new-ad-user.ps1 -AccountName jsmith -GivenName Jo -Surname Smith -TemplateUser template-sales -ResultField NewUserPassword
```

Creates jsmith like the template-sales user and stores the first password in the field.

```powershell
.\new-ad-user.ps1 -CsvPath C:\Temp\new-users.csv -TargetOu "OU=Staff,DC=contoso,DC=com"
```

Creates every user in the CSV in the Staff OU (passwords come later from reset-ad-user-password).

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `AccountName`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Created jsmith in OU=Staff,DC=contoso,DC=com; must change password at first sign-in; password written to field NewUserPassword; added to 3 group(s)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\new-ad-user.log`.

## Changelog

- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/new-ad-user

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
