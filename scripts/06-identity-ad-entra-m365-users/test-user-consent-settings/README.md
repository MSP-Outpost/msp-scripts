# Users can consent to any app

> Alerts when any user in the Microsoft 365 tenant can consent to any app (user consent is not limited to verified publishers).

| | |
|---|---|
| Script | `test-user-consent-settings.ps1` |
| Type | Monitor |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; app registration with Microsoft Graph application permission Policy.Read.All, admin-consented |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## What it does

THIS SCRIPT IS READ-ONLY. It signs in as your app registration (certificate preferred, or the ClientSecret environment variable) and reads the tenant's authorization policy: which app consent policies are assigned to ordinary users. It ALERTs when:

- the legacy policy "microsoft-user-default-legacy" is assigned: every user can consent to any app for any permission that does not need an admin (Microsoft's own wording: "Allow user consent for apps"), the setting phishing consent attacks rely on; or
- allowUserConsentForRiskyApps is true (users may consent to apps Microsoft flags as risky). It is healthy (OK) when user consent is off (no ManagePermissionGrantsForSelf policy), or limited by "microsoft-user-default-low" (verified publishers, permissions you classified as low impact) or by a custom policy of your own. A custom policy is reported in the table and in a warning, because only you know what it allows. To see which apps users have already consented to, run test-risky-app-consents.

Permission (Microsoft Graph APPLICATION): Policy.Read.All.

Where each fact comes from (read in the Microsoft Graph v1.0 reference): GET /policies/authorizationPolicy (Policy.Read.All; defaultUserRolePermissions.permissionGrantPoliciesAssigned, allowUserConsentForRiskyApps) and Microsoft's consent configuration guide (built-in policy IDs microsoft-user-default-low and microsoft-user-default-legacy, written in the assigned list as managePermissionGrantsForSelf.<id>). Not confirmed in the documentation, so read defensively: the exact casing of the assigned values (the guide writes "managePermissionGrantsForSelf.", the example response "ManagePermissionGrantsForSelf."; compared ignoring case), whether a newer built-in policy such as "microsoft-user-default-recommended" exists and what it allows (it is treated like a custom policy: OK with a warning), and that the list is empty when user consent is off.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The Application (client) ID of the app registration that holds the Graph permissions. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (private key in LocalMachine\My or CurrentUser\My). Preferred. When empty, the app secret is read from the environment variable ClientSecret (a secure/hidden RMM field; never an argument). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-user-consent-settings.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Alerts when users can consent to any app.
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
Users can consent to any app (policy microsoft-user-default-legacy is assigned)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Setting`, `Value`, `Finding`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-19 First version (untested).

## More

Full page: https://mspoutpost.com/scripts/test-user-consent-settings

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
