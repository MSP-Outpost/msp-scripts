# Sign-in history of one user

> Lists one Microsoft 365 user's sign-ins (time, app, IP address, place, result) for the last days.

| | |
|---|---|
| Script | `get-user-signin-history.ps1` |
| Type | Report |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: AuditLog.Read.All; Entra ID P1 |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## What it does

THIS SCRIPT IS READ-ONLY. It signs in as your app registration (certificate preferred, or the ClientSecret environment variable) and reads the Entra sign-in log for the one user in UserPrincipalName over the last LookbackDays days, newest first, up to MaxRows rows. Use it when a user may be compromised: which apps, from which IP addresses and countries, and whether each sign-in succeeded. The answer lists the countries seen. A Report: it never alerts.

Permission (Microsoft Graph APPLICATION): AuditLog.Read.All. The sign-in log needs Entra ID P1 (or P2) and keeps 30 days at most, so LookbackDays is limited to 30. Interactive sign-ins and successful federated sign-ins are in this log; the page does not say that non-interactive and service-principal sign-ins are, so they may be missing.

Where each fact comes from (read in the Microsoft Graph v1.0 reference): GET /auditLogs/signIns with $filter on userPrincipalName (eq) and createdDateTime (ge, le), $top up to 1,000, newest first, the UPN stored in lower case; properties createdDateTime, appDisplayName, clientAppUsed, ipAddress, isInteractive, status.errorCode, status.failureReason, location.countryOrRegion, location.city. Not confirmed in the documentation, so read defensively: any property missing from a row is shown empty.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The Application (client) ID of the app registration that holds the Graph permissions. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (private key in LocalMachine\My or CurrentUser\My). Preferred. When empty, the app secret is read from the environment variable ClientSecret (a secure/hidden RMM field; never an argument). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `UserPrincipalName` | The user's sign-in name, for example ann@contoso.com. Required. | (empty) | `UserPrincipalName` or `USER_PRINCIPAL_NAME` |
| `LookbackDays` | How many days to read. Whole number, 1 to 30. Default 7. | `7` | `LookbackDays` or `LOOKBACK_DAYS` |
| `MaxRows` | The most sign-ins to list. Whole number, 10 to 5000. Default 500. | `500` | `MaxRows` or `MAX_ROWS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-user-signin-history.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -UserPrincipalName ann@contoso.com -LookbackDays 14
The last 14 days of Ann's sign-ins.
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
ann@contoso.com: 63 sign-in(s) in 7 days, 4 failed; countries: CA (60), RO (3)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `WhenUtc`, `App`, `ClientApp`, `IpAddress`, `Country`, `City`, `Result`, `Interactive`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-18 First version.

## More

Full page: https://mspoutpost.com/scripts/get-user-signin-history

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
