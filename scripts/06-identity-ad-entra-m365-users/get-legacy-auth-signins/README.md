# Who still uses legacy authentication

> Lists who still signs in to Microsoft 365 with legacy authentication (IMAP, POP, SMTP, ActiveSync and other old clients).

| | |
|---|---|
| Script | `get-legacy-auth-signins.ps1` |
| Type | Report |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: AuditLog.Read.All; Entra ID P1 |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 5 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-18 |

## What it does

THIS SCRIPT IS READ-ONLY. It signs in as your app registration (certificate preferred, or the ClientSecret environment variable), reads the Entra sign-in log for the last LookbackDays days, keeps the sign-ins whose clientAppUsed is a legacy client, and writes one row per user, client type and app: how many sign-ins, how many succeeded and failed, the last time seen and the most frequent IP address. A Report: it never alerts, and a tenant with no legacy sign-ins is OK with an empty table.

The log is read newest first, 1,000 at a time, and stops at MaxSignIns legacy sign-ins (default 20,000) so a busy tenant cannot run for hours; the answer says when it stopped early. The sign-in log keeps 30 days at most, so LookbackDays is limited to 30. A busy tenant can time out on a wide window: narrow LookbackDays.

Permission (Microsoft Graph APPLICATION): AuditLog.Read.All. The sign-in log needs Entra ID P1 (or P2).

Where each fact comes from (read in the Microsoft Graph v1.0 reference): GET /auditLogs/signIns with $filter on createdDateTime (ge, le) and clientAppUsed (eq), page size at most 1,000, newest first, retention follows the Entra data retention period; properties userPrincipalName, appDisplayName, ipAddress, clientAppUsed, status.errorCode, createdDateTime. The resource page names the legacy clients as Exchange ActiveSync, IMAP, MAPI, SMTP, POP and other clients. Not confirmed in the documentation, so read defensively: the exact strings the log stores. The page gives short names; the portal shows IMAP4, POP3, Authenticated SMTP, Other clients and several Exchange clients. The filter therefore lists every spelling this script knows (LegacyClients in Constants) and the rows show the string the log returned, so a new spelling shows up as zero rows and not as an error. Sign-in events of non-interactive legacy clients may also be absent from this endpoint, which the page says lists interactive sign-ins and successful federated ones.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The Application (client) ID of the app registration that holds the Graph permissions. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (private key in LocalMachine\My or CurrentUser\My). Preferred. When empty, the app secret is read from the environment variable ClientSecret (a secure/hidden RMM field; never an argument). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `LookbackDays` | How many days of the sign-in log to read. Whole number, 1 to 30. Default 30. | `30` | `LookbackDays` or `LOOKBACK_DAYS` |
| `MaxSignIns` | Stop after this many legacy sign-ins. Whole number, 100 to 200000. Default 20000. | `20000` | `MaxSignIns` or `MAX_SIGN_INS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-legacy-auth-signins.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -LookbackDays 14
One row per user and legacy client over the last 14 days.
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
142 legacy sign-in(s) by 6 user(s) in 30 days; clients: IMAP4 (97), Authenticated SMTP (45)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `User`, `ClientApp`, `App`, `SignIns`, `Succeeded`, `Failed`, `LastSeenUtc`, `TopIpAddress`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-18 First version (untested).

## More

Full page: https://mspoutpost.com/scripts/get-legacy-auth-signins

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
