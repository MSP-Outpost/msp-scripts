# Break-glass accounts present, excluded, unused

> Alerts when a break-glass (emergency access) account is missing, disabled, caught by a Conditional Access policy or has signed in.

| | |
|---|---|
| Script | `test-break-glass-accounts.ps1` |
| Type | Monitor |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: User.Read.All, Policy.Read.All, AuditLog.Read.All, GroupMember.Read.All; Entra ID P1 |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.0 |
| Updated | 2026-11-18 |

## What it does

THIS SCRIPT IS READ-ONLY. It signs in as your app registration (certificate preferred, or the ClientSecret environment variable) and checks each account named in BreakGlassAccounts:

- it exists,
- it is enabled (a disabled emergency account does not work when you need it),
- it is excluded from every ENABLED Conditional Access policy that applies to users: excluded directly, or through a group it belongs to (nested groups included). Policies in report-only mode and policies that apply to guests only are ignored. A policy that excludes a directory ROLE the account holds is not resolved: such a policy is counted as not excluding the account and the row says so,
- it has no sign-in in the last SignInLookbackDays days, unless AllowSignIn is true (set it for a test period). Any failed check alerts. The answer names the accounts and the failed checks.

Permissions (Microsoft Graph APPLICATION): User.Read.All, Policy.Read.All, AuditLog.Read.All (sign-in log, needs Entra ID P1), GroupMember.Read.All (group membership of the account).

Where each fact comes from (read in the Microsoft Graph v1.0 reference): GET /users/{id | userPrincipalName} (accountEnabled, id), GET /identity/conditionalAccess/policies (state, conditions.users.includeUsers, includeGroups, includeRoles, excludeUsers, excludeGroups), GET /auditLogs/signIns with $filter on userId and createdDateTime (page size 1 to 1,000), GET /users/{id}/transitiveMemberOf/microsoft.graph.group. Not confirmed in the documentation, so read defensively: the least-privileged application permission for transitiveMemberOf (taken as GroupMember.Read.All from the permissions reference, not re-read), whether a sign-in filter on userId needs ConsistencyLevel (none is sent), and the exact text of a missing-user error (the script treats HTTP 404 as "does not exist").

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The Application (client) ID of the app registration that holds the Graph permissions. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (private key in LocalMachine\My or CurrentUser\My). Preferred. When empty, the app secret is read from the environment variable ClientSecret (a secure/hidden RMM field; never an argument). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `BreakGlassAccounts` | The break-glass accounts' user principal names, separated by comma, semicolon or new line. Required. | (empty) | `BreakGlassAccounts` or `BREAK_GLASS_ACCOUNTS` |
| `SignInLookbackDays` | Alert on a sign-in within this many days. Whole number, 1 to 30. Default 7. | `7` | `SignInLookbackDays` or `SIGN_IN_LOOKBACK_DAYS` |
| `AllowSignIn` | true to list sign-ins but not alert on them (for the days when you test the accounts). Default false. | `false` | `AllowSignIn` or `ALLOW_SIGN_IN` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-break-glass-accounts.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -BreakGlassAccounts "bg1@contoso.onmicrosoft.com,bg2@contoso.onmicrosoft.com"
Checks both emergency accounts.
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
Break-glass: bg2@contoso.onmicrosoft.com: not excluded from 2 Conditional Access polic(ies); bg1@contoso.onmicrosoft.com: signed in 1 time(s) in 7 days
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Account`, `Exists`, `Enabled`, `PoliciesNotExcluding`, `SignIns`, `Problem`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-18 First version (untested).

## More

Full page: https://mspoutpost.com/scripts/test-break-glass-accounts

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
