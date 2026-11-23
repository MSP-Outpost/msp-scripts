# Microsoft 365 app access check (permissions and certificate expiry)

> Checks a client's Microsoft 365 app registration once: it signs in, lists the permissions it was granted, and alerts when the certificate is about to expire or a permission you need is missing.

| | |
|---|---|
| Script | `test-m365-app-access.ps1` |
| Type | Monitor |
| Category | Exchange & email |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; the app's certificate; for CheckExchange: Graph Organization.Read.All and Exchange app access |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## What it does

THIS SCRIPT IS READ-ONLY. It is the setup check an MSP runs once for each client app, and again from a monitor to catch an expiring certificate. It signs in to ONE tenant with the app (certificate preferred; the client secret only from the ClientSecret environment variable), reads the access token it got back, and decodes the token's roles claim on this computer to list the application permissions the client's administrator has granted (admin consent). The token itself is never printed, logged or written.

It alerts (exit 1) when: the sign-in works but the token carries no permissions at all; a permission named in RequiredPermissions is missing; the certificate on this computer expires within CertificateWarnDays days; or, with CheckExchange=true, Exchange Online will not connect. The sign-in itself failing (wrong tenant or app ID, certificate not uploaded to the app, no admin consent) is an ERROR with Microsoft's own message. With CheckExchange=true and the ExchangeOnlineManagement module missing, the Exchange part is reported as SKIPPED and the rest still runs.

The Microsoft Graph application permissions you need: none to sign in (the check reads the token's own roles). Organization.Read.All, only when CheckExchange=true (the shared Exchange helper reads the tenant's initial domain with GET /organization). Exchange itself needs the app's Exchange.ManageAsApp permission and an Exchange role (for example Exchange Administrator or Global Reader) assigned to the app.

Where each fact comes from: the client-credentials token request and the roles claim of an app-only access token (Microsoft Entra documentation above); Exchange.ManageAsApp, the app roles that make Connect-ExchangeOnline work and module version 2.0.4+ for certificate sign-in (the app-only authentication guide above); Get-AcceptedDomain (used as the Exchange proof of access). Not confirmed in the documentation, so read defensively: that the roles claim is present as an array of strings (a missing claim is treated as no permissions); that the token for https://outlook.office365.com carries the role name Exchange.ManageAsApp (checked only when you list it in RequiredPermissions); and that the certificate on this computer is the one uploaded to the app (only the app registration can say; the script checks the local copy's NotAfter date, which is what a replacement must beat).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client's tenant ID (a GUID) or domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate, with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. Leave empty to use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `CertificateWarnDays` | Alert when the certificate expires within this many days. Whole number, 1 to 3650. Default 30. | `30` | `CertificateWarnDays` or `CERTIFICATE_WARN_DAYS` |
| `CheckExchange` | true to also connect to Exchange Online and run Get-AcceptedDomain. Default false. | `false` | `CheckExchange` or `CHECK_EXCHANGE` |
| `RequiredPermissions` | Permissions the scripts you plan to run need, separated by comma, semicolon or new line (for example "Mail.Read, User.Read.All, Exchange.ManageAsApp"). Each missing one alerts. Default none (only the list is shown). | (empty) | `RequiredPermissions` or `REQUIRED_PERMISSIONS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-m365-app-access.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Signs in, lists the granted permissions and checks the certificate's expiry.
```

```powershell
.\test-m365-app-access.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -RequiredPermissions "Mail.Read, Exchange.ManageAsApp" -CheckExchange true
Alerts when either permission is missing or Exchange Online will not connect.
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
App access: 4 permission(s) granted; certificate expires in 18 day(s) (limit 30); missing Mail.Read
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Check`, `Item`, `Status`, `Detail`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-18 First version.

## More

Full page: https://mspoutpost.com/scripts/test-m365-app-access

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
