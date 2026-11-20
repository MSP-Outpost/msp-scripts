# New client tenant - Microsoft 365 onboarding audit

> Audits a new Microsoft 365 client tenant in one pass: licences, global admins, security defaults, Conditional Access, MFA registration, guests, external sharing, audit log and mailbox forwarding.

| | |
|---|---|
| Script | `get-tenant-onboarding-audit.ps1` |
| Type | Report |
| Category | Inventory, reporting & audit |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph read permissions (see the script); Entra ID P1; Exchange app access for CheckExchange |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 2 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-18 |

## What it does

THIS SCRIPT IS READ-ONLY. It signs in to ONE client tenant as an app registration (TenantId, ClientId and a certificate, or a ClientSecret in the environment) and writes one row per finding, each with a Severity (High, Medium, Low or Info) and the evidence in Detail:

- Licences: every subscribed SKU with units used and bought; a suspended or locked-out SKU, or more units used than bought, is flagged.
- Global administrators: how many active Global Administrator assignments there are and who they are. Fewer than 2 (no emergency account) or more than 5 is flagged.
- Security defaults on or off, and the Conditional Access policy count (enabled, report-only, disabled). Security defaults off with no enabled Conditional Access policy is High.
- MFA registration: the percentage of member accounts registered for MFA, and administrators that are not registered.
- Guest users: how many guests the tenant holds.
- External sharing: the SharePoint and OneDrive tenant sharing level (Anyone links are flagged), guest resharing and domain restriction.
- Only when CheckExchange=true: whether the unified audit log is on (Get-AdminAuditLogConfig) and how many mailboxes forward mail, with the targets (Get-Mailbox). Exchange checks need the ExchangeOnlineManagement module 3.1 or later; when it is missing the two rows say "Not checked" and the rest of the report still runs. A check the app is not allowed to run (a missing permission or licence) becomes a "Not checked" row with the service's own error, so one missing permission does not lose the whole report. The run is ERROR only when every check failed. Active role assignments only: Privileged Identity Management eligible assignments are not listed.

Microsoft Graph application permissions (admin consent): LicenseAssignment.Read.All, RoleManagement.Read.Directory, Policy.Read.All, AuditLog.Read.All (MFA registration report), User.Read.All, SharePointTenantSettings.Read.All. For CheckExchange: Exchange.ManageAsApp plus an Exchange or Entra role that can read mailboxes and the audit configuration (Global Reader or Exchange Administrator). The MFA registration report is reported to need Entra ID P1 or P2.

Where each fact comes from (read in Microsoft's reference): GET v1.0/subscribedSkus (skuPartNumber, consumedUnits, capabilityStatus, prepaidUnits.enabled); GET v1.0/roleManagement/directory/roleAssignments with a roleDefinitionId filter and $expand=principal (Global Administrator is role template 62e90394-69f5-4237-9190-012177145e10, the id Microsoft's own example uses); GET v1.0/policies/identitySecurityDefaultsEnforcementPolicy (isEnabled); GET v1.0/identity/conditionalAccess/policies (state); GET v1.0/reports/authenticationMethods/userRegistrationDetails (isMfaRegistered, isAdmin, userType); GET v1.0/users filtered on userType eq 'Guest' with ConsistencyLevel eventual and $count; GET v1.0/admin/sharepoint/settings (sharingCapability, isResharingByExternalUsersEnabled, sharingDomainRestrictionMode); Get-AdminAuditLogConfig (UnifiedAuditLogIngestionEnabled, read in Exchange Online PowerShell); Get-Mailbox. Not confirmed in the documentation, so read defensively: the Get-Mailbox page does not list ForwardingAddress and ForwardingSmtpAddress as output properties (the Set-Mailbox page does); the least-privileged Exchange role for the two Exchange reads; whether the principal of a role assignment always returns userPrincipalName (display name or id is used when it does not); the shape of the sharepoint settings reply (Microsoft's example wraps it in a value object, so both shapes are read); the Entra licence the MFA registration report needs (the page states none).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint (40 hex characters) of the app's certificate, which must be installed with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. When empty, the app secret is read from the environment variable ClientSecret (a secure RMM field). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `CheckExchange` | true to also check the unified audit log and mailbox forwarding through Exchange Online PowerShell. Default false. | `false` | `CheckExchange` or `CHECK_EXCHANGE` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-tenant-onboarding-audit.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Audits the Graph-visible settings of the tenant.
```

```powershell
.\get-tenant-onboarding-audit.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -CheckExchange true -ExportPath C:\Temp\audit.csv
Also checks the audit log and mailbox forwarding, and saves the findings.
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
Tenant audit: 16 findings; 2 High, 3 Medium, 1 Low; 0 not checked
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Area`, `Finding`, `Value`, `Severity`, `Detail`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-18 First version (untested).

## More

Full page: https://mspoutpost.com/scripts/get-tenant-onboarding-audit

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
