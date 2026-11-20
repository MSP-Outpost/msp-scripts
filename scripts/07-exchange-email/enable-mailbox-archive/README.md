# Turn on the archive and auto-expanding archive

> Turns on the online archive, and the auto-expanding archive, for user mailboxes that do not have them yet.

| | |
|---|---|
| Script | `enable-mailbox-archive.ps1` |
| Type | Action |
| Category | Exchange & email |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: Organization.Read.All; ExchangeOnlineManagement 3.1+, Exchange.ManageAsApp, Exchange admin role |
| Changes | Creates the online archive and turns on auto-expanding archiving (cannot be turned off again) for mailboxes that lack them |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 10 minutes on a large tenant |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## What it does

THIS SCRIPT CHANGES THINGS. It connects to Exchange Online as the client's app and, for each user mailbox (or the one in TargetMailbox, of any type) that lacks one, creates the online archive (Enable-Mailbox -Archive), then, unless AutoExpanding is false, turns on auto-expanding archiving for that mailbox (Enable-Mailbox -AutoExpandingArchive), which Microsoft says adds storage automatically as the archive approaches its limit. Microsoft also says the archive must exist before auto-expanding can be enabled, and that auto-expanding archiving cannot be turned off again once it is on: that part is permanent. Mailboxes that already have an archive (and auto-expanding when asked) are left alone. It does NOT assign a retention policy: moving mail into the archive happens through the mailbox's retention policy, and a mailbox with a blank policy is listed as a warning. Assigning one is left to a person because a retention policy can also delete mail (Microsoft's default policy has delete tags). It does not touch shared mailboxes unless named in TargetMailbox, and never deletes or disables an archive. Each change is logged in the MSP Outpost change log. SKIPPED when the ExchangeOnlineManagement module is not installed. One tenant per run.

The archive needs a licence that includes archiving (Microsoft's licensing, not read on the pages above): a mailbox whose licence does not allow one fails with Exchange's message, the run goes on with the other mailboxes and ends ERROR naming how many failed. After enabling, it re-reads each mailbox (up to 6 times, 5 seconds apart) and fails (exit 2) if the archive did not appear. A second run after a real change ends OK "Already ...".

Permissions: Microsoft Graph application permission Organization.Read.All (the shared helper reads the tenant's initial domain, GET /organization); Exchange.ManageAsApp on Office 365 Exchange Online; and an Exchange role that can run Enable-Mailbox (Exchange Administrator works; Global Reader does not).

Where each fact comes from (Microsoft Learn): Enable-Mailbox (-Archive creates an archive mailbox for an existing user mailbox; -AutoExpandingArchive, the archive must be enabled first, cannot be disabled later), Get-EXOMailbox (-PropertySets, -RecipientTypeDetails, -ResultSize), the property sets page (Archive set: ArchiveStatus, ArchiveState, ArchiveGuid, AutoExpandingArchiveEnabled; Policy set: RetentionPolicy). Not confirmed in the documentation, so read defensively: that ArchiveStatus is Active (or ArchiveGuid is a real GUID) for a mailbox with a working archive; how long a new archive takes to show (the run waits up to 30 seconds); the licences that allow an archive and auto-expanding archive.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client's tenant ID (a GUID) or domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate, with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. Leave empty to use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `TargetMailbox` | One mailbox (its address or UPN). Default empty: every user mailbox. | (empty) | `TargetMailbox` or `TARGET_MAILBOX` |
| `AutoExpanding` | true (default) to also turn on auto-expanding archiving (permanent); false to create the archive only. | `true` | `AutoExpanding` or `AUTO_EXPANDING` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\enable-mailbox-archive.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -DryRun true
Lists the mailboxes that would get an archive and auto-expanding archiving.
```

```powershell
.\enable-mailbox-archive.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -TargetMailbox jane@contoso.com -AutoExpanding false
Creates Jane's archive only.
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
Enabled the archive on 3 mailbox(es) and auto-expanding archiving on 5
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\enable-mailbox-archive.log`.

## Changelog

- 1.0.0 2026-11-19 First version (untested).

## More

Full page: https://mspoutpost.com/scripts/enable-mailbox-archive

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
