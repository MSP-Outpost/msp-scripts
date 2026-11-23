# Employee left - Microsoft 365 offboarding

> Offboards one Microsoft 365 user: blocks sign-in, revokes sessions, removes groups and licences, converts the mailbox to shared and hands it to a manager.

| | |
|---|---|
| Script | `invoke-m365-offboarding.ps1` |
| Type | Action |
| Category | Offboarding & decommission |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph user, group and license permissions (see the script); Exchange app access for mail |
| Changes | Blocks sign-in; revokes sessions; removes group memberships; converts the mailbox to shared; sets the auto-reply, forwarding, manager access and address-list visibility; removes direct licences; writes a before-state JSON file |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | Under 3 minutes |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=invoke-m365-offboarding`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\invoke-m365-offboarding.log`.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. For the ONE user in UserPrincipalName it can, each as a separate logged change and each switched off by its input:

1. block sign-in (accountEnabled = false);
2. revoke all sign-in sessions and refresh tokens;
3. remove the user from groups: Microsoft 365 groups and security groups only. Dynamic-membership groups, groups synced from on-premises Active Directory, role-assignable groups and mail-enabled security or distribution groups (managed in Exchange) are skipped and listed;
4. convert the mailbox to a shared mailbox (Exchange Online);
5. set the automatic reply to AutoReplyText for internal and external senders (Exchange Online);
6. when ManagerUpn is set: forward the mail to the manager and keep a copy (Forward), grant the manager Full Access to the mailbox (FullAccess) or both, as ManagerMailboxAccess says (Exchange Online);
7. hide the mailbox from address lists (Exchange Online);
8. remove the licences assigned directly to the user (licences inherited from a group go when the group membership goes, and are listed otherwise). ORDER: the mailbox is converted to shared BEFORE the licences are removed, so the mailbox is never left unlicensed and unconverted; if a mailbox step fails the run stops before any licence is removed. Before anything changes, the user's groups, licences and mailbox settings (forwarding, auto-reply, address-list visibility) are written as JSON under the MSP Outpost data folder (the file is named in the output) so each step can be undone by hand. It NEVER deletes the user, the mailbox, a group or a licence subscription, never resets the password and never removes OneDrive data. High risk: it is a dry run until DryRun=false AND Approve=invoke-m365-offboarding are both set. Running it again repeats only what is still undone, plus the steps that always run (sign-in sessions are revoked again, and the auto-reply, forwarding and Full Access steps run again when their inputs are set). Users synced from on-premises Active Directory cannot be blocked or hidden from Microsoft 365: those two steps are skipped with a note and must be done in Active Directory.

Microsoft Graph application permissions (admin consent): User.EnableDisableAccount.All and User.Read.All (block sign-in), User.RevokeSessions.All, GroupMember.ReadWrite.All and Directory.Read.All (groups), LicenseAssignment.ReadWrite.All (licences). The app also needs an Entra administrator role that may change administrators if the user is one (Microsoft's rule for sensitive actions). Exchange steps need ExchangeOnlineManagement 3.1 or later, the Exchange.ManageAsApp permission and the Exchange Administrator role on the app. Exchange steps are only used when switched on; when the module is missing the run is SKIPPED before anything changes.

Where each fact comes from (read in Microsoft's reference): PATCH v1.0/users/{id} accountEnabled (User.EnableDisableAccount.All + User.Read.All is the least-privileged pair; sensitive-action role rule for app-only calls); POST v1.0/users/{id}/revokeSignInSessions (User.RevokeSessions.All); GET v1.0/users/{id}/memberOf/microsoft.graph.group (needs ConsistencyLevel eventual and $count for the cast; Directory.Read.All for another user); DELETE v1.0/groups/{id}/members/{id}/$ref (GroupMember.ReadWrite.All; dynamic groups cannot be changed; role-assignable groups also need RoleManagement.ReadWrite.Directory, which this script does not use); POST v1.0/users/{id}/assignLicense with removeLicenses (LicenseAssignment.ReadWrite.All); licenseAssignmentStates.assignedByGroup (null when assigned directly); Set-Mailbox -Type Shared, -ForwardingAddress, -DeliverToMailboxAndForward, -HiddenFromAddressListsEnabled; Set-MailboxAutoReplyConfiguration -AutoReplyState Enabled -InternalMessage -ExternalMessage -ExternalAudience All; Add-MailboxPermission -AccessRights FullAccess. Not confirmed in the documentation, so read defensively: the Get-Mailbox output property names ForwardingAddress, ForwardingSmtpAddress, DeliverToMailboxAndForward, RecipientTypeDetails and HiddenFromAddressListsEnabled (named on the Set-Mailbox page, not on Get-Mailbox); what Add-MailboxPermission does when the manager already has the permission (the run reports the error); whether a mail-enabled group is always unmanageable from Graph (this script skips them rather than try); the exact Exchange role the app needs (Exchange Administrator is Microsoft's usual answer).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint (40 hex characters) of the app's certificate with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. When empty, the secret is read from the environment variable ClientSecret (a secure RMM field). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `UserPrincipalName` | The user to offboard, such as jane@contoso.com. Required. One user per run. | (empty) | `UserPrincipalName` or `USER_PRINCIPAL_NAME` |
| `BlockSignIn` | true to block sign-in. Default true. | `true` | `BlockSignIn` or `BLOCK_SIGN_IN` |
| `RevokeSessions` | true to revoke sessions and refresh tokens. Default true. | `true` | `RevokeSessions` or `REVOKE_SESSIONS` |
| `RemoveFromGroups` | true to remove the user from groups (not dynamic, not synced, not role-assignable, not mail-enabled security or distribution). Default true. | `true` | `RemoveFromGroups` or `REMOVE_FROM_GROUPS` |
| `ConvertToShared` | true to convert the mailbox to a shared mailbox. Default true. | `true` | `ConvertToShared` or `CONVERT_TO_SHARED` |
| `AutoReplyText` | Text of the automatic reply for internal and external senders. Empty (default) leaves the auto-reply alone. | (empty) | `AutoReplyText` or `AUTO_REPLY_TEXT` |
| `ManagerUpn` | The manager who receives the mail or the access, such as boss@contoso.com. Empty (default) skips that step. | (empty) | `ManagerUpn` or `MANAGER_UPN` |
| `ManagerMailboxAccess` | What ManagerUpn gets: FullAccess (default), Forward (forward and keep a copy), Both or None. | `FullAccess` | `ManagerMailboxAccess` or `MANAGER_MAILBOX_ACCESS` |
| `HideFromAddressLists` | true to hide the mailbox from address lists. Default true. | `true` | `HideFromAddressLists` or `HIDE_FROM_ADDRESS_LISTS` |
| `RemoveLicenses` | true to remove the directly assigned licences, after the mailbox steps. Default true. | `true` | `RemoveLicenses` or `REMOVE_LICENSES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\invoke-m365-offboarding.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -UserPrincipalName jane@contoso.com -ManagerUpn boss@contoso.com
Dry run: lists everything it would do for Jane and changes nothing.
```

```powershell
.\invoke-m365-offboarding.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -UserPrincipalName jane@contoso.com -AutoReplyText "Jane has left. Please write to sales@contoso.com." -DryRun false -Approve invoke-m365-offboarding
Offboards Jane for real, with an auto-reply and the defaults for the other steps.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `TenantId`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `invoke-m365-offboarding`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Offboarded jane@contoso.com: sign-in blocked, sessions revoked, 4 groups, mailbox shared, 2 licences
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\invoke-m365-offboarding.log`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-18 First version.

## More

Full page: https://mspoutpost.com/scripts/invoke-m365-offboarding

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
