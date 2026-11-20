# Someone was just made an admin

> Alerts when someone was made a Microsoft 365 administrator in the last few hours.

| | |
|---|---|
| Script | `test-new-admin-assignments.ps1` |
| Type | Monitor |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; app registration with Microsoft Graph application permission AuditLog.Read.All, admin-consented |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.0 |
| Updated | 2026-11-18 |

## What it does

THIS SCRIPT IS READ-ONLY. It signs in as your app registration (certificate preferred, or the ClientSecret environment variable) and reads the Entra directory audit log for the last LookbackHours hours (RoleManagement category). A successful event whose activity name is "Add member to role" or "Add eligible member to role" (an eligible assignment made in Privileged Identity Management) alerts, with the person who made the change, the person who received the role and the role. Events whose actor is in IgnoreActors are skipped (for example the break-glass or provisioning account you expect to assign roles). Run it on a schedule that is shorter than LookbackHours so no assignment falls between two runs; it keeps no state between runs.

Permission (Microsoft Graph APPLICATION): AuditLog.Read.All (or Directory.Read.All).

Where each fact comes from (read in the Microsoft Graph v1.0 reference): GET /auditLogs/directoryaudits with $filter (eq, ge, le, startswith), $top and paging; properties activityDateTime, activityDisplayName, category, result, initiatedBy.user.userPrincipalName, initiatedBy.app.displayName, targetResources (type, displayName, userPrincipalName). Not confirmed in the documentation, so read defensively: the category name RoleManagement and the activity names above (taken from Microsoft's audit activity reference, not from the Graph page; the page's example shows UserManagement and GroupManagement), that the activity names are never translated, and which targetResources entry is the role (this script takes the entry whose type is Role, and the entry whose type is User as the person). If a tenant words the activity differently the script reports no events, not an error.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The Application (client) ID of the app registration that holds the Graph permissions. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (private key in LocalMachine\My or CurrentUser\My). Preferred. When empty, the app secret is read from the environment variable ClientSecret (a secure/hidden RMM field; never an argument). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `LookbackHours` | How far back to look. Whole number, 1 to 720. Default 24. | `24` | `LookbackHours` or `LOOKBACK_HOURS` |
| `IgnoreActors` | User principal names or app names whose role assignments are expected, separated by comma, semicolon or new line. Default empty. | (empty) | `IgnoreActors` or `IGNORE_ACTORS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-new-admin-assignments.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -LookbackHours 6
Alerts on every admin role assignment in the last six hours.
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
2 admin role assignment(s) in the last 24 h: bob@contoso.com got Global Administrator from ann@contoso.com
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `WhenUtc`, `Actor`, `Target`, `Role`, `Activity`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-18 First version (untested).

## More

Full page: https://mspoutpost.com/scripts/test-new-admin-assignments

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
