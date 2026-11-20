# Shared mailboxes that can sign in - block them

> Blocks sign-in on shared, room and equipment mailboxes whose account is enabled, so they can only be used through delegation.

| | |
|---|---|
| Script | `disable-shared-mailbox-sign-in.ps1` |
| Type | Action |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: User.Read.All, User.EnableDisableAccount.All, Organization.Read.All; Exchange app access |
| Changes | Sets accountEnabled false on the Entra account of each shared, room or equipment mailbox that can sign in; writes a before-state JSON file |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | Under 5 minutes on a large tenant |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=disable-shared-mailbox-sign-in`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\disable-shared-mailbox-sign-in.log`.
- Run the dry run first and read the list.

## What it does

HIGH RISK: it blocks accounts. It does nothing unless you run it with DryRun=false AND Approve=disable-shared-mailbox-sign-in; otherwise it lists what it would do. It connects to Exchange Online as the client's app and finds what "test-shared-mailbox-sign-in" finds: shared mailboxes (and, unless IncludeResources is false, room and equipment mailboxes) whose Entra account has accountEnabled true. For each it sets accountEnabled to false (Microsoft Graph PATCH /users/{id}). Mail delivery, delegates' access (FullAccess, SendAs) and calendar booking keep working: only direct sign-in with the mailbox's own password is blocked. Do not block a shared mailbox that an application or a person really signs in to (a scanner, an old script): list it in ExcludeMailboxes first. The mailbox itself, its licences, its permissions and its data are never touched, and nothing is deleted. Accounts synced from on-premises Active Directory cannot be changed through Graph: they are listed as skipped and must be disabled in Active Directory.

Before it changes anything it writes the before-state (each mailbox, its user ID and its accountEnabled value) to a JSON file under %ProgramData%\MSPOutpost\Backups\disable-shared-mailbox-sign-in\<time>\before-state.json and prints that file's path; to undo, set accountEnabled back to true for the listed IDs. It stops without changing anything when more than MaxChanges (default 25) accounts are planned: check the dry run, then raise MaxChanges. Afterwards it re-reads every account (up to 6 times, 5 seconds apart, because Entra shows a change late) and fails (exit 2) if one is still enabled. A second run after a real change ends OK "Already ...". SKIPPED when the ExchangeOnlineManagement module is not installed. One tenant per run.

Permissions: Microsoft Graph application permissions Organization.Read.All (the shared helper reads the tenant's initial domain), User.Read.All and User.EnableDisableAccount.All (Microsoft's least-privileged pair for updating accountEnabled); Exchange.ManageAsApp on Office 365 Exchange Online and an Exchange role that can read recipients (Global Reader is enough; this script only runs Get-EXOMailbox). The app may also need an Entra role if the account to block is an administrator (Microsoft's rule for sensitive properties).

Where each fact comes from (Microsoft Learn): Graph PATCH /users/{id} (accountEnabled; User.EnableDisableAccount.All + User.Read.All is the least privileged combination; response 204 No Content), Graph GET /users/{id}, Get-EXOMailbox and the app-only authentication guide. Not confirmed in the documentation, so read defensively: that a shared mailbox's ExternalDirectoryObjectId is its Entra user's object ID; that blocking the account does not interrupt delegate access (true as widely documented for shared mailboxes, not read on the pages above); how long Entra takes to show accountEnabled false (the run waits up to 30 seconds).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client's tenant ID (a GUID) or domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate, with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. Leave empty to use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `IncludeResources` | true (default) to handle room and equipment mailboxes as well as shared mailboxes. | `true` | `IncludeResources` or `INCLUDE_RESOURCES` |
| `ExcludeMailboxes` | Addresses (or UPNs) that must keep sign-in enabled, separated by comma, semicolon or new line. Default none. | (empty) | `ExcludeMailboxes` or `EXCLUDE_MAILBOXES` |
| `TargetMailbox` | Work on one mailbox only (its address or UPN). Default empty: every shared, room and equipment mailbox. | (empty) | `TargetMailbox` or `TARGET_MAILBOX` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\disable-shared-mailbox-sign-in.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Dry run: lists the mailbox accounts it would block.
```

```powershell
.\disable-shared-mailbox-sign-in.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -ExcludeMailboxes scanner@contoso.com -DryRun false -Approve disable-shared-mailbox-sign-in
Blocks sign-in on every shared, room and equipment mailbox except scanner@contoso.com, after saving the before-state.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `TenantId`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `disable-shared-mailbox-sign-in`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Blocked sign-in on 3 shared/resource mailbox(es); before-state saved
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\disable-shared-mailbox-sign-in.log`.

## Changelog

- 1.0.0 2026-11-19 First version (untested).

## More

Full page: https://mspoutpost.com/scripts/disable-shared-mailbox-sign-in

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
