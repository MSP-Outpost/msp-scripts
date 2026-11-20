# Give or remove mailbox access

> Gives or removes one person's Full Access, Send As or Send on Behalf on one mailbox, with control of Outlook automapping.

| | |
|---|---|
| Script | `set-mailbox-permission.ps1` |
| Type | Action |
| Category | Exchange & email |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: Organization.Read.All; ExchangeOnlineManagement 3.1+, Exchange.ManageAsApp, Exchange admin role |
| Changes | Adds or removes one FullAccess, SendAs or SendOnBehalf permission for one user on one mailbox |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## What it does

THIS SCRIPT CHANGES THINGS. It connects to Exchange Online as the client's app and, for the ONE mailbox in Mailbox and the ONE user or mail-enabled security group in Delegate, does what Operation says (Grant is the default, or Remove) for the kind of access in Access: FullAccess (Add-MailboxPermission or Remove-MailboxPermission, InheritanceType All), SendAs (Add-RecipientPermission or Remove-RecipientPermission) or SendOnBehalf (Set-Mailbox -GrantSendOnBehalfTo with Add or Remove). AutoMapping (default true, the Microsoft default) says whether the mailbox is added to the user's Outlook profile automatically when FullAccess is granted; it applies only when granting FullAccess. It checks first: granting access the user already has, or removing access the user does not have, changes nothing and ends OK "Already ...". If a user already has FullAccess, the AutoMapping setting cannot be changed in place: Microsoft's documented way is to remove the permission and grant it again with the new setting. It never touches any other permission, never grants access to more than one person per run, and never changes folder or calendar permissions. Each change is logged in the MSP Outpost change log. SKIPPED when the ExchangeOnlineManagement module is not installed. One tenant per run.

Afterwards it re-reads the access (up to 6 times, 5 seconds apart, because Exchange shows a change late) and fails (exit 2) if the access is not as asked. A second run after a real change ends OK "Already ...".

Permissions: Microsoft Graph application permission Organization.Read.All (the shared helper reads the tenant's initial domain, GET /organization); Exchange.ManageAsApp on Office 365 Exchange Online; and an Exchange role that can run Add-MailboxPermission, Add-RecipientPermission and Set-Mailbox (Exchange Administrator works; Global Reader does not).

Where each fact comes from (Microsoft Learn): Add-MailboxPermission (-AccessRights FullAccess, -InheritanceType All, -AutoMapping default $true, the note that to disable automapping for a user who already has FullAccess you remove then re-add, -User may be a mail-enabled security group but a group does not get automapping), Remove-MailboxPermission, Get-EXOMailboxPermission (-Identity, -User; AccessRights, IsInherited, Deny), Add-RecipientPermission and Remove-RecipientPermission (-AccessRights SendAs, -Trustee, -Confirm:$false), Get-EXORecipientPermission (-Identity, -Trustee), Set-Mailbox -GrantSendOnBehalfTo (@{Add=...} and @{Remove=...} syntax), and the app-only guide. Not confirmed in the documentation, so read defensively: that Get-EXOMailboxPermission -User accepts an SMTP address; how GrantSendOnBehalfTo values print (the run compares them with the recipient's name, alias, address and distinguished name); what Add-MailboxPermission does when the permission already exists (the run checks first so it should not arise); whether Add-RecipientPermission needs -Confirm:$false in an unattended run (it is passed).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client's tenant ID (a GUID) or domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate, with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. Leave empty to use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `Mailbox` | The mailbox to change access on (its address or UPN). Required. | (empty) | `Mailbox` or `MAILBOX` |
| `Delegate` | Who gets or loses the access (a user's address or UPN, or a mail-enabled security group's address). Required. | (empty) | `Delegate` or `DELEGATE` |
| `Access` | FullAccess (default), SendAs or SendOnBehalf. | `FullAccess` | `Access` or `ACCESS` |
| `Operation` | Grant (default) or Remove. | `Grant` | `Operation` or `OPERATION` |
| `AutoMapping` | true (default) to let Outlook add the mailbox automatically when FullAccess is granted; false to stop that. Only used by Grant with FullAccess. | `true` | `AutoMapping` or `AUTO_MAPPING` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\set-mailbox-permission.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -Mailbox support@contoso.com -Delegate jane@contoso.com -AutoMapping false
Gives Jane Full Access to the support mailbox without adding it to her Outlook automatically.
```

```powershell
.\set-mailbox-permission.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -Mailbox support@contoso.com -Delegate jane@contoso.com -Access SendAs -Operation Remove
Removes Jane's Send As permission on the support mailbox.
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
Granted FullAccess on support@contoso.com to jane@contoso.com (automapping off)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\set-mailbox-permission.log`.

## Changelog

- 1.0.0 2026-11-19 First version (untested).

## More

Full page: https://mspoutpost.com/scripts/set-mailbox-permission

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
