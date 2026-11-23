# Create Microsoft 365 users from a CSV file

> Creates Microsoft 365 (Entra ID) users from a CSV file, with an optional licence and groups, and puts each new user's first password in a secure RMM field.

| | |
|---|---|
| Script | `new-m365-users-from-csv.ps1` |
| Type | Action |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: User.Create, LicenseAssignment.ReadWrite.All, GroupMember.ReadWrite.All; a secure RMM field |
| Changes | Creates Entra ID users; assigns a licence; adds the users to groups; writes the initial passwords to a secure RMM field |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | Under 3 minutes |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=new-m365-users-from-csv`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\new-m365-users-from-csv.log`.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. It reads the CSV in CsvPath and, for every row whose user principal name does not exist yet, it:

1. CREATES the cloud user (accountEnabled true, a random initial password, change required at the first sign-in);
2. when LicenseSku is set: assigns that licence (the row needs a usage location: its UsageLocation column or DefaultUsageLocation);
3. when AddToGroups is set: adds the user to each of those security or Microsoft 365 groups. Users that already exist are SKIPPED and not touched at all (not even their licence or groups), which is what makes a second run safe: it says "Already created". If a run stops half way through a user, finish that user by hand; running it again will skip them. It never deletes or changes an existing user, never touches a user outside the CSV, never sets a manager, and never prints, logs, exports or returns a password.

CSV: a header row and one user per row. Columns (header names, any order): UserPrincipalName (required), DisplayName (or both GivenName and Surname), GivenName, Surname, JobTitle, Department, UsageLocation (two-letter country code such as US). Save it as UTF-8. At most 200 rows. The whole file is checked before anything is created: a bad row, a duplicate name, a domain the tenant has not verified, an unknown or exhausted licence or a group that cannot be changed stops the run with nothing created.

PASSWORDS. Each password is made here (24 characters, random, from the cryptographic generator) and written ONCE, before the users are created, to the secure RMM custom field named in ResultField, as one value: "user@contoso.com=Password user2@contoso.com=Password2". Split on spaces, then at the first "=". ResultField must be a secure (secret) field of NinjaOne, Datto RMM (UDF number) or Syncro; the run refuses to create anyone without one, and OutputFormat Answer is refused. A field holds about 240 characters (Datto RMM keeps 255), so one run creates a BATCH of users that fits (about 4 to 5 users): the rest are listed as "Deferred". Copy the passwords out of the field, then run again for the next batch; a second run overwrites the field. When ResultField is set the answer is never written to it, even on a run that creates nobody, so a second run cannot wipe passwords you have not copied. HIGH RISK: it is a dry run (it lists what it would create) until DryRun=false AND Approve=new-m365-users-from-csv are both set. Every create, licence and group add counts as one change toward MaxChanges (default 25): raise MaxChanges for a longer file.

Microsoft Graph application permissions (admin consent): User.Create (create users), LicenseAssignment.ReadWrite.All (assign the licence), GroupMember.ReadWrite.All (add to groups), and Directory.Read.All (read users, groups, the tenant's verified domains and its licence subscriptions).

Where each fact comes from (read in Microsoft's reference): POST v1.0/users needs accountEnabled, displayName, mailNickname, passwordProfile and userPrincipalName, returns 201, and the UPN domain must be a verified domain of the tenant (User.Create is the least privileged application permission); usageLocation is required for a user who is assigned a licence; POST v1.0/users/{id}/assignLicense with addLicenses (skuId, disabledPlans) and the required removeLicenses (LicenseAssignment.ReadWrite.All); POST v1.0/groups/{id}/members/$ref (GroupMember.ReadWrite.All; only security and Microsoft 365 groups; 400 for a group or user not yet replicated); GET v1.0/subscribedSkus with prepaidUnits and consumedUnits; GET v1.0/organization verifiedDomains. Not confirmed in the documentation, so read defensively: how long a new user takes to be usable for a licence or group add (the script retries an add that answers 400 or 404 up to 6 times, 5 seconds apart); that User.Create alone can create a user whose UPN is free but whose mailNickname or proxy address clashes with another object (the create is then refused and the run stops); that Directory.Read.All is enough to read verifiedDomains and subscribedSkus (Microsoft lists Organization.Read.All and LicenseAssignment.Read.All as the least privileged permissions for those two pages, so grant them if a read is refused); the password complexity rule for a tenant with a custom policy (the generated password has upper and lower case letters, digits and symbols).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint (40 hex characters) of the app's certificate with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. When empty, the secret is read from the environment variable ClientSecret (a secure RMM field). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `CsvPath` | Full path of the CSV file on this computer. Required. | (empty) | `CsvPath` or `CSV_PATH` |
| `DefaultUsageLocation` | Two-letter country code used for rows with no UsageLocation, such as CA. Default empty. | (empty) | `DefaultUsageLocation` or `DEFAULT_USAGE_LOCATION` |
| `LicenseSku` | The licence to assign to every new user: the SKU part number (such as O365_BUSINESS_PREMIUM) or the SKU ID (a GUID). Default empty: no licence. | (empty) | `LicenseSku` or `LICENSE_SKU` |
| `AddToGroups` | Groups every new user joins: display names or group IDs, separated by comma or semicolon. Security or Microsoft 365 groups only. Default empty. | (empty) | `AddToGroups` or `ADD_TO_GROUPS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\new-m365-users-from-csv.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -CsvPath C:\Temp\newusers.csv -DefaultUsageLocation CA -LicenseSku O365_BUSINESS_PREMIUM
Dry run: lists the users it would create and license; changes nothing.
```

```powershell
.\new-m365-users-from-csv.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -CsvPath C:\Temp\newusers.csv -DefaultUsageLocation CA -AddToGroups "All Staff" -ResultField NewUserPasswords -DryRun false -Approve new-m365-users-from-csv
Creates the missing users, adds them to All Staff and writes their passwords to the secure field NewUserPasswords.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `TenantId`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `new-m365-users-from-csv`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Created 4 user(s) (4 licensed, 8 group memberships); passwords are in the secure field; 2 already existed
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\new-m365-users-from-csv.log`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/new-m365-users-from-csv

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
