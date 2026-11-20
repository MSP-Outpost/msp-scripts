# New inbox rules that hide mail

> Alerts when a mailbox gets a new inbox rule that hides mail: deletes it, moves it to RSS Feeds, Archive or Conversation History, marks it read, or matches invoice, payment or wire words.

| | |
|---|---|
| Script | `test-suspicious-inbox-rules.ps1` |
| Type | Monitor |
| Category | Exchange & email |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: Organization.Read.All; ExchangeOnlineManagement 3.1+, Exchange.ManageAsApp, Exchange admin role |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | 1 to 10 minutes on a large tenant |
| Version | 1.0.0 |
| Updated | 2026-11-18 |

## What it does

THIS SCRIPT IS READ-ONLY on the tenant. After an account takeover the attacker often creates an inbox rule that hides replies and security mail from the real user. This script connects to Exchange Online as the client's app, reads the inbox rules of every user and shared mailbox, and marks a rule as suspicious when it deletes (or permanently deletes) messages, moves them to the RSS Feeds, RSS Subscriptions, Archive or Conversation History folder, marks them read, or has subject or body words invoice, payment or wire (plus any ExtraWords). It keeps a snapshot of the suspicious rules as JSON in %ProgramData%\MSPOutpost\Snapshots\test-suspicious-inbox-rules\<tenant>.json (the previous one is kept beside it as <tenant>.previous.json) and alerts (exit 1) only on rules that are NEW since the last run: rules already in the snapshot are listed as known and do not alert. A rule that is new stays flagged for NewWithinHours (default 24) so a run twice a day or a retry still reports it. The first run records every suspicious rule it finds as the starting point and reports them (ALERT when there are any); review them once. Run it from the same computer each time (the snapshot is a local file). It is SKIPPED when the ExchangeOnlineManagement module is not installed. One tenant per run. On a large tenant it reads one mailbox at a time and can take several minutes.

Permissions: Microsoft Graph application permission Organization.Read.All (the shared helper reads the tenant's initial domain, GET /organization); Exchange.ManageAsApp on Office 365 Exchange Online; and an Exchange role that lets Get-Mailbox and Get-InboxRule run (Exchange Administrator works; Microsoft says Get-InboxRule does not work for the Global Reader role).

Where each fact comes from (Microsoft Learn): Get-InboxRule (-Mailbox, Name and the RuleIdentity and Description properties), Set-InboxRule (the actions and conditions DeleteMessage, PermanentDelete, MoveToFolder with the syntax MailboxID:\ParentFolder\SubFolder, MarkAsRead, SubjectContainsWords, BodyContainsWords, SubjectOrBodyContainsWords), Get-Mailbox, and the app-only authentication guide. Not confirmed in the documentation, so read defensively (an absent property counts as not set): that Get-InboxRule returns those same property names, including Enabled (a disabled rule is ignored when the property is present); that RuleIdentity stays the same from run to run (the snapshot key is mailbox, rule name and RuleIdentity; if it changes every run, every rule will look new); the exact text of the MoveToFolder value (only the folder names are matched). Hidden rules (Get-InboxRule -IncludeHidden) are not read.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client's tenant ID (a GUID) or domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate, with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. Leave empty to use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `ExtraWords` | More words that make a rule suspicious when they appear in its subject or body conditions, separated by comma, semicolon or new line (for example "remittance, bank details"). Default none. | (empty) | `ExtraWords` or `EXTRA_WORDS` |
| `NewWithinHours` | A new suspicious rule keeps alerting for this many hours after it was first seen. Whole number, 1 to 720. Default 24. | `24` | `NewWithinHours` or `NEW_WITHIN_HOURS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-suspicious-inbox-rules.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
First run: records the suspicious rules it finds and reports them. Later runs alert on new ones only.
```

```powershell
.\test-suspicious-inbox-rules.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -ExtraWords "remittance, bank details" -OutputFormat Json
Also treats rules that mention remittance or bank details as suspicious.
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
Suspicious inbox rules: 1 new; jane@contoso.com rule 'x' (deletes; marks read)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Mailbox`, `Rule`, `Reasons`, `FirstSeen`, `IsNew`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-18 First version (untested).

## More

Full page: https://mspoutpost.com/scripts/test-suspicious-inbox-rules

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
