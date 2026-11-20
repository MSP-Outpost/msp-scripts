# Stale guest accounts

> Lists guest accounts in a Microsoft 365 tenant that have not signed in for 90 days or never accepted their invitation.

| | |
|---|---|
| Script | `get-stale-guests.ps1` |
| Type | Report |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: User.Read.All, AuditLog.Read.All; Entra ID P1 for sign-in activity |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## What it does

PARTLY TESTED: written from https://learn.microsoft.com/en-us/graph/api/user-list, https://learn.microsoft.com/en-us/graph/api/resources/user and https://learn.microsoft.com/en-us/graph/api/resources/signinactivity (Microsoft Graph v1.0). Compared on 2026-11-20 with get-unused-m365-licenses (tested): identical runtime and sign-in-time logic. Run against the test tenant: the guest query with signInActivity works and a guest without an invitation state is judged by sign-in time; no guest was old enough to be stale (the trial blocked invitations).

THIS SCRIPT IS READ-ONLY. It signs in as your app registration (certificate preferred, or the ClientSecret environment variable), lists every guest account (userType Guest) and reports the stale ones:

- "Invitation never accepted": the invitation (externalUserState PendingAcceptance) is older than StaleDays;
- "Idle": the newest of the guest's last successful, interactive and non-interactive sign-in is older than StaleDays;
- "No sign-in on record": no sign-in time at all and the account is older than StaleDays (Graph returns no sign-in activity for a user who never signed in or last signed in before April 2020). Guests in ExcludeGuests (sign-in name or mail address) are skipped. The table shows each stale guest with days since the invitation or last sign-in. Use remove-stale-guests to disable or delete them. The inviter and group memberships of each guest are not listed (Graph keeps the inviter only in the audit log).

Sign-in activity needs Microsoft Entra ID P1 and the AuditLog.Read.All permission. Without them the script says so in a warning and judges only unaccepted invitations; it does not guess about idle guests.

Permission (Microsoft Graph APPLICATION): User.Read.All and AuditLog.Read.All (sign-in activity).

Where each fact comes from (read in the Microsoft Graph v1.0 reference): GET /users with $filter on userType (eq), $select of createdDateTime, externalUserState, externalUserStateChangeDateTime, signInActivity (each needs $select), page size up to 500 when signInActivity is selected; signInActivity.lastSignInDateTime, lastNonInteractiveSignInDateTime and lastSuccessfulSignInDateTime (the page says signInActivity supports $filter "but not with any other filterable properties": this script only SELECTS it). Not confirmed in the documentation, so read defensively: that $select=signInActivity combines with $filter=userType eq 'Guest' (if Graph refuses, the script warns and judges only unaccepted invitations), the error a tenant without P1 gets (any error that mentions signInActivity, a licence or Premium falls back; any other error stops the run), and that externalUserState is filled only for guests invited through the invitation API (a guest added another way shows an empty state and is judged by sign-in time).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The Application (client) ID of the app registration that holds the Graph permissions. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (private key in LocalMachine\My or CurrentUser\My). Preferred. When empty, the app secret is read from the environment variable ClientSecret (a secure/hidden RMM field; never an argument). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `StaleDays` | A guest with no sign-in, or an unaccepted invitation, for this many days is stale. Whole number, 14 to 3650. Default 90. | `90` | `StaleDays` or `STALE_DAYS` |
| `ExcludeGuests` | Guests to leave out, by sign-in name or mail address, separated by comma, semicolon or new line. Default empty. | (empty) | `ExcludeGuests` or `EXCLUDE_GUESTS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-stale-guests.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -StaleDays 60
Lists guests idle or never redeemed for 60 days.
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
12 stale guest(s) of 40 (no sign-in or invitation accepted for 90 days)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `UserPrincipalName`, `DisplayName`, `Mail`, `State`, `CreatedUtc`, `LastSignInUtc`, `DaysIdle`, `Reason`, `Enabled`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/get-stale-guests

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
