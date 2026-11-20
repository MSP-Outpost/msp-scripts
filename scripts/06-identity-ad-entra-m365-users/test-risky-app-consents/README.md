# Apps with risky Microsoft 365 permissions

> Alerts when a third-party app holds a high-risk Microsoft 365 permission (read all mail, all files, directory write and similar).

| | |
|---|---|
| Script | `test-risky-app-consents.ps1` |
| Type | Monitor |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: Directory.Read.All, Application.Read.All |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 2 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-18 |

## What it does

THIS SCRIPT IS READ-ONLY. It signs in as your app registration (certificate preferred, or the ClientSecret environment variable) and lists:

- DELEGATED consents (oauth2PermissionGrants, what users or admins let an app do as them) whose scope contains a permission from the high-risk list, and
- APPLICATION permissions (app role assignments, what an app may do with no user present) with a permission from the list, for apps granted rights on Microsoft Graph, Exchange Online or SharePoint Online. Microsoft's own apps (owner tenant f8cdef31-a31e-4b4a-93e4-5f571e91255a), the app this script signs in as, and apps named in AllowedApps are skipped. It ALERTS when any is found and lists one row per grant. To remove them, run remove-risky-app-consents (a dry run first).

The high-risk list is fixed in the script (HighRiskPermissions in Constants): mail read, write and send, mailbox settings, all files, all sites, directory write, role and application management, group write, user write, Exchange full access and the grant-management permissions. Microsoft does not publish a "high-risk" list: the names are real permission names from the Microsoft Graph permissions reference, and the choice of which count as high risk is this script's, so read the list before you trust a quiet result. Apps with rights on other resources (a custom API) are not checked, and neither are owners of the apps.

Permission (Microsoft Graph APPLICATION): Directory.Read.All (lists the delegated grants) and Application.Read.All (service principals and app role assignments).

Where each fact comes from (read in the Microsoft Graph v1.0 reference): GET /oauth2PermissionGrants (clientId, consentType AllPrincipals or Principal, principalId, resourceId, scope; Directory.Read.All), GET /servicePrincipals(appId='{appId}') and /servicePrincipals/{id} (id, appId, displayName, appRoles, appOwnerOrganizationId), GET /servicePrincipals/{id}/appRoleAssignedTo (appRoleId, principalId, principalType, resourceId; Application.Read.All). Not confirmed in the documentation, so read defensively: the Microsoft tenant ID above (a well-known value, not on these pages), the three resource app IDs (Microsoft Graph 00000003-0000-0000-c000-000000000000, Exchange Online 00000002-0000-0ff1-ce00-000000000000, SharePoint Online 00000003-0000-0ff1-ce00-000000000000, also well known), and the value of the principalType field for an app (taken as ServicePrincipal). A client whose service principal cannot be read is shown with an empty name.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The Application (client) ID of the app registration that holds the Graph permissions. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (private key in LocalMachine\My or CurrentUser\My). Preferred. When empty, the app secret is read from the environment variable ClientSecret (a secure/hidden RMM field; never an argument). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `AllowedApps` | Apps you accept, by application (client) ID or exact display name, separated by comma, semicolon or new line. Default empty. | (empty) | `AllowedApps` or `ALLOWED_APPS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-risky-app-consents.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -AllowedApps "Backup Tool,aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
Alerts on every other app that holds a high-risk permission.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `TenantId`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Risky app consents: 4 grant(s) for 3 app(s): Mail Merge Pro (Mail.ReadWrite Mail.Send), Cloud Backup (Files.ReadWrite.All), +1 more
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `App`, `AppId`, `GrantType`, `Resource`, `Permissions`, `ConsentedFor`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-18 First version (untested).

## More

Full page: https://mspoutpost.com/scripts/test-risky-app-consents

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
