# Mail forwarding to outside addresses - turn it off

> Stops mail forwarding to outside addresses: clears mailbox forwarding and disables (or removes) inbox rules that forward or redirect outside the company's own domains.

| | |
|---|---|
| Script | `remove-external-mail-forwarding.ps1` |
| Type | Action |
| Category | Exchange & email |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: Organization.Read.All; ExchangeOnlineManagement 3.1+, Exchange.ManageAsApp, Exchange admin role |
| Changes | Clears external ForwardingSmtpAddress and ForwardingAddress on mailboxes; disables or removes inbox rules that forward or redirect outside; writes a before-state JSON file |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | 1 to 10 minutes on a large tenant |
| Version | 1.0.0 |
| Updated | 2026-11-18 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=remove-external-mail-forwarding`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\remove-external-mail-forwarding.log`.
- Run the dry run first and read the list.

## What it does

HIGH RISK: it changes mailbox settings and inbox rules across the tenant. It does nothing unless you run it with DryRun=false AND Approve=remove-external-mail-forwarding; otherwise it lists what it would do. It connects to Exchange Online as the client's app and finds what "test-external-mail-forwarding" finds: a mailbox's ForwardingSmtpAddress or ForwardingAddress pointing outside the tenant's accepted domains (and AllowedDomains), and enabled inbox rules that forward, forward as an attachment or redirect outside. For each such mailbox it clears the external forwarding setting; for each such rule it disables the rule (RuleAction=Disable, the default, which keeps the rule so it can be switched on again) or removes it (RuleAction=Remove). Internal forwarding is never touched. Before it changes anything it writes the before-state of every affected mailbox and rule to a JSON file under %ProgramData%\MSPOutpost\Backups\remove-external-mail-forwarding\<time>\before-state.json and prints that file's path; keep it, it is how you restore a forward that turns out to be legitimate. It stops without changing anything when more than MaxChanges (default 25) changes are planned: check the dry run, then raise MaxChanges. Afterwards it re-reads every touched mailbox and fails (exit 2) if any external forward is still there. SKIPPED when the ExchangeOnlineManagement module is not installed. One tenant per run.

If the mailbox was compromised, clearing the forward is not enough: reset the password, revoke sessions and look for other persistence. Microsoft documents that creating, modifying, disabling or removing an inbox rule from Exchange PowerShell also removes the Outlook client-side rules of that mailbox.

Permissions: Microsoft Graph application permission Organization.Read.All (the shared helper reads the tenant's initial domain, GET /organization); Exchange.ManageAsApp on Office 365 Exchange Online; and an Exchange role that can run Set-Mailbox, Get-InboxRule and Disable-InboxRule or Remove-InboxRule (Exchange Administrator works; Global Reader does not).

Where each fact comes from (Microsoft Learn): Set-Mailbox (-ForwardingSmtpAddress, -ForwardingAddress, -DeliverToMailboxAndForward; the default of both forwarding properties is blank, $null), Disable-InboxRule and Remove-InboxRule (-Identity accepts the rule Name or the RuleIdentity, -Mailbox, -Confirm, -Force, and the Outlook client-side rules warning), Get-Mailbox, Get-InboxRule, Get-AcceptedDomain, Get-Recipient and the app-only authentication guide. Not confirmed in the documentation, so read defensively: that Set-Mailbox accepts $null to clear (the documented default is blank; the run re-reads the mailbox to prove it); the output property names listed in test-external-mail-forwarding (DomainName, Enabled, PrimarySmtpAddress, ExternalEmailAddress and the text of ForwardTo, ForwardAsAttachmentTo and RedirectTo). If a rule's Enabled property is absent the re-read cannot prove a disabled rule and the run fails; use RuleAction=Remove then.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client's tenant ID (a GUID) or domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate, with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. Leave empty to use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `AllowedDomains` | Extra domains that are fine to forward to, separated by comma, semicolon or new line. Default none. | (empty) | `AllowedDomains` or `ALLOWED_DOMAINS` |
| `TargetMailbox` | Work on one mailbox only (an address, alias or UPN). Default empty: every user and shared mailbox. | (empty) | `TargetMailbox` or `TARGET_MAILBOX` |
| `RuleAction` | Disable (default) keeps the rule but switches it off; Remove deletes it. | `Disable` | `RuleAction` or `RULE_ACTION` |
| `IncludeInboxRules` | true (default) to handle inbox rules as well as mailbox forwarding; false for mailbox forwarding only. | `true` | `IncludeInboxRules` or `INCLUDE_INBOX_RULES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\remove-external-mail-forwarding.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Dry run: lists the external forwards it would clear or disable.
```

```powershell
.\remove-external-mail-forwarding.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -TargetMailbox jane@contoso.com -DryRun false -Approve remove-external-mail-forwarding
Clears the external forwarding of one mailbox, after saving its before-state.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `TenantId`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `remove-external-mail-forwarding`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Cleared external forwarding on 2 mailbox(es), disabled 1 rule(s); before-state saved
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\remove-external-mail-forwarding.log`.

## Changelog

- 1.0.0 2026-11-18 First version (untested).

## More

Full page: https://mspoutpost.com/scripts/remove-external-mail-forwarding

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
