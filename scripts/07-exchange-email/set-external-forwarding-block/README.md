# Block automatic external forwarding for the tenant

> Blocks automatic forwarding to outside addresses for the whole tenant: sets the default outbound spam filter policy to AutoForwardingMode Off, with an optional list of senders who may still forward.

| | |
|---|---|
| Script | `set-external-forwarding-block.ps1` |
| Type | Action |
| Category | Exchange & email |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: Organization.Read.All; ExchangeOnlineManagement 3.1+, Exchange.ManageAsApp, Exchange admin role |
| Changes | Sets AutoForwardingMode Off on the default outbound spam filter policy; with ExceptionSenders also creates or updates one outbound spam filter policy and rule; writes a before-state JSON file |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | Under a minute |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=set-external-forwarding-block`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\set-external-forwarding-block.log`.
- Run the dry run first and read the list.

## What it does

HIGH RISK: it changes how mail is handled for every mailbox in the tenant. It does nothing unless you run it with DryRun=false AND Approve=set-external-forwarding-block; otherwise it lists what it would do. Microsoft documents that with AutoForwardingMode Off, automatic forwarding to external recipients (inbox rules and mailbox forwarding alike) is disabled and the sender of the forwarded message gets a non-delivery report (5.7.520); forwarding between internal users is not affected. Run test-external-mail-forwarding first to see which forwards will start bouncing.

What it changes: 1) the DEFAULT outbound spam filter policy (the one with IsDefault true, named Default): AutoForwardingMode is set to Off when it is Automatic or On. (Automatic behaves as On or Off depending on the tenant, so it is not trusted.) 2) Only when you list ExceptionSenders: a separate outbound spam filter policy named "MSP Outpost allow external forwarding" with AutoForwardingMode On, and a rule of the same name that applies that policy to exactly those senders (rule condition From). Existing exception lists are replaced by the list you give. It never deletes a policy or a rule, never touches other policies, and never touches mailbox forwarding or inbox rules (use remove-external-mail-forwarding for those). Preset security policies (Standard or Strict) take precedence over custom policies in Microsoft's model, so a sender covered by a preset policy follows the preset's outbound policy, not this exception.

Before it changes anything it writes the before-state (the default policy's mode, the exception policy and rule if they exist) to a JSON file under %ProgramData%\MSPOutpost\Backups\set-external-forwarding-block\<time>\before-state.json and prints that file's path. Afterwards it re-reads the policies (up to 6 times, 5 seconds apart, because Exchange shows a change late) and fails (exit 2) if the setting did not take. A second run after a real change ends OK "Already ...". SKIPPED when the ExchangeOnlineManagement module is not installed. One tenant per run.

Permissions: Microsoft Graph application permission Organization.Read.All (the shared helper reads the tenant's initial domain, GET /organization); Exchange.ManageAsApp on Office 365 Exchange Online; and an Exchange role that can run Set-HostedOutboundSpamFilterPolicy, New-HostedOutboundSpamFilterPolicy and the outbound spam filter rule cmdlets (Exchange Administrator, or the Organization Management or Security Administrator role groups).

Where each fact comes from (Microsoft Learn): Set-HostedOutboundSpamFilterPolicy (-Identity accepts the Name, -AutoForwardingMode Automatic, On or Off, the Default policy is addressed as "Default" in the example), Get-HostedOutboundSpamFilterPolicy (example output columns Name, Enabled, IsDefault), New-HostedOutboundSpamFilterPolicy (a new policy is not applied to anyone until a rule names it), New-HostedOutboundSpamFilterRule and Set-HostedOutboundSpamFilterRule (-HostedOutboundSpamFilterPolicy, -From, -Comments), Get-HostedOutboundSpamFilterRule (columns Name, Priority, State), the forwarding article (values and the NDR text) and the app-only authentication guide. Not confirmed in the documentation, so read defensively: that the Default policy always has IsDefault true (the run falls back to the name Default); the form in which Get-HostedOutboundSpamFilterRule returns the From values (the run compares them with each sender's name, alias, address and distinguished name); that a rule created without -Priority lands below existing rules; the exact precedence between preset security policies and this exception policy.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client's tenant ID (a GUID) or domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate, with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. Leave empty to use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `ExceptionSenders` | Mailbox addresses that may keep forwarding outside (for example a scanner or a shared mailbox that forwards to a partner), separated by comma, semicolon or new line. Default none: no exception policy is created or changed. When set, the list REPLACES the exception rule's senders. | (empty) | `ExceptionSenders` or `EXCEPTION_SENDERS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\set-external-forwarding-block.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Dry run: says what it would change and changes nothing.
```

```powershell
.\set-external-forwarding-block.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -ExceptionSenders scanner@contoso.com -DryRun false -Approve set-external-forwarding-block
Turns automatic external forwarding off for everyone except scanner@contoso.com, after saving the before-state.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `TenantId`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `set-external-forwarding-block`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Automatic external forwarding is now Off tenant-wide; 1 sender(s) exempt; before-state saved
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\set-external-forwarding-block.log`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/set-external-forwarding-block

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
