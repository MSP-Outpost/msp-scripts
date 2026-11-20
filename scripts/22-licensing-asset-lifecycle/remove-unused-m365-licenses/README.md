# Reclaim Microsoft 365 licences from disabled users

> Removes the directly assigned Microsoft 365 licences from disabled users (and, only if you ask, from users who stopped signing in).

| | |
|---|---|
| Script | `remove-unused-m365-licenses.ps1` |
| Type | Action |
| Category | Licensing & asset lifecycle |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: User.Read.All, LicenseAssignment.ReadWrite.All, AuditLog.Read.All; Entra ID P1 |
| Changes | Removes directly assigned licences from disabled users (and inactive users with IncludeInactive); writes a before-state JSON file |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | Under 5 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-18 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=remove-unused-m365-licenses`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\remove-unused-m365-licenses.log`.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. For ONE client tenant it finds users who hold licences and are DISABLED (sign-in blocked) and removes the licences assigned directly to them, one change per user. With IncludeInactive=true it also removes the licences of ENABLED users with no sign-in for InactiveDays or more (users never seen who were created at least that long ago count too): that can take a working user's mailbox and apps away, so it is off by default and the dry run lists every name first. Users in ExcludeUsers are never touched. It never deletes a user, a mailbox or a subscription, and never changes a licence assigned through a group (those are listed as skipped: change the group instead). Disabled accounts can legitimately need a licence (a shared mailbox over 50 GB or with an archive, a mailbox on litigation hold): put them in ExcludeUsers. A removed licence starts Microsoft's grace period for the mailbox and OneDrive; it is not an instant deletion, but it is not a decision to take lightly. Before anything changes, the licences of every user it will touch (SKU id, name and disabled plans, so they can be assigned again) are written as JSON under the MSP Outpost data folder; the file is named in the output. High risk: it is a dry run until DryRun=false AND Approve=remove-unused-m365-licenses are both set, and it refuses to start if more users are planned than MaxChanges (default 25). SIGN-IN ACTIVITY NEEDS A LICENCE AND A PERMISSION: with IncludeInactive=true, Microsoft returns signInActivity only for tenants with Microsoft Entra ID P1 or P2 and only to an app with AuditLog.Read.All. Without them the run ends in ERROR before any change.

Microsoft Graph application permissions (admin consent): User.Read.All, LicenseAssignment.ReadWrite.All (assignLicense and the SKU names), and AuditLog.Read.All (only with IncludeInactive=true).

Where each fact comes from (read in Microsoft's reference): POST v1.0/users/{id}/assignLicense with an empty addLicenses and a removeLicenses list of skuIds (LicenseAssignment.ReadWrite.All least privileged); GET v1.0/users with $select of accountEnabled, assignedLicenses (includes group-inherited licences and their disabledPlans), licenseAssignmentStates (assignedByGroup is null for a direct assignment), createdDateTime and signInActivity (P1 or P2 and AuditLog.Read.All; page size 500; not returned for a user who never signed in or last signed in before April 2020); GET v1.0/subscribedSkus (skuId, skuPartNumber). Not confirmed in the documentation, so read defensively: the exact error Graph returns without P1 (reported with the service's own text); whether assignLicense can remove a licence another licence depends on (Graph then answers with an error naming the dependency, and the run stops at that user with the earlier users already changed and listed in the log).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint (40 hex characters) of the app's certificate with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. When empty, the secret is read from the environment variable ClientSecret (a secure RMM field). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `IncludeInactive` | true to also remove the licences of enabled users who have not signed in for InactiveDays. Default false (disabled users only). | `false` | `IncludeInactive` or `INCLUDE_INACTIVE` |
| `InactiveDays` | With IncludeInactive: days without a sign-in. Whole number, 1 to 3650. Default 90. | `90` | `InactiveDays` or `INACTIVE_DAYS` |
| `ExcludeUsers` | User principal names never to touch, separated by comma, semicolon or new line. Default empty. | (empty) | `ExcludeUsers` or `EXCLUDE_USERS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\remove-unused-m365-licenses.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Dry run: lists the disabled users whose licences it would remove.
```

```powershell
.\remove-unused-m365-licenses.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -ExcludeUsers "shared.archive@contoso.com" -DryRun false -Approve remove-unused-m365-licenses
Removes the licences of disabled users except one mailbox that needs its licence.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `TenantId`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `remove-unused-m365-licenses`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Removed licences from 6 disabled user(s)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\remove-unused-m365-licenses.log`.

## Changelog

- 1.0.0 2026-11-18 First version (untested).

## More

Full page: https://mspoutpost.com/scripts/remove-unused-m365-licenses

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
