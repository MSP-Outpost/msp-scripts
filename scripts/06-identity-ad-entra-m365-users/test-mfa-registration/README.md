# Users without MFA or with SMS-only MFA

> Alerts when a Microsoft 365 user has no strong MFA method, or only SMS or voice calls.

| | |
|---|---|
| Script | `test-mfa-registration.ps1` |
| Type | Monitor |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: AuditLog.Read.All; Entra ID P1 |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.0 |
| Updated | 2026-11-18 |

## What it does

THIS SCRIPT IS READ-ONLY. It signs in as your app registration (certificate preferred, or the ClientSecret environment variable) and reads the authentication methods registration report, one record per user. A member user ALERTS when isMfaRegistered is false (no strong method: a user with only an email address or only a password counts as none), or, with AlertOnWeakMethods, when every registered method is a phone method (SMS or voice call: mobilePhone, alternateMobilePhone, officePhone) and no app, key or passkey is registered. Guests are skipped unless IncludeGuests is true. Users in ExcludeUsers (user principal names) are skipped. The report does not return disabled users, so they are never listed. It checks registration only: it does not prove that Conditional Access or security defaults enforce MFA at sign-in.

Permission (Microsoft Graph APPLICATION): AuditLog.Read.All. The report needs Entra ID P1 (or P2) in the tenant.

Where each fact comes from (read in the Microsoft Graph v1.0 reference): GET /reports/authenticationMethods/userRegistrationDetails (properties userPrincipalName, userDisplayName, isAdmin, isMfaRegistered, isMfaCapable, methodsRegistered, userType with values member or guest; AuditLog.Read.All). Not confirmed in the documentation, so read defensively: the exact spelling of the phone values in methodsRegistered (the page shows mobilePhone, email and passKeyDeviceBound and says "such as"; alternateMobilePhone and officePhone follow the same naming but are not listed), so an unknown value counts as a non-phone method and the user is not called weak. A user whose only method is a phone that the tenant's authentication methods policy does not allow for MFA counts as no strong method, with "phone only, not allowed for MFA by policy" in the Problem column.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The Application (client) ID of the app registration that holds the Graph permissions. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (private key in LocalMachine\My or CurrentUser\My). Preferred. When empty, the app secret is read from the environment variable ClientSecret (a secure/hidden RMM field; never an argument). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `ExcludeUsers` | User principal names to skip (service accounts, shared mailboxes), separated by comma, semicolon or new line. Default empty. | (empty) | `ExcludeUsers` or `EXCLUDE_USERS` |
| `IncludeGuests` | true to check guest users as well. Default false. | `false` | `IncludeGuests` or `INCLUDE_GUESTS` |
| `AlertOnWeakMethods` | true to alert on users whose only methods are SMS or voice calls. Default true. | `true` | `AlertOnWeakMethods` or `ALERT_ON_WEAK_METHODS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-mfa-registration.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Alerts when any member user has no MFA method or only phone methods.
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
MFA: 4 user(s) with no strong method, 7 with SMS or voice only (of 212): ann@contoso.com, bob@contoso.com, +9 more
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `User`, `DisplayName`, `UserType`, `Admin`, `Methods`, `Problem`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-18 First version.

## More

Full page: https://mspoutpost.com/scripts/test-mfa-registration

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
