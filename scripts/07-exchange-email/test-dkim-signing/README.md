# DKIM signing not on for a domain

> Alerts when a domain's outgoing mail is not DKIM-signed in Microsoft 365: no signing config, signing switched off, or the two selector DNS records not published.

| | |
|---|---|
| Script | `test-dkim-signing.ps1` |
| Type | Monitor |
| Category | Exchange & email |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; DnsClient; Graph: Organization.Read.All; Exchange app access (ManageAsApp), Exchange admin role |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 2 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-18 |

## What it does

THIS SCRIPT IS READ-ONLY. It connects to Exchange Online as the client's app, lists the tenant's accepted domains (authoritative domains only; the *.onmicrosoft.com domains are signed by Microsoft and skipped, and so is anything in SkipDomains) and, for each one, reads its DKIM signing configuration (Get-DkimSigningConfig: Enabled, Status, Selector1CNAME, Selector2CNAME) and asks DNS (Resolve-DnsName, on this computer) whether selector1._domainkey.<domain> and selector2._domainkey.<domain> are CNAME records pointing where Microsoft says. It writes one row per domain and alerts (exit 1) for a domain with no signing config, signing not enabled, or a selector that is missing or points to the wrong target. "enable-dkim-signing" is the matching Action. SKIPPED when the ExchangeOnlineManagement module is not installed. One tenant per run.

Permissions: Microsoft Graph application permission Organization.Read.All (the shared helper reads the tenant's initial domain, GET /organization); Exchange.ManageAsApp on Office 365 Exchange Online; and an Exchange role that can run Get-DkimSigningConfig and Get-AcceptedDomain (Exchange Administrator works; the DKIM cmdlets are cloud-only).

Where each fact comes from (Microsoft Learn): Get-DkimSigningConfig (cloud only; -Identity is the domain name), Get-AcceptedDomain, the DKIM configuration article (the two CNAME records are selector1._domainkey and selector2._domainkey, each pointing to a selector-<domain with dashes>._domainkey.<initial domain prefix>.<partition>-v1.dkim.mail.microsoft name; Get-DkimSigningConfig shows Name, Enabled, Status with the values Valid, CnameMissing and NoDKIMKeys, Selector1CNAME and Selector2CNAME), and Resolve-DnsName (-Type CNAME, -DnsOnly; records carry Type and NameHost). Not confirmed in the documentation, so read defensively: the DomainName and DomainType property names on Get-AcceptedDomain (a domain whose type is not Authoritative, for example an internal relay domain, is skipped); that Name on a DKIM config is the domain name; that DNS answers from this computer's resolver match what the internet sees (a split-horizon internal DNS can differ). DKIM can be fine without the status being Valid; the alert uses Enabled and the DNS answers.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client's tenant ID (a GUID) or domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate, with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. Leave empty to use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `SkipDomains` | Accepted domains that never send mail (parked domains), separated by comma, semicolon or new line. Default none. | (empty) | `SkipDomains` or `SKIP_DOMAINS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-dkim-signing.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Alerts when any accepted domain is not DKIM-signing.
```

```powershell
.\test-dkim-signing.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -SkipDomains "parked.example.net" -OutputFormat Json
Leaves one parked domain out and prints one JSON object.
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
DKIM: 1 of 3 domain(s) not signing; contoso.com (not enabled; selector1 missing)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Domain`, `Config`, `Enabled`, `Status`, `Selector1`, `Selector2`, `Problem`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-18 First version (untested).

## More

Full page: https://mspoutpost.com/scripts/test-dkim-signing

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
