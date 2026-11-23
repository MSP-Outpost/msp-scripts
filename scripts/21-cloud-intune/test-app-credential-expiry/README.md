# App secret or certificate expiring in Microsoft 365

> Alerts when an Entra app registration or enterprise app has a secret or certificate that has expired or expires soon.

| | |
|---|---|
| Script | `test-app-credential-expiry.ps1` |
| Type | Monitor |
| Category | Cloud & Intune |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; an Entra app registration with the Graph application permission Application.Read.All (admin consent) |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## What it does

THIS SCRIPT IS READ-ONLY. It signs in to ONE client tenant as an app registration (TenantId, ClientId and a certificate, or a ClientSecret in the environment), reads every application (app registration) and every service principal (enterprise app) with their passwordCredentials (secrets) and keyCredentials (certificates), and writes one row per credential that has already expired or expires within WarnDays. It alerts (exit 1) when there is at least one row. Applications or service principals named in ExcludeApps are skipped (match on display name, app ID or object ID). Service principals include SAML single sign-on signing certificates, which stop single sign-on when they lapse. An expired credential that was already replaced still shows as Expired: exclude the app, or delete the old credential, to quiet it.

Microsoft Graph application permission (admin consent): Application.Read.All. No licence needed.

Where each fact comes from (read in Microsoft's reference): GET v1.0/applications and GET v1.0/servicePrincipals (Application.Read.All least privileged; $select and $top supported, 999 per page); the application and servicePrincipal properties id, appId, displayName, passwordCredentials and keyCredentials; passwordCredential and keyCredential properties displayName, keyId and endDateTime (UTC); keyCredential properties type and usage. Not confirmed in the documentation, so read defensively: whether every tenant returns endDateTime as a date value or text (both are handled); the hidden secret text is never returned by Graph and is never read or printed here (only the name, id and end date).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint (40 hex characters) of the app's certificate with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. When empty, the secret is read from the environment variable ClientSecret (a secure RMM field). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `WarnDays` | Alert when a credential expires within this many days. Whole number, 1 to 3650. Default 30. | `30` | `WarnDays` or `WARN_DAYS` |
| `ExcludeApps` | Applications or service principals to skip, separated by comma, semicolon or new line: display name, app ID or object ID. Default empty. | (empty) | `ExcludeApps` or `EXCLUDE_APPS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-app-credential-expiry.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Alerts when any app secret or certificate in the tenant expires within 30 days or has expired.
```

```powershell
.\test-app-credential-expiry.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -WarnDays 60 -ExcludeApps "Old Intranet" -OutputFormat Json
Warns 60 days ahead, skips one app and prints one JSON object.
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
App credentials: 1 expired, 2 expiring within 30 days; first: Contoso API secret 2026-12-01
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Object`, `Kind`, `AppId`, `Credential`, `CredentialName`, `ExpiresUtc`, `DaysLeft`, `Status`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-18 First version.

## More

Full page: https://mspoutpost.com/scripts/test-app-credential-expiry

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
