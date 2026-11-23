# Mail forwarding to outside addresses

> Alerts when a mailbox forwards mail, or an inbox rule forwards or redirects it, to an address outside the company's own domains.

| | |
|---|---|
| Script | `test-external-mail-forwarding.ps1` |
| Type | Monitor |
| Category | Exchange & email |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: Organization.Read.All; ExchangeOnlineManagement 3.1+, Exchange.ManageAsApp, Exchange admin role |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | 1 to 10 minutes on a large tenant |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## What it does

THIS SCRIPT IS READ-ONLY. It connects to Exchange Online as the client's app (certificate), reads the accepted domains, then for every user and shared mailbox looks at two things: the mailbox-level forwarding settings (ForwardingSmtpAddress, and ForwardingAddress, which may name a contact that points outside) and, unless IncludeInboxRules is false, every enabled inbox rule that forwards, forwards as an attachment or redirects. A target is external when its domain is not one of the tenant's accepted domains and not in AllowedDomains. It writes one row per external forward and alerts (exit 1) when there is any. Mail forwarding to an outside address is the classic sign of a compromised mailbox; "remove-external-mail-forwarding" is the matching Action. It is SKIPPED when the ExchangeOnlineManagement module is not installed. One tenant per run. On a large tenant the inbox-rule pass reads one mailbox at a time and can take several minutes; set IncludeInboxRules to false for a quick mailbox-setting check.

Permissions: Microsoft Graph application permission Organization.Read.All (the shared helper reads the tenant's initial domain, GET /organization); Exchange.ManageAsApp on Office 365 Exchange Online; and an Exchange role that lets Get-Mailbox and Get-InboxRule run (Exchange Administrator works; Microsoft says Get-InboxRule does not work for the Global Reader role).

Where each fact comes from: Get-Mailbox (ForwardingSmtpAddress, ForwardingAddress, DeliverToMailboxAndForward, -ResultSize, -RecipientTypeDetails), Set-Mailbox (the two forwarding properties; if both are set, ForwardingAddress wins), Get-InboxRule (-Mailbox, Name, the RuleIdentity and Description properties), Set-InboxRule (the ForwardTo, ForwardAsAttachmentTo and RedirectTo actions), Get-AcceptedDomain, Get-Recipient, and the app-only authentication guide (all Microsoft Learn pages above). Not confirmed in the documentation, so read defensively: the exact output property names DomainName on Get-AcceptedDomain, PrimarySmtpAddress and ExternalEmailAddress on Get-Recipient, Enabled on Get-InboxRule (an absent Enabled is treated as enabled) and the text format of the ForwardTo, ForwardAsAttachmentTo and RedirectTo values (every address found inside the text is read, so '"Name" [SMTP:a@b.com]' and 'a@b.com' both work). A ForwardingAddress that cannot be looked up is reported as external, to be checked by hand. Hidden inbox rules (Get-InboxRule -IncludeHidden) are not read.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client's tenant ID (a GUID) or domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate, with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. Leave empty to use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `AllowedDomains` | Extra domains that are fine to forward to (for example a sister company or an archive service), separated by comma, semicolon or new line. The tenant's accepted domains are always allowed. Default none. | (empty) | `AllowedDomains` or `ALLOWED_DOMAINS` |
| `IncludeInboxRules` | true to also read every mailbox's inbox rules (slower). Default true. | `true` | `IncludeInboxRules` or `INCLUDE_INBOX_RULES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-external-mail-forwarding.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Alerts when any mailbox or inbox rule forwards outside the tenant's accepted domains.
```

```powershell
.\test-external-mail-forwarding.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -AllowedDomains "archive.example.net" -OutputFormat Json
Treats archive.example.net as allowed and prints one JSON object.
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
Forwarding outside: 2 found; jane@contoso.com (inbox rule 'Fwd') -> x@gmail.com; bob@contoso.com (mailbox) -> y@proton.me
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Mailbox`, `Kind`, `Rule`, `Target`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-18 First version.

## More

Full page: https://mspoutpost.com/scripts/test-external-mail-forwarding

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
