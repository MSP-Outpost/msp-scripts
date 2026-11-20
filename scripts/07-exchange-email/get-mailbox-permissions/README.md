# Who can access which mailbox

> Lists who has Full Access, Send As and Send on Behalf on which mailbox, for one mailbox or all of them.

| | |
|---|---|
| Script | `get-mailbox-permissions.ps1` |
| Type | Report |
| Category | Exchange & email |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: Organization.Read.All; ExchangeOnlineManagement 3.1+, Exchange.ManageAsApp, read role |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | 1 to 30 minutes depending on the number of mailboxes |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## What it does

THIS SCRIPT IS READ-ONLY. It connects to Exchange Online as the client's app, lists the mailboxes (all of them, or the one in TargetMailbox) and for each one collects three kinds of access that someone other than the owner holds: FullAccess (Get-EXOMailboxPermission, only permissions assigned directly to the mailbox, not inherited, not denied, and not the owner's own NT AUTHORITY\SELF entry), SendAs (Get-EXORecipientPermission, allowed entries other than SELF) and SendOnBehalf (the mailbox's GrantSendOnBehalfTo list). One data row per grant: Mailbox, MailboxType, Permission, Trustee. Permissions given to a group show the group as the trustee; this script does not expand group members. Folder and calendar permissions are not included.

It makes two or three Exchange calls per mailbox, so a tenant with thousands of mailboxes takes a while (Exchange may throttle; a mailbox that fails is reported as a warning and the run goes on). Use MailboxType or TargetMailbox to narrow it. Permissions whose trustee no longer resolves show as a SID (S-1-5-21-...): those are leftovers worth removing. SKIPPED when the ExchangeOnlineManagement module is not installed. One tenant per run.

Permissions: Microsoft Graph application permission Organization.Read.All (the shared helper reads the tenant's initial domain, GET /organization); Exchange.ManageAsApp on Office 365 Exchange Online; and an Exchange role that can read mailbox permissions (Global Reader or View-Only Organization Management is expected to be enough; this script runs only Get-EXO* cmdlets).

Where each fact comes from (Microsoft Learn): Get-EXOMailboxPermission (-Identity, -ExternalDirectoryObjectId, -User, output Identity, User, AccessRights, IsInherited, Deny, and the note that NT AUTHORITY\SELF holds FullAccess on every mailbox), Get-EXORecipientPermission (-Identity, -ExternalDirectoryObjectId, -Trustee, -AccessRights, SendAs is the only value), Get-EXOMailbox (-RecipientTypeDetails, -ResultSize, -Properties; GrantSendOnBehalfTo is in the Delivery property set), Set-Mailbox (GrantSendOnBehalfTo lists who can send on behalf). Not confirmed in the documentation, so read defensively: the output property names of Get-EXORecipientPermission (Trustee, AccessControlType, IsInherited) and how GrantSendOnBehalfTo values print (the run shows them as text); whether an app-only session with a read role can run Get-EXOMailboxPermission (the run reports the error per mailbox).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client's tenant ID (a GUID) or domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate, with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. Leave empty to use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `TargetMailbox` | One mailbox (its address or UPN). Default empty: every mailbox of the chosen MailboxType. | (empty) | `TargetMailbox` or `TARGET_MAILBOX` |
| `MailboxType` | All (default: user, shared, room and equipment mailboxes), User, Shared or Resource (room and equipment). Ignored when TargetMailbox is set. | `All` | `MailboxType` or `MAILBOX_TYPE` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-mailbox-permissions.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -MailboxType Shared
Lists who can access each shared mailbox.
```

```powershell
.\get-mailbox-permissions.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -TargetMailbox jane@contoso.com
Lists who has access to Jane's mailbox.
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
14 mailbox access grant(s) on 9 of 120 mailbox(es): FullAccess 8, SendAs 4, SendOnBehalf 2
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Mailbox`, `MailboxType`, `Permission`, `Trustee`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-19 First version (untested).

## More

Full page: https://mspoutpost.com/scripts/get-mailbox-permissions

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
