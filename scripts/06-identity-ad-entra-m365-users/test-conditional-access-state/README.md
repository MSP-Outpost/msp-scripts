# Is anything forcing MFA in Microsoft 365

> Alerts when a Microsoft 365 tenant has neither Security Defaults nor an enabled Conditional Access policy that requires MFA.

| | |
|---|---|
| Script | `test-conditional-access-state.ps1` |
| Type | Monitor |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; app registration with Microsoft Graph application permission Policy.Read.All, admin-consented |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## What it does

THIS SCRIPT IS READ-ONLY. It signs in as your app registration (certificate preferred, or the ClientSecret environment variable) and reads two things: whether Security Defaults is switched on, and every Conditional Access policy with its state. The tenant is protected (OK) when Security Defaults is on, or when at least one Conditional Access policy in the state "enabled" requires multifactor authentication (the built-in control "mfa", or an authentication strength that satisfies "mfa"). Otherwise it ALERTs. A policy that is only in report-only or disabled state does not count, and the answer says how many MFA policies are waiting in report-only. The table lists Security Defaults and every policy with who it covers, so you can see a policy that requires MFA only for a small group: such a policy counts here, check the Scope column.

Permission (Microsoft Graph APPLICATION): Policy.Read.All.

Where each fact comes from (read in the Microsoft Graph v1.0 reference): GET /policies/identitySecurityDefaultsEnforcementPolicy (isEnabled; Policy.Read.All), GET /identity/conditionalAccess/policies (displayName, state enabled / disabled / enabledForReportingButNotEnforced, conditions.users.includeUsers / includeRoles, grantControls.builtInControls and grantControls.authenticationStrength.requirementsSatisfied; Policy.Read.All, $top and paging). Not confirmed in the documentation, so read defensively: the exact error a tenant without Entra ID P1 gets from the Conditional Access list (the script treats an HTTP 403 whose message mentions a licence or Premium as "no Conditional Access in this tenant" and any other error as a failure), and whether a policy whose grant is "mfa OR something else" (operator OR with other controls) really forces MFA (it is counted as requiring it).

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
.\test-conditional-access-state.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Alerts when nothing in the tenant forces MFA.
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
Security Defaults is off and no enabled Conditional Access policy requires MFA (1 MFA policy in report-only)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Source`, `Name`, `State`, `RequiresMfa`, `Scope`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/test-conditional-access-state

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
