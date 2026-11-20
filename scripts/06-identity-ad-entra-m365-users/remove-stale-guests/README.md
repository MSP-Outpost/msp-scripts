# Remove stale guest accounts

> Disables or deletes guest accounts in a Microsoft 365 tenant that have not signed in for 90 days or never accepted their invitation.

| | |
|---|---|
| Script | `remove-stale-guests.ps1` |
| Type | Action |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: User.Read.All, AuditLog.Read.All, User.EnableDisableAccount.All or User.ReadWrite.All |
| Changes | Disables, or deletes, guest accounts that are idle or never redeemed |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | Under 2 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=remove-stale-guests`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\remove-stale-guests.log`.
- Run the dry run first and read the list.

## What it does

PARTLY TESTED: written from https://learn.microsoft.com/en-us/graph/api/user-list, https://learn.microsoft.com/en-us/graph/api/resources/user, https://learn.microsoft.com/en-us/graph/api/resources/signinactivity, https://learn.microsoft.com/en-us/graph/api/user-delete and https://learn.microsoft.com/en-us/graph/api/user-update (Microsoft Graph v1.0). Compared on 2026-11-20 with invoke-compromised-account-containment and disable-shared-mailbox-sign-in (tested): the same disable call, 404 handling and read-back loop. Run against the test tenant: both modes found the guest and ended Already clean; no guest was old enough to disable or delete.

THIS SCRIPT CHANGES THINGS. It finds the stale guests that get-stale-guests lists (guest accounts whose invitation is older than StaleDays and unaccepted, or whose newest sign-in is older than StaleDays) and, depending on Mode:

- Disable (the default): sets accountEnabled to false. The guest cannot sign in; nothing is lost, and setting accountEnabled back to true restores access. Guests that are already disabled are left alone, so a second run changes nothing.
- Delete: DELETES the guest account (enabled or already disabled). Microsoft moves a deleted user, with licenses and group memberships, to a recycle bin where it can be restored within 30 days; after that it is gone for good. Use it after a Disable run has sat for a while with nobody complaining. It never touches a member account, never touches a guest in ExcludeGuests (sign-in name or mail address), never changes group memberships, shared files or the guest's own tenant, and never acts on the account it signs in as (that is an app, not a guest). A guest the app is not allowed to change (one holding an admin role) stops the run with an error naming it; the earlier changes stay.

HIGH RISK: it is a dry run (lists every guest it would change, changes nothing) unless DryRun=false AND Approve=remove-stale-guests, and it refuses to change more than MaxChanges (default 25) guests in one run. Before the first change it writes the guests to be changed (ID, sign-in name, mail, state, last sign-in; no secrets) as JSON under %ProgramData%\MSPOutpost\Backups\remove-stale-guests\ and prints the file name; it is the list to restore from.

Sign-in activity needs Microsoft Entra ID P1 and the AuditLog.Read.All permission. Without them the script warns and acts only on guests whose invitation was never accepted.

Permission (Microsoft Graph APPLICATION): User.Read.All and AuditLog.Read.All (find the guests), User.EnableDisableAccount.All (Mode Disable) and User.ReadWrite.All (Mode Delete). Microsoft says User.ReadWrite.All is not enough to delete a user who holds a privileged admin role.

Where each fact comes from (read in the Microsoft Graph v1.0 reference): GET /users with $filter userType eq 'Guest' and $select of createdDateTime, externalUserState, externalUserStateChangeDateTime, signInActivity; DELETE /users/{id} (User.ReadWrite.All; 204; restorable for 30 days); PATCH /users/{id} (accountEnabled needs User.EnableDisableAccount.All and User.Read.All, as used by invoke-compromised-account-containment). Not confirmed in the documentation, so read defensively: that $select=signInActivity combines with $filter=userType eq 'Guest' (if Graph refuses, the script warns and judges only unaccepted invitations), that externalUserState is filled for guests invited another way than the invitation API, and that a deleted user disappears from GET /users/{id} within about 30 seconds (the check reads up to 6 times, 5 seconds apart; a 404 means deleted).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The Application (client) ID of the app registration that holds the Graph permissions. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (private key in LocalMachine\My or CurrentUser\My). Preferred. When empty, the app secret is read from the environment variable ClientSecret (a secure/hidden RMM field; never an argument). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `StaleDays` | A guest with no sign-in, or an unaccepted invitation, for this many days is stale. Whole number, 30 to 3650. Default 90. | `90` | `StaleDays` or `STALE_DAYS` |
| `Mode` | Disable (default) blocks the guests' sign-in; Delete removes the accounts (restorable for 30 days). | `Disable` | `Mode` or `MODE` |
| `ExcludeGuests` | Guests to leave alone, by sign-in name or mail address, separated by comma, semicolon or new line. Default empty. | (empty) | `ExcludeGuests` or `EXCLUDE_GUESTS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\remove-stale-guests.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Dry run: lists the guests it would disable.
```

```powershell
.\remove-stale-guests.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -Mode Delete -ExcludeGuests "auditor@fabrikam.com" -DryRun false -Approve remove-stale-guests
Deletes every stale guest except the auditor.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `TenantId`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `remove-stale-guests`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Disabled 8 stale guest(s) (idle or never redeemed for 90 days)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\remove-stale-guests.log`.

## Changelog

- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/remove-stale-guests

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
