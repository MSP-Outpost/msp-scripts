# Remove risky app consents

> Removes high-risk Microsoft 365 app permissions (delegated grants and application permissions) from apps you have not allowed.

| | |
|---|---|
| Script | `remove-risky-app-consents.ps1` |
| Type | Action |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: Application.Read.All, DelegatedPermissionGrant and AppRoleAssignment ReadWrite.All |
| Changes | Deletes delegated permission grants and application permission assignments that contain high-risk permissions |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | Under 2 minutes |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=remove-risky-app-consents`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\remove-risky-app-consents.log`.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. It finds what test-risky-app-consents finds (the same fixed high-risk permission list, in the HighRiskPermissions constant) and removes it:

- a delegated consent (oauth2PermissionGrant) that contains a high-risk scope is DELETED WHOLE: the app loses every delegated permission of that grant on that resource, not only the risky scope, for the people covered by it (all users, or one user). Access tokens already issued stay valid until they expire (Microsoft's note).
- an application permission (app role assignment) that is on the list is DELETED; that app's other permissions are left alone. It never deletes the app, its service principal, its secrets or its users, never disables the app, and skips Microsoft's own apps (owner tenant f8cdef31-a31e-4b4a-93e4-5f571e91255a), the app this script signs in as, and every app named in AllowedApps. With OnlyApps it touches only the apps named there (by application ID or exact display name). The users of a removed app may be asked for consent again; an app they still need stops working until you put it in AllowedApps and consent again. Run a dry run first and read the list.

HIGH RISK: it is a dry run (lists every removal, changes nothing) unless DryRun=false AND Approve=remove-risky-app-consents, and it refuses to remove more than MaxChanges (default 25) in one run. Before the first removal it writes the consents to be removed (grant and assignment IDs, app, permissions, who consented; no secrets) as JSON under %ProgramData%\MSPOutpost\Backups\remove-risky-app-consents\ and prints the file name; the file is how you put one back (re-consent in the portal or recreate the grant).

Permissions (Microsoft Graph APPLICATION): Directory.Read.All (list grants), Application.Read.All (service principals and assignments), DelegatedPermissionGrant.ReadWrite.All (delete a delegated grant) and AppRoleAssignment.ReadWrite.All (delete an app role assignment).

Where each fact comes from (read in the Microsoft Graph v1.0 reference): GET /oauth2PermissionGrants and DELETE /oauth2PermissionGrants/{id} (204; DelegatedPermissionGrant.ReadWrite.All), GET /servicePrincipals/{id}/appRoleAssignedTo and DELETE /servicePrincipals/{resource-sp-id}/appRoleAssignedTo/{assignment-id} (204; AppRoleAssignment.ReadWrite.All), GET /servicePrincipals(appId='...') (appRoles id and value). Not confirmed in the documentation, so read defensively: the Microsoft tenant ID and the three resource app IDs (Microsoft Graph, Exchange Online, SharePoint Online; well known, not on these pages), the principalType value for an app (taken as ServicePrincipal), and whether a grant that Graph reports can lag after a delete (the check after the removal only warns).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The Application (client) ID of the app registration that holds the Graph permissions. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (private key in LocalMachine\My or CurrentUser\My). Preferred. When empty, the app secret is read from the environment variable ClientSecret (a secure/hidden RMM field; never an argument). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `AllowedApps` | Apps to leave alone, by application (client) ID or exact display name, separated by comma, semicolon or new line. Default empty. | (empty) | `AllowedApps` or `ALLOWED_APPS` |
| `OnlyApps` | When set, remove only from these apps (application ID or exact display name). Default empty (every risky app not allowed). | (empty) | `OnlyApps` or `ONLY_APPS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\remove-risky-app-consents.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -AllowedApps "Backup Tool"
Dry run: lists every high-risk consent it would remove.
```

```powershell
.\remove-risky-app-consents.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -OnlyApps "Mail Merge Pro" -DryRun false -Approve remove-risky-app-consents
Removes the high-risk consents of one app.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `TenantId`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `remove-risky-app-consents`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Removed 5 high-risk consent(s) from 3 app(s)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\remove-risky-app-consents.log`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-18 First version.

## More

Full page: https://mspoutpost.com/scripts/remove-risky-app-consents

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
