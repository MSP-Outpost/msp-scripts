# Audit logging off - turn on unified and mailbox auditing

> Turns on Microsoft 365 auditing: the unified audit log and mailbox auditing for the whole tenant, and optionally removes mailbox audit bypass.

| | |
|---|---|
| Script | `enable-audit-logging.ps1` |
| Type | Action |
| Category | Exchange & email |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: Organization.Read.All; ExchangeOnlineManagement 3.1+, Exchange.ManageAsApp, Exchange admin role |
| Changes | Sets UnifiedAuditLogIngestionEnabled true and AuditDisabled false; with ClearAuditBypass also switches mailbox audit bypass off; writes a before-state JSON file |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under a minute |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## What it does

THIS SCRIPT CHANGES THINGS. It connects to Exchange Online as the client's app and checks three things Microsoft documents: 1) UnifiedAuditLogIngestionEnabled from Get-AdminAuditLogConfig (the Microsoft 365 audit log; Microsoft notes auditing is not on by default for Business Basic, Standard and Premium or for trial tenants). 2) AuditDisabled from Get-OrganizationConfig (mailbox auditing on by default; False means on; when it is True no mailbox action is audited whatever a mailbox says). 3) Accounts with mailbox audit bypass (Get-MailboxAuditBypassAssociation, AuditByPassEnabled True): actions by those accounts are never logged. It turns on what is off: Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true and Set-OrganizationConfig -AuditDisabled $false. Because mailbox auditing on by default overrides each mailbox's own AuditEnabled setting, no per-mailbox change is needed. Bypass accounts are only listed (a warning) unless you set ClearAuditBypass=true, which switches the bypass off for each of them (Set-MailboxAuditBypassAssociation -AuditByPassEnabled $false). Bypass is sometimes deliberate (a backup or migration service account), so the default leaves it alone. It never turns auditing off, never changes which mailbox actions are audited and never changes retention.

Microsoft says audit events can take several hours to become searchable after you turn on auditing, and that the change can take up to 60 minutes to take effect; the script verifies the settings, not the first events. Before it changes anything it writes the before-state (both settings and the bypass accounts) to a JSON file under %ProgramData%\MSPOutpost\Backups\enable-audit-logging\<time>\before-state.json and prints its path. Afterwards it re-reads the settings (up to 6 times, 5 seconds apart) and fails (exit 2) if one did not take. A second run after a real change ends OK "Already ...". SKIPPED when the ExchangeOnlineManagement module is not installed. One tenant per run.

Permissions: Microsoft Graph application permission Organization.Read.All (the shared helper reads the tenant's initial domain, GET /organization); Exchange.ManageAsApp on Office 365 Exchange Online; and an Exchange role that includes the Audit Logs role (Microsoft names it for turning auditing on; Compliance Management and Organization Management role groups have it) and the Organization Configuration role for Set-OrganizationConfig. Exchange Administrator covers both.

Where each fact comes from (Microsoft Learn): the two articles above (verify and turn on, the Audit Logs role, "up to 60 minutes", the note that UnifiedAuditLogIngestionEnabled is only reliable in Exchange Online PowerShell, mailbox auditing on by default and AuditDisabled, bypass), Set-OrganizationConfig -AuditDisabled (True disables mailbox auditing for the organization, False allows it) and Get-MailboxAuditBypassAssociation (-ResultSize, the AuditBypassEnabled property). Not confirmed in the documentation, so read defensively: whether Get-AdminAuditLogConfig shows True immediately after the change (the run waits up to 30 seconds, then fails); that the exact Exchange role names above are the minimum for an app-only service principal; whether Get-MailboxAuditBypassAssociation -ResultSize Unlimited lists every account in a large tenant.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client's tenant ID (a GUID) or domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate, with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. Leave empty to use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `ClearAuditBypass` | true to also switch mailbox audit bypass off for every account that has it. Default false: bypass accounts are only listed. | `false` | `ClearAuditBypass` or `CLEAR_AUDIT_BYPASS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\enable-audit-logging.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -DryRun true
Lists which auditing settings are off and would be turned on.
```

```powershell
.\enable-audit-logging.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -ClearAuditBypass true
Turns on the unified audit log and mailbox auditing and clears every audit bypass.
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
Auditing turned on: unified audit log on, mailbox auditing on, 0 bypass account(s) cleared; before-state saved
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\enable-audit-logging.log`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/enable-audit-logging

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
