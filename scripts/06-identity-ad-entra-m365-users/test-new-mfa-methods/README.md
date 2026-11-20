# New MFA method registered

> Alerts when someone registered a new MFA method (phone, authenticator, security key) in the last few hours, the way an attacker keeps access.

| | |
|---|---|
| Script | `test-new-mfa-methods.ps1` |
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
| Updated | 2026-11-19 |

## What it does

THIS SCRIPT IS READ-ONLY. It signs in as your app registration (certificate preferred, or the ClientSecret environment variable) and reads the Entra directory audit log for the last LookbackHours hours (category UserManagement). A successful event named "User registered security info" (the user added a method) or "Admin registered security info" (an admin added one) alerts, with the user, what was registered when the log says, who did it and from which IP address. People registering their first method after you create their account alert too: list them in IgnoreUsers, or run the check a few hours after onboarding. An attacker who stole a password adds their own phone or authenticator app so that resetting the password does not evict them; this is that check. If you find one, run reset-user-mfa-methods and invoke-compromised-account-containment. Run it on a schedule shorter than LookbackHours so no registration falls between two runs; it keeps no state between runs.

Permission (Microsoft Graph APPLICATION): AuditLog.Read.All (or Directory.Read.All).

Where each fact comes from (read in the Microsoft Graph v1.0 reference and Microsoft's audit activity list): GET /auditLogs/directoryAudits with $filter (eq, ge, le, startswith), $top and paging; properties activityDateTime, activityDisplayName, category, result, resultReason, initiatedBy.user (userPrincipalName, ipAddress), initiatedBy.app.displayName, targetResources (type, userPrincipalName, displayName, modifiedProperties); the audit activity list names "User registered security info" and "Admin registered security info" in category UserManagement (also "User registered all required security info", which only says registration is complete and is not counted). Not confirmed in the documentation, so read defensively: where the method type sits (resultReason is tried first, then modifiedProperties; a Microsoft Q&A answer says that since June 2026 resultReason often just repeats the activity name, so the Method column may be empty), whether loggedByService is "Authentication Methods" or "Azure MFA" (the script does not filter on it), that initiatedBy.user.ipAddress is filled for self-registration, and that the activity names are never translated. If a tenant words the activity differently the script reports no events, not an error.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The Application (client) ID of the app registration that holds the Graph permissions. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (private key in LocalMachine\My or CurrentUser\My). Preferred. When empty, the app secret is read from the environment variable ClientSecret (a secure/hidden RMM field; never an argument). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `LookbackHours` | How far back to look. Whole number, 1 to 720. Default 24. | `24` | `LookbackHours` or `LOOKBACK_HOURS` |
| `IgnoreUsers` | Sign-in names whose registrations are expected (new hires), separated by comma, semicolon or new line. Default empty. | (empty) | `IgnoreUsers` or `IGNORE_USERS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-new-mfa-methods.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -LookbackHours 6
Alerts on every MFA method registered in the last six hours.
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
2 MFA method registration(s) in the last 24 h: ann@contoso.com (Fido2) from 203.0.113.9
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `WhenUtc`, `User`, `Activity`, `Method`, `Actor`, `IpAddress`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-19 First version (untested).

## More

Full page: https://mspoutpost.com/scripts/test-new-mfa-methods

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
