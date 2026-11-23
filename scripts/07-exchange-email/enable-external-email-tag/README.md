# Tag external email in Outlook

> Turns on Outlook's native External tag for mail from outside the company, with an optional list of senders that should not get it.

| | |
|---|---|
| Script | `enable-external-email-tag.ps1` |
| Type | Action |
| Category | Exchange & email |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: Organization.Read.All; ExchangeOnlineManagement 3.1+, Exchange.ManageAsApp, Exchange admin role |
| Changes | Sets external sender identification Enabled true and adds AllowSenders to its allow list; writes a before-state JSON file |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under a minute |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## What it does

THIS SCRIPT CHANGES THINGS. It connects to Exchange Online as the client's app and reads the external sender identification setting (Get-ExternalInOutlook: Enabled and AllowList). When it is off it turns it on (Set-ExternalInOutlook -Enabled $true): Outlook, Outlook for Mac, Outlook on the web and Outlook for iOS and Android then show an External label beside the subject of messages from outside the organization. When you list AllowSenders (domains such as partner.com, subdomain patterns such as *.partner.com, or addresses) any that are not on the allow list yet are added to it (the Add form of -AllowList, which keeps every existing entry); entries that are already there are left alone, and nothing is ever removed. Microsoft says the allow list holds at most 200 entries and 8 KB in all, and that it uses the 5322.From address. It changes only this one organization setting. It does not create a banner or mail flow rule: Microsoft says that if your organization already uses a mail flow rule to add text to the subject of external messages you should disable that rule before turning this on, to avoid duplicates, and this script cannot judge whether such a rule exists, so check the mail flow rules yourself.

Before it changes anything it writes the before-state (Enabled and the allow list) to a JSON file under %ProgramData%\MSPOutpost\Backups\enable-external-email-tag\<time>\before-state.json and prints its path. Afterwards it re-reads the setting (up to 6 times, 5 seconds apart) and fails (exit 2) if it did not take. A second run after a real change ends OK "Already ...". SKIPPED when the ExchangeOnlineManagement module is not installed. One tenant per run.

Permissions: Microsoft Graph application permission Organization.Read.All (the shared helper reads the tenant's initial domain, GET /organization); Exchange.ManageAsApp on Office 365 Exchange Online; and an Exchange role that can run Set-ExternalInOutlook (Exchange Administrator works; the exact narrower role is not named on the cmdlet page).

Where each fact comes from (Microsoft Learn): Set-ExternalInOutlook (-Enabled, -AllowList with domains, *.domain and addresses, the @{Add=...; Remove=...} form, "meaningful only when Enabled is $true", 200 entries and 8 KB, duplicate-rule advice, -Identity is optional and resolves to the organization), Get-ExternalInOutlook (Enabled and AllowList are the important output properties) and the app-only authentication guide. Not confirmed in the documentation, so read defensively: how long the setting takes to show in Outlook clients (the script verifies the setting, not a client); how AllowList values print (compared as lower-case text); the narrowest Exchange role that may run Set-ExternalInOutlook.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client's tenant ID (a GUID) or domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate, with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. Leave empty to use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `AllowSenders` | Domains (partner.com), subdomain patterns (*.partner.com) or addresses (billing@partner.com) that should not get the External label, separated by comma, semicolon or new line. Default none. Entries are only added. | (empty) | `AllowSenders` or `ALLOW_SENDERS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\enable-external-email-tag.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Turns on the External label in Outlook for the whole tenant.
```

```powershell
.\enable-external-email-tag.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -AllowSenders partner.com,*.fabrikam.com
Turns it on and keeps the label off messages from partner.com and fabrikam.com.
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
External sender tag turned on; 2 allow-list entry(ies) added; before-state saved
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\enable-external-email-tag.log`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/enable-external-email-tag

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
