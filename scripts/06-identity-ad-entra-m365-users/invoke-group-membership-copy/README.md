# New starter same as Jane - copy group memberships

> New starter "same as Jane": adds a user to the Entra security groups and Microsoft 365 groups (Teams) that a template user is in.

| | |
|---|---|
| Script | `invoke-group-membership-copy.ps1` |
| Type | Action |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: GroupMember.ReadWrite.All, Directory.Read.All |
| Changes | Adds the new user to the security and Microsoft 365 groups the template user is in |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | Under 2 minutes |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=invoke-group-membership-copy`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\invoke-group-membership-copy.log`.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. It reads the groups the template user (TemplateUpn) is a direct member of, reads the groups the new user (NewUserUpn) is already in, and adds the new user to every template group they are not in yet. It adds members only: it never removes a user from a group, never changes the template user, never creates or edits a group, and never changes licences or roles (a licence that comes from group-based licensing follows the new group membership by itself). A Microsoft 365 group membership is also the user's Team membership. Groups it SKIPS and lists in the output with the reason, because Graph cannot or should not change them: dynamic-membership groups (membership follows a rule), groups synced from on-premises Active Directory (change them in Active Directory), role-assignable groups (they grant Entra administrator roles and need RoleManagement.ReadWrite.Directory, which this script does not use), mail-enabled security and distribution groups (managed in Exchange), and any group named in SkipGroups. Only security and Microsoft 365 groups are copied. HIGH RISK: group membership can grant access, so it is a dry run (it lists the groups it would add) until DryRun=false AND Approve=invoke-group-membership-copy are both set, and one run adds at most MaxChanges memberships (default 25). Running it again adds only what is still missing and then says "Already the same".

Microsoft Graph application permissions (admin consent): GroupMember.ReadWrite.All (add members), and Directory.Read.All (read the template and new user's group memberships and group properties).

Where each fact comes from (read in Microsoft's reference): GET v1.0/users/{id}/memberOf/microsoft.graph.group (direct memberships; needs ConsistencyLevel eventual and $count for the cast; Directory.Read.All is the least privileged application permission; the page says the index may not be up to date with recent changes); POST v1.0/groups/{id}/members/$ref with @odata.id (GroupMember.ReadWrite.All; 204; 400 when the object is already a member or the group is too new to be replicated; 403 for a group Graph cannot manage, which is only security and Microsoft 365 groups; a role-assignable group also needs RoleManagement.ReadWrite.Directory); group properties groupTypes, mailEnabled, securityEnabled, onPremisesSyncEnabled and isAssignableToRole. Not confirmed in the documentation, so read defensively: whether a group list read straight after a change shows it at once (the script re-reads up to 6 times, 5 seconds apart); whether a freshly created new user can be added to groups immediately (the page documents a replication delay for new groups; the script retries an add that answers 400 or 404 up to 3 times); whether a mail-enabled security group is always refused with 403 (this script skips them rather than try).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint (40 hex characters) of the app's certificate with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. When empty, the secret is read from the environment variable ClientSecret (a secure RMM field). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `TemplateUpn` | The user whose groups are copied, such as jane@contoso.com. Required. | (empty) | `TemplateUpn` or `TEMPLATE_UPN` |
| `NewUserUpn` | The user who receives the groups, such as new.starter@contoso.com. Required. Must be a different account from TemplateUpn. | (empty) | `NewUserUpn` or `NEW_USER_UPN` |
| `SkipGroups` | Group display names NOT to copy, separated by comma or semicolon (exact name, any case). Default empty. | (empty) | `SkipGroups` or `SKIP_GROUPS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\invoke-group-membership-copy.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -TemplateUpn jane@contoso.com -NewUserUpn new.starter@contoso.com
Dry run: lists the groups the new starter would be added to and the groups that are skipped; changes nothing.
```

```powershell
.\invoke-group-membership-copy.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -TemplateUpn jane@contoso.com -NewUserUpn new.starter@contoso.com -SkipGroups "Finance Approvers" -DryRun false -Approve invoke-group-membership-copy
Adds the new starter to Jane's groups except Finance Approvers.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `TenantId`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `invoke-group-membership-copy`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Added new.starter@contoso.com to 7 group(s) copied from jane@contoso.com; 2 skipped
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\invoke-group-membership-copy.log`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/invoke-group-membership-copy

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
