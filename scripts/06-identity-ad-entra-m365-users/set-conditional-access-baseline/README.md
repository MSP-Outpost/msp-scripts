# Deploy the Conditional Access baseline

> Deploys the MSP Conditional Access baseline (MFA for everyone, block legacy sign-in, MFA for admins), first in report-only mode.

| | |
|---|---|
| Script | `set-conditional-access-baseline.ps1` |
| Type | Action |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: Policy.ReadWrite.ConditionalAccess, Policy.Read.All, User.Read.All; Entra ID P1 |
| Changes | Creates three Conditional Access policies (report-only by default); with Enforce switches them to enabled; optionally turns Security Defaults off |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=set-conditional-access-baseline`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\set-conditional-access-baseline.log`.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. It creates up to three Conditional Access policies, each with a name that starts with "MSP Outpost baseline: ":

1. "MSP Outpost baseline: MFA for all users": all users, all cloud apps, grant control "require multifactor authentication".
2. "MSP Outpost baseline: Block legacy authentication": all users, all cloud apps, client app types Exchange ActiveSync and "other" (legacy protocols that cannot do MFA), grant control "block".
3. "MSP Outpost baseline: MFA for administrators": 15 directory admin roles (the list in the AdminRoleIds constant: Global, Privileged Role, Security, Exchange, SharePoint, User, Conditional Access, Helpdesk, Billing, Authentication, Privileged Authentication, Application, Cloud Application, Password and Global Reader), all cloud apps, grant control "require multifactor authentication". It repeats policy 1 on purpose: it keeps admins covered if someone later narrows or disables policy 1. EVERY policy excludes the break-glass accounts you name in BreakGlassAccounts (required: at least one, two are recommended, and each must exist), so a mistake cannot lock you out of the tenant. The policies are created in REPORT-ONLY state (they log what they would block and block nothing). Read the Conditional Access insights and sign-in logs for a week or two, then run the script again with Enforce=true, which changes these policies from report-only to enabled. With Enforce=true on a first run the policies are created enabled at once; every user without MFA is asked to register at their next sign-in, and every legacy mail client stops working. It does not create the risk-based policies (they need Entra ID P2), named locations or device policies, never edits or deletes a policy that already exists other than switching a report-only baseline policy to enabled, never touches a policy whose name does not start with the prefix, and never switches an enabled baseline policy back to report-only or switches on a policy an admin disabled. Security Defaults and Conditional Access cannot both be on. When Security Defaults is on the script stops before any change and says so, unless DisableSecurityDefaults is true, in which case it turns Security Defaults off first (Security Defaults is what protects the tenant until the new policies are enforced: leave it on and create the policies by hand if report-only is not enough for you). Idempotent by name: a run that finds all three policies (and nothing to enforce) changes nothing and says "Already deployed". It warns when an existing baseline policy does not exclude one of your break-glass accounts; it does not fix it.

HIGH RISK: it is a dry run (lists every policy it would create or enforce, changes nothing) unless DryRun=false AND Approve=set-conditional-access-baseline, and it refuses to make more than MaxChanges (default 25) changes in one run. Before the first change it writes the current baseline policies and the Security Defaults state as JSON under %ProgramData%\MSPOutpost\Backups\set-conditional-access-baseline\ and prints the file name.

Permission (Microsoft Graph APPLICATION): Policy.ReadWrite.ConditionalAccess and Policy.Read.All (create and update policies; Microsoft's known-issues page says the create and update calls also need Policy.Read.All), User.Read.All (look up the break-glass accounts). Turning Security Defaults off needs Policy.ReadWrite.ConditionalAccess and Policy.Read.All too. Entra ID P1 is needed for Conditional Access.

Where each fact comes from (read in the Microsoft Graph v1.0 reference): POST /identity/conditionalAccess/policies (201; displayName, state enabled / disabled / enabledForReportingButNotEnforced, conditions.clientAppTypes, conditions.applications.includeApplications "All", conditions.users.includeUsers "All", includeRoles with role IDs, excludeUsers with user IDs, grantControls.operator and builtInControls "mfa" or "block"), GET /identity/conditionalAccess/policies, PATCH /identity/conditionalAccess/policies/{id} (204), PATCH /policies/identitySecurityDefaultsEnforcementPolicy with {"isEnabled": false} (204), and the role template IDs of the permissions reference. Not confirmed in the documentation, so read defensively: the client app type values "exchangeActiveSync" and "other" for legacy protocols (both are in the clientAppTypes enum list; which legacy clients each covers is from experience, not the page), that includeUsers may be empty when includeRoles is set (the list page's own example shows it), the role template IDs for Password Administrator (966707d0-3269-4727-9be2-8c3a10f19b9d) and Global Reader (f2ef992c-3afb-46b9-b7cf-a126ee74c451), which come from Microsoft's example responses and not from the permissions reference page I read, that creating a policy in a tenant without Entra ID P1 fails (the error is shown as is), and that a policy shows up in the list within about 30 seconds (the check reads up to 6 times, 5 seconds apart).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The Application (client) ID of the app registration that holds the Graph permissions. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (private key in LocalMachine\My or CurrentUser\My). Preferred. When empty, the app secret is read from the environment variable ClientSecret (a secure/hidden RMM field; never an argument). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `BreakGlassAccounts` | Sign-in names of your emergency-access (break-glass) accounts, separated by comma, semicolon or new line. Every policy excludes them. Required. | (empty) | `BreakGlassAccounts` or `BREAK_GLASS_ACCOUNTS` |
| `Enforce` | true to switch the baseline policies to enabled (new ones are created enabled, report-only ones are switched). Default false: report-only. | `false` | `Enforce` or `ENFORCE` |
| `DisableSecurityDefaults` | true to turn Security Defaults off when it is on (it must be off before Conditional Access policies can be enabled). Default false: the script refuses. | `false` | `DisableSecurityDefaults` or `DISABLE_SECURITY_DEFAULTS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\set-conditional-access-baseline.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -BreakGlassAccounts "bg1@contoso.onmicrosoft.com,bg2@contoso.onmicrosoft.com"
Dry run: lists the three policies it would create in report-only state.
```

```powershell
.\set-conditional-access-baseline.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -BreakGlassAccounts "bg1@contoso.onmicrosoft.com,bg2@contoso.onmicrosoft.com" -Enforce true -DryRun false -Approve set-conditional-access-baseline
Switches the report-only baseline policies to enabled.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `TenantId`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `set-conditional-access-baseline`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Created 3 baseline Conditional Access policy(ies) in report-only; review sign-ins, then run again with Enforce=true
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\set-conditional-access-baseline.log`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/set-conditional-access-baseline

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
