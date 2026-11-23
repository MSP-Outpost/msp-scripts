# Compromised M365 account - contain it in order

> Contains a compromised Microsoft 365 account in the right order: block sign-in, revoke sessions, then the extras you ask for.

| | |
|---|---|
| Script | `invoke-compromised-account-containment.ps1` |
| Type | Action |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph user, session and auth method permissions (see the script); Exchange app access |
| Changes | Blocks the account's sign-in; revokes its sessions; optionally sets a new random password, deletes its MFA methods, disables its forwarding inbox rules |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | Under 2 minutes |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=invoke-compromised-account-containment`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\invoke-compromised-account-containment.log`.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. For the one account in UserPrincipalName it does these steps, always in this order, because the order is the point:

1. BLOCKS SIGN-IN (accountEnabled = false), so the attacker cannot get a new token or start a new session.
2. REVOKES SESSIONS (revokeSignInSessions), so every refresh token and browser session issued before now stops working. This comes after the block: revoking first would let the attacker sign straight back in. Revoked tokens can keep working for a few minutes (Microsoft's note).
3. Only if ResetPassword is true: sets a NEW RANDOM PASSWORD (24 characters, change required at next sign-in). The password is generated here, written to the secure RMM custom field named in ResultField BEFORE it is set, and never printed, logged or returned. The field must be a secure (secret) field of NinjaOne, Datto RMM (UDF number) or Syncro: the run refuses to start without one.
4. Only if RemoveMfaMethods is true: DELETES the account's phone, authenticator app, software token, FIDO2 key, Windows Hello for Business, email and temporary access pass methods (not the password), because an attacker may have registered their own. The user must register again after you unblock the account.
5. Only if DisableForwardingRules is true: DISABLES every inbox rule that forwards, redirects or forwards as attachment to someone else (Exchange Online PowerShell, Disable-InboxRule). It disables the rules and does not delete them, so you can read them; the rule definitions are saved in the before-state file. It never deletes the account, its mailbox or its data, never unblocks the account (do that when you have cleaned up, by setting accountEnabled to true), never touches mailbox-level forwarding (it only warns when the mailbox has ForwardingAddress or ForwardingSmtpAddress set) and never touches any other account.

HIGH RISK: it is a dry run (lists the steps, changes nothing) unless DryRun=false AND Approve=invoke-compromised-account-containment. Before the first change it writes the before-state (account state, authentication method IDs and types, inbox rule definitions; no secrets) as JSON under %ProgramData%\MSPOutpost\Backups\invoke-compromised-account-containment\ and prints the file name. Run it again and it blocks and revokes again (revoking is repeatable, so a second run reports CHANGED, not "already done"); steps 3 to 5 apply only to what is still there.

Permissions (Microsoft Graph APPLICATION): User.Read.All and User.EnableDisableAccount.All (step 1), User.RevokeSessions.All (step 2), User-PasswordProfile.ReadWrite.All (step 3), UserAuthenticationMethod.ReadWrite.All (step 4). Step 5 needs the Exchange Online module ExchangeOnlineManagement 3.1 or later, the app permission Exchange.ManageAsApp and an Exchange role that allows Get-InboxRule and Disable-InboxRule on mailboxes (an Entra role of Exchange Administrator assigned to the app's service principal is the usual way). If the module is missing and DisableForwardingRules is true, the run stops before any change.

Where each fact comes from (read in the Microsoft Graph v1.0 reference and the Exchange cmdlet reference): PATCH /users/{id} (accountEnabled needs User.EnableDisableAccount.All plus User.Read.All; passwordProfile needs User-PasswordProfile.ReadWrite.All, always set forceChangePasswordNextSignIn), POST /users/{id}/revokeSignInSessions (User.RevokeSessions.All, 200 with value true; not for external users), GET /users/{id}/authentication/methods (UserAuthenticationMethod.Read.All; ReadWrite.All to delete), the authentication methods overview (which method types can be deleted), Get-InboxRule (-Mailbox, -IncludeHidden) and Disable-InboxRule (-Identity, -Mailbox, -Force, -Confirm:$false; it removes the user's Outlook client-side rules). Not confirmed in the documentation, so read defensively: (a) the per-type delete paths used for step 4 (microsoftAuthenticatorMethods, phoneMethods, softwareOathMethods, fido2Methods, windowsHelloForBusinessMethods, emailMethods, temporaryAccessPassMethods under /users/{id}/authentication) follow the documented pattern but each page was not read; a method that fails to delete stops the run with an error that names it (the earlier steps stay done); (b) whether an app-only token may reset the password or delete methods of an ADMIN account (Microsoft ties this to a directory role, so give the app's service principal the Privileged Authentication Administrator role when the account may be an admin); (c) the Get-InboxRule property names ForwardTo, ForwardAsAttachmentTo, RedirectTo (they are the rule's action parameters; the cmdlet page does not list its output properties), read with PSObject.Properties; (d) Get-Mailbox ForwardingAddress and ForwardingSmtpAddress for the warning.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The Application (client) ID of the app registration that holds the Graph permissions. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (private key in LocalMachine\My or CurrentUser\My). Preferred. When empty, the app secret is read from the environment variable ClientSecret (a secure/hidden RMM field; never an argument). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `UserPrincipalName` | The compromised user's sign-in name, for example ann@contoso.com. Required. | (empty) | `UserPrincipalName` or `USER_PRINCIPAL_NAME` |
| `ResetPassword` | true to also set a new random password (needs a secure ResultField). Default false. | `false` | `ResetPassword` or `RESET_PASSWORD` |
| `RemoveMfaMethods` | true to also delete the account's registered MFA and passwordless methods. Default false. | `false` | `RemoveMfaMethods` or `REMOVE_MFA_METHODS` |
| `DisableForwardingRules` | true to also disable the mailbox's forwarding and redirect inbox rules (Exchange Online). Default false. | `false` | `DisableForwardingRules` or `DISABLE_FORWARDING_RULES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\invoke-compromised-account-containment.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -UserPrincipalName ann@contoso.com
Dry run: lists the block and revoke steps for Ann.
```

```powershell
.\invoke-compromised-account-containment.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -UserPrincipalName ann@contoso.com -DisableForwardingRules true -RemoveMfaMethods true -DryRun false -Approve invoke-compromised-account-containment
Blocks, revokes, removes the MFA methods and disables forwarding rules.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `TenantId`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `invoke-compromised-account-containment`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
ann@contoso.com contained: sign-in blocked, sessions revoked, 3 MFA method(s) removed, 1 forwarding rule(s) disabled
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\invoke-compromised-account-containment.log`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-18 First version.

## More

Full page: https://mspoutpost.com/scripts/invoke-compromised-account-containment

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
