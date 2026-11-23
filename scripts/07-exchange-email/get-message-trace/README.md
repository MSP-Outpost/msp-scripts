# Where did this email go - message trace

> Lists where recent mail went: a message trace by sender, recipient, subject and time window, with each message's delivery status.

| | |
|---|---|
| Script | `get-message-trace.ps1` |
| Type | Report |
| Category | Exchange & email |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: Organization.Read.All; ExchangeOnlineManagement 3.1+, Exchange.ManageAsApp, message trace role |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## What it does

THIS SCRIPT IS READ-ONLY. It answers "where did this email go?". It connects to Exchange Online as the client's app and runs a message trace for the last Hours hours (default 24, at most 240, which is the 10 days one trace query may span), filtered by Sender and/or Recipient address and/or Subject text (each optional), and writes up to MaxRows messages, newest first, with the delivery status (Delivered, Failed, Pending, FilteredAsSpam, Quarantined, Expanded or GettingStatus). A message sent to several recipients is one row per recipient. Run it again with a narrower window if the answer says the list was cut off. For mail older than 10 days Microsoft has a separate historical search (Start-HistoricalSearch); this script does not start one. SKIPPED when the ExchangeOnlineManagement module is not installed. One tenant per run.

Which trace cmdlet: Microsoft documents Get-MessageTraceV2 as the replacement of Get-MessageTrace, which "will eventually be deprecated". The script uses Get-MessageTraceV2 when the Exchange session offers it (-ResultSize replaces the old -PageSize; -Subject with -SubjectFilterType Contains is built in), and falls back to Get-MessageTrace (first page of -PageSize rows; the subject is then filtered here, after the page was read) only when V2 is not there, so an older or newer module still works. The first output line says which one ran.

Permissions: Microsoft Graph application permission Organization.Read.All (the shared helper reads the tenant's initial domain, GET /organization); Exchange.ManageAsApp on Office 365 Exchange Online; and an Exchange role that can run message trace (Exchange Administrator works).

Where each fact comes from (Microsoft Learn): Get-MessageTraceV2 (-StartDate, -EndDate, -SenderAddress, -RecipientAddress, -Subject, -SubjectFilterType, -ResultSize 1 to 5000, the 90-day search range, 10 days per query, the 5000-row maximum, time stamps in UTC, the Status values), Get-MessageTrace (-PageSize 1 to 5000, 10-day range, deprecation note), and the app-only authentication guide. Not confirmed in the documentation, so read defensively (an absent property shows as empty): the output property names Received, SenderAddress, RecipientAddress, Subject, Status, Size and MessageTraceId (the V2 page names "Recipient address" and "Received Time" without giving the property names); which Exchange role is the least that can run a trace. Trace data can lag delivery by a few minutes.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client's tenant ID (a GUID) or domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate, with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. Leave empty to use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `Sender` | Only messages from this address (for example jane@contoso.com). Default empty: any sender. | (empty) | `Sender` or `SENDER` |
| `Recipient` | Only messages to this address. Default empty: any recipient. | (empty) | `Recipient` or `RECIPIENT` |
| `Subject` | Only messages whose subject contains this text. Default empty: any subject. | (empty) | `Subject` or `SUBJECT` |
| `Hours` | How far back to look, in hours. Whole number, 1 to 240. Default 24. | `24` | `Hours` or `HOURS` |
| `MaxRows` | The most messages to list. Whole number, 1 to 5000. Default 100. | `100` | `MaxRows` or `MAX_ROWS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-message-trace.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -Sender jane@contoso.com -Hours 72
Lists what jane@contoso.com sent in the last three days and where each message ended up.
```

```powershell
.\get-message-trace.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -Recipient bob@fabrikam.com -Subject "Invoice 4471" -OutputFormat Json
Finds the message to bob@fabrikam.com with that subject and prints one JSON object.
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
Message trace (Get-MessageTraceV2): 12 message(s) in 24 h; Delivered 11, Failed 1
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Received`, `Sender`, `Recipient`, `Subject`, `Status`, `Size`, `MessageTraceId`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-18 First version.

## More

Full page: https://mspoutpost.com/scripts/get-message-trace

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
