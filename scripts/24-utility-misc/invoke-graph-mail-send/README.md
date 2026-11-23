# Send an email through Microsoft Graph from a script

> Sends one email through Microsoft Graph (not SMTP) from a mailbox of your tenant, with an optional attachment.

| | |
|---|---|
| Script | `invoke-graph-mail-send.ps1` |
| Type | Action |
| Category | Utility / misc |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: Mail.Send, ideally limited to one mailbox |
| Changes | Sends one email (saved in the sender's Sent Items) |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## What it does

THIS SCRIPT CHANGES THINGS. It sends ONE email as the mailbox in FromMailbox to the addresses in To, with Subject and MessageBody (plain text, or HTML when BodyFormat=Html) and, optionally, one file as an attachment. The message is saved in the sender's Sent Items. It sends nothing else, reads no mailbox, and a dry run only prints what it would send. Graph answers 202 Accepted when it takes the message; that is not a delivery receipt (delivery is subject to Exchange Online limits and throttling). ATTACHMENT LIMIT: this script sends the file inside the sendMail call, which Microsoft limits to attachments under 3 MB; a file of 3 MB or more is refused (larger files need a draft and an upload session, which this script does not do). RESTRICT THE APP: the application permission Mail.Send lets the app send as ANY mailbox in the tenant. The MSP should limit the app to the one sending mailbox with an Exchange Online application access policy, or better with RBAC for Applications (a management scope plus the Application Mail.Send role), as Microsoft documents on the "limit an app's access to specific mailboxes" page. Otherwise a leaked certificate can send mail as the CEO.

Microsoft Graph application permission (admin consent): Mail.Send. The sending mailbox must exist and be licensed (or a shared mailbox).

Where each fact comes from (read in Microsoft's reference): POST v1.0/users/{id | userPrincipalName}/sendMail (Mail.Send; body message with subject, body.contentType and content, toRecipients, attachments; saveToSentItems; 202 Accepted); the fileAttachment shape with @odata.type #microsoft.graph.fileAttachment, name, contentType and base64 contentBytes; the 3 MB attachment limit of the single-call method; RBAC for Applications and application access policies as the way to limit Mail.Send to chosen mailboxes. Not confirmed in the documentation, so read defensively: whether the request body as a whole has a size limit beyond the 3 MB attachment rule (the script stays well inside it by refusing 3 MB files, but a very long body is not checked); the number of recipients one call accepts (Exchange Online limits apply and Graph reports a refusal in the error text).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint (40 hex characters) of the app's certificate with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. When empty, the secret is read from the environment variable ClientSecret (a secure RMM field). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `FromMailbox` | The sending mailbox, such as alerts@contoso.com. Required. | (empty) | `FromMailbox` or `FROM_MAILBOX` |
| `To` | Recipient addresses, separated by comma, semicolon or new line. Required. | (empty) | `To` or `TO` |
| `Subject` | Subject line. Required. | (empty) | `Subject` or `SUBJECT` |
| `MessageBody` | Message text. Required. Plain text unless BodyFormat is Html. | (empty) | `MessageBody` or `MESSAGE_BODY` |
| `BodyFormat` | Text (default) or Html. | `Text` | `BodyFormat` or `BODY_FORMAT` |
| `AttachmentPath` | Path of one file to attach, under 3 MB. Empty (default) sends no attachment. | (empty) | `AttachmentPath` or `ATTACHMENT_PATH` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\invoke-graph-mail-send.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -FromMailbox alerts@contoso.com -To tech@contoso.com -Subject "Backup failed" -MessageBody "Server FS01 backup failed at 02:00."
Sends a plain-text email.
```

```powershell
.\invoke-graph-mail-send.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -FromMailbox alerts@contoso.com -To "a@contoso.com,b@contoso.com" -Subject Report -MessageBody "<p>See attached.</p>" -BodyFormat Html -AttachmentPath C:\Temp\report.csv -DryRun true
Shows what it would send, to two people, with an HTML body and an attachment.
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
Sent 'Backup failed' from alerts@contoso.com to 2 recipient(s); Graph accepted it
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\invoke-graph-mail-send.log`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-18 First version.

## More

Full page: https://mspoutpost.com/scripts/invoke-graph-mail-send

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
