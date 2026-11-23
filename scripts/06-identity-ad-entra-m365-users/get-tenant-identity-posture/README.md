# Identity posture of every client tenant

> One row per Microsoft 365 client tenant: users, admins, MFA registration, legacy sign-in and guests.

| | |
|---|---|
| Script | `get-tenant-identity-posture.ps1` |
| Type | Report |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: User.Read.All, RoleManagement.Read.Directory, AuditLog.Read.All, Policy.Read.All; Entra ID P1 |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 2 minutes per tenant |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## What it does

THIS SCRIPT IS READ-ONLY. It signs in as your app registration (certificate preferred, or the ClientSecret environment variable) to each tenant in TenantId and reads Microsoft Graph v1.0. This is the only Outpost Microsoft 365 script where TenantId takes a comma, semicolon or new-line separated LIST of tenants. The same app (a multi-tenant app registration, with admin consent given in each client tenant) and the same certificate are used for every tenant; the token is reset for each one. One tenant that cannot be read (consent missing, wrong tenant, a missing licence) is a row with the error text, not a stop. It ends in an error only when no tenant at all could be read.

Each row: Users (enabled member accounts), Admins (distinct users with a directory role assignment; assignments that are only PIM-eligible are not listed by this endpoint), MfaRegisteredPercent (members registered for a strong method, from the authentication methods registration report), LegacyAuth and Guests (guest accounts). LegacyAuth is a reading, not a proof: "Blocked (security defaults)" when security defaults are on, "Likely blocked (Conditional Access)" when an enabled policy for all users and all apps blocks both Exchange ActiveSync and other legacy clients, and "Allowed" when neither is found.

Permissions (Microsoft Graph APPLICATION): User.Read.All, RoleManagement.Read.Directory, AuditLog.Read.All (registration report), Policy.Read.All. The registration report needs Entra ID P1; a tenant without it gets MfaRegisteredPercent "n/a" and the error in the Error column.

Where each fact comes from (each page was read in the Microsoft Graph v1.0 reference): GET /users (accountEnabled, userType), GET /roleManagement/directory/roleAssignments with $expand=principal (principalId, principal.@odata.type), GET /reports/authenticationMethods/userRegistrationDetails (isMfaRegistered, userType; AuditLog.Read.All), GET /policies/identitySecurityDefaultsEnforcementPolicy (isEnabled; Policy.Read.All), GET /identity/conditionalAccess/policies (state, conditions.users.includeUsers, conditions.applications.includeApplications, conditions.clientAppTypes, grantControls.builtInControls; Policy.Read.All). Not confirmed in the documentation, so read defensively: the clientAppTypes values exchangeActiveSync and other (the page shows only "all"), the value "block" in builtInControls, and whether the users list (a large tenant) needs ConsistencyLevel for the select used here (it does not, no filter or count is used).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | One or more client tenants (IDs or domains) separated by comma, semicolon or new line. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The Application (client) ID of the app registration that holds the Graph permissions. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (private key in LocalMachine\My or CurrentUser\My). Preferred. When empty, the app secret is read from the environment variable ClientSecret (a secure/hidden RMM field; never an argument). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-tenant-identity-posture.ps1 -TenantId "contoso.onmicrosoft.com,fabrikam.onmicrosoft.com" -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
One posture row for each of the two tenants.
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
3 tenant(s) read, 1 failed; lowest MFA registration: fabrikam.onmicrosoft.com 61%
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Tenant`, `Users`, `Admins`, `MfaRegisteredPercent`, `LegacyAuth`, `Guests`, `Error`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-18 First version.

## More

Full page: https://mspoutpost.com/scripts/get-tenant-identity-posture

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
