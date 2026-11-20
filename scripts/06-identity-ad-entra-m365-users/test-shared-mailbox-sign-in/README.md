# Shared mailboxes that can sign in

> Alerts when a shared, room or equipment mailbox has a sign-in enabled account, which nobody should be able to use.

| | |
|---|---|
| Script | `test-shared-mailbox-sign-in.ps1` |
| Type | Monitor |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: Organization.Read.All, User.Read.All; Exchange app access (ManageAsApp), read role |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 5 minutes on a large tenant |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## What it does

THIS SCRIPT IS READ-ONLY. It connects to Exchange Online as the client's app, lists the shared mailboxes (and, unless IncludeResources is false, the room and equipment mailboxes) with Get-EXOMailbox -RecipientTypeDetails, then reads each mailbox's Entra user from Microsoft Graph (GET /users/{ExternalDirectoryObjectId}, properties accountEnabled and onPremisesSyncEnabled). A mailbox whose account is enabled can be signed in to directly with a password, which defeats the point of a shared mailbox (access is meant to come through delegation, with MFA and conditional access on the delegate) and leaves one more password to steal. The run ends ALERT, exit 1, when any such mailbox exists; the Answer names the first three. Use ExcludeMailboxes for the few that must stay signed-in (a shared mailbox that an application logs in to). Pair it with disable-shared-mailbox-sign-in, which blocks them. SKIPPED when the ExchangeOnlineManagement module is not installed. One tenant per run.

Permissions: Microsoft Graph application permissions Organization.Read.All (the shared helper reads the tenant's initial domain) and User.Read.All (reads accountEnabled); Exchange.ManageAsApp on Office 365 Exchange Online; and an Exchange role that can read recipients (Global Reader or View-Only Organization Management is enough; this script runs only Get-EXOMailbox).

Where each fact comes from (Microsoft Learn): Get-EXOMailbox (-RecipientTypeDetails values SharedMailbox, RoomMailbox, EquipmentMailbox; -ResultSize; the Minimum property set holds ExternalDirectoryObjectId, PrimarySmtpAddress, RecipientTypeDetails and UserPrincipalName), Graph GET /users/{id} with $select (accountEnabled, onPremisesSyncEnabled), and the app-only authentication guide. Not confirmed in the documentation, so read defensively: that a shared mailbox's ExternalDirectoryObjectId is the object ID of its Entra user (the run reports an error per mailbox that Graph cannot find, and skips it with a warning); that Microsoft creates shared and resource mailbox accounts with sign-in blocked (assumed from experience, not read); the exact Exchange role names a service principal needs.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client's tenant ID (a GUID) or domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate, with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. Leave empty to use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `IncludeResources` | true (default) to check room and equipment mailboxes as well as shared mailboxes. | `true` | `IncludeResources` or `INCLUDE_RESOURCES` |
| `ExcludeMailboxes` | Addresses (or UPNs) that are allowed to have sign-in enabled, separated by comma, semicolon or new line. Default none. | (empty) | `ExcludeMailboxes` or `EXCLUDE_MAILBOXES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-shared-mailbox-sign-in.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Alerts when any shared, room or equipment mailbox can be signed in to.
```

```powershell
.\test-shared-mailbox-sign-in.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -IncludeResources false -ExcludeMailboxes scanner@contoso.com
Checks shared mailboxes only, and accepts scanner@contoso.com as signed-in.
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
Sign-in enabled on 2 shared/resource mailbox(es): support@contoso.com (shared); room1@contoso.com (room)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Mailbox`, `Type`, `AccountEnabled`, `SyncedFromOnPremises`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-19 First version (untested).

## More

Full page: https://mspoutpost.com/scripts/test-shared-mailbox-sign-in

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
