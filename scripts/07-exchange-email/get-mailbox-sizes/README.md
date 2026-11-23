# Mailbox nearly full - size and quota report

> Reports each mailbox's size against its quota, its Recoverable Items size and its archive size, fullest first, to find mailboxes that are nearly full.

| | |
|---|---|
| Script | `get-mailbox-sizes.ps1` |
| Type | Report |
| Category | Exchange & email |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: Organization.Read.All; ExchangeOnlineManagement 3.1+, Exchange.ManageAsApp, read role |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | 1 to 30 minutes depending on the number of mailboxes |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## What it does

THIS SCRIPT IS READ-ONLY. It connects to Exchange Online as the client's app, lists the mailboxes (all, or the one in TargetMailbox) with the Quota and Archive property sets of Get-EXOMailbox, and for each one reads Get-EXOMailboxStatistics (item count, TotalItemSize, TotalDeletedItemSize) and, when the mailbox has an active archive and IncludeArchive is true, the archive's statistics with -Archive. One data row per mailbox: size and quota in GB, percent of the quota used, item count, the Recoverable Items size (the deleted-items "dumpster" that fills when users delete a lot, or when a litigation hold keeps what they delete) with its percent of RecoverableItemsQuota, and the archive size. The quota used is ProhibitSendQuota (the size at which the user can no longer send), or ProhibitSendReceiveQuota when that is the only one set. Rows are sorted fullest first and only mailboxes at or above MinPercentUsed (default 0: all) are listed. It does not list the biggest folders. It makes two or three Exchange calls per mailbox, so a large tenant takes a while; a mailbox that fails is reported as a warning and the run goes on. Always ends OK (a Report); use MinPercentUsed=90 to see only the nearly full ones. SKIPPED when the ExchangeOnlineManagement module is not installed. One tenant per run.

Permissions: Microsoft Graph application permission Organization.Read.All (the shared helper reads the tenant's initial domain, GET /organization); Exchange.ManageAsApp on Office 365 Exchange Online; and an Exchange role that can read mailbox statistics (Global Reader or View-Only Organization Management is expected to be enough).

Where each fact comes from (Microsoft Learn): Get-EXOMailbox (-PropertySets, -RecipientTypeDetails, -ResultSize), the property sets page (Quota set: ProhibitSendQuota, ProhibitSendReceiveQuota, IssueWarningQuota, RecoverableItemsQuota, RecoverableItemsWarningQuota, ArchiveQuota; Archive set: ArchiveStatus, ArchiveState, ArchiveGuid, AutoExpandingArchiveEnabled), Get-EXOMailboxStatistics (-Identity, -Archive; Minimum set DeletedItemCount, ItemCount, TotalDeletedItemSize, TotalItemSize). Not confirmed in the documentation, so read defensively: how the sizes print (the run reads the number in "x GB (n bytes)" text, or ToBytes() when the value has it, and shows blank when a quota is Unlimited); that TotalDeletedItemSize is the size of Recoverable Items (assumed from the name and Microsoft's usual description); that ArchiveStatus is Active for a working archive.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client's tenant ID (a GUID) or domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate, with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. Leave empty to use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `TargetMailbox` | One mailbox (its address or UPN). Default empty: every mailbox of the chosen MailboxType. | (empty) | `TargetMailbox` or `TARGET_MAILBOX` |
| `MailboxType` | All (default: user and shared mailboxes), User or Shared. Ignored when TargetMailbox is set. | `All` | `MailboxType` or `MAILBOX_TYPE` |
| `MinPercentUsed` | List only mailboxes at or above this percent of quota, 0 to 100. Default 0 (all). | `0` | `MinPercentUsed` or `MIN_PERCENT_USED` |
| `IncludeArchive` | true (default) to read the archive size of mailboxes that have an active archive. | `true` | `IncludeArchive` or `INCLUDE_ARCHIVE` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-mailbox-sizes.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -MinPercentUsed 80
Lists the mailboxes that are at least 80 percent full, fullest first.
```

```powershell
.\get-mailbox-sizes.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -TargetMailbox jane@contoso.com
Shows Jane's mailbox, Recoverable Items and archive size.
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
120 mailbox(es) checked, 4 listed; fullest: jane@contoso.com 98.4% (98.4 of 100 GB)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Mailbox`, `MailboxType`, `SizeGB`, `QuotaGB`, `PercentUsed`, `Items`, `RecoverableItemsGB`, `RecoverablePercent`, `ArchiveStatus`, `ArchiveGB`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/get-mailbox-sizes

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
