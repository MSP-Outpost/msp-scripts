# User lost their phone - reset MFA methods

> Resets a Microsoft 365 user's MFA methods (phone, authenticator app, OATH token, security key) so they register again, for a lost phone.

| | |
|---|---|
| Script | `reset-user-mfa-methods.ps1` |
| Type | Action |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: User.Read.All, UserAuthenticationMethod.ReadWrite.All, User.RevokeSessions.All |
| Changes | Deletes the user's phone, Microsoft Authenticator, software OATH and FIDO2 authentication methods; optionally revokes their sign-in sessions |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=reset-user-mfa-methods`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\reset-user-mfa-methods.log`.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. For the one account in UserPrincipalName it DELETES these registered authentication methods:

- phone numbers (mobile, alternate mobile and office; used for SMS and voice calls),
- the Microsoft Authenticator app registrations,
- software OATH token registrations (other authenticator apps),
- FIDO2 security keys. The user then has to register again the next time they sign in where MFA is required (Microsoft's "require re-register multifactor authentication" procedure: delete each method; with none left the user is prompted). It NEVER deletes the password method, a Windows Hello for Business credential (bound to a device, not to the lost phone), the email method (used for password reset) or a Temporary Access Pass (the admin may have just issued one so the user can register again), and never touches any other account. If RevokeSessions is true it also revokes the user's sign-in sessions and refresh tokens (the user is signed out everywhere), but only in a run that removes methods, so a second run changes nothing. A method that cannot be deleted stops the run with an error naming it (methods already deleted stay deleted; run it again). Microsoft says a phone number cannot be deleted while it is the user's default MFA method, and that a mobile number cannot be deleted while an alternate mobile number remains (the script deletes alternate and office numbers first); ask the user to change the default method first, or delete the method in the Entra admin center.

HIGH RISK: it is a dry run (lists every method it would delete, changes nothing) unless DryRun=false AND Approve=reset-user-mfa-methods, and it refuses to delete more than MaxChanges (default 25) in one run. Before the first deletion it writes the method IDs and types (no phone numbers, no secrets) as JSON under %ProgramData%\MSPOutpost\Backups\reset-user-mfa-methods\ and prints the file name; a deleted method cannot be restored, the user registers a new one.

Permission (Microsoft Graph APPLICATION): User.Read.All (find the user), UserAuthenticationMethod.ReadWrite.All (list and delete methods) and, only when RevokeSessions is true, User.RevokeSessions.All. For a user who holds an admin role, Microsoft ties changing credentials to a directory role: give the app's service principal the Privileged Authentication Administrator role, or the run stops with a 403 naming the method.

Where each fact comes from (read in the Microsoft Graph v1.0 reference): GET /users/{id}/authentication/methods (UserAuthenticationMethod.Read.All; @odata.type per method), DELETE /users/{id}/authentication/phoneMethods/{id} (ReadWrite.All; ids 3179e48a-750b-4051-897c-87b9720928f7 mobile, b6332ec1-7057-4abe-9331-3d72feddfe41 alternateMobile, e37fc753-ff3b-4958-9484-eaa9425c82bc office; 204), DELETE .../microsoftAuthenticatorMethods/{id} (204), DELETE .../softwareOathMethods/{id} (204), and the overview page's list of method types and its re-register procedure. Not confirmed in the documentation, so read defensively: the delete path for FIDO2 keys (fido2Methods, the documented pattern; its page was not read), that the id of a phone entry in the methods list equals the phoneMethods id above (it is used only to order the deletions), whether an app-only token can delete a phone number that is the default MFA method, and that the user's methods list is updated within about 30 seconds (the check after the deletion reads up to 6 times, 5 seconds apart).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The Application (client) ID of the app registration that holds the Graph permissions. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (private key in LocalMachine\My or CurrentUser\My). Preferred. When empty, the app secret is read from the environment variable ClientSecret (a secure/hidden RMM field; never an argument). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `UserPrincipalName` | The user's sign-in name, for example ann@contoso.com. Required. | (empty) | `UserPrincipalName` or `USER_PRINCIPAL_NAME` |
| `RevokeSessions` | true to also revoke the user's sign-in sessions and refresh tokens in the same run. Default false. | `false` | `RevokeSessions` or `REVOKE_SESSIONS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\reset-user-mfa-methods.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -UserPrincipalName ann@contoso.com
Dry run: lists the MFA methods Ann has registered.
```

```powershell
.\reset-user-mfa-methods.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -UserPrincipalName ann@contoso.com -RevokeSessions true -DryRun false -Approve reset-user-mfa-methods
Deletes Ann's phone, authenticator and security key methods and signs her out everywhere.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `TenantId`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `reset-user-mfa-methods`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Removed 3 MFA method(s) from ann@contoso.com; sessions revoked; she registers again at next sign-in
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\reset-user-mfa-methods.log`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/reset-user-mfa-methods

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
