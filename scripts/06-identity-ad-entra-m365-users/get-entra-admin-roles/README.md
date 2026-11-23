# Who holds admin roles in Microsoft 365

> Lists who holds Microsoft 365 / Entra admin roles, including PIM-eligible assignments, and counts the Global Administrators.

| | |
|---|---|
| Script | `get-entra-admin-roles.ps1` |
| Type | Report |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: RoleManagement.Read.Directory; Entra ID P2 for the eligible list |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## What it does

THIS SCRIPT IS READ-ONLY. It signs in as your app registration (certificate preferred, or the ClientSecret environment variable) and lists every Entra directory role assignment: the role, the member (user, app or group), whether the assignment is Active or Eligible (Privileged Identity Management), its scope and, for an eligible assignment, when it ends. It counts the Global Administrators (distinct users with the role active; apps and groups are listed but not counted) and warns when there are fewer than 2 or more than 4, the range Microsoft recommends. A Report cannot raise an alert: use test-new-admin-assignments to be told when someone is made an admin.

Eligible assignments need Microsoft Entra ID P2 (or Governance). When the tenant has no PIM, the eligible part is skipped with a warning and the active list is still reported. Members of a group that holds a role are not expanded; the group is listed as the member.

Permission (Microsoft Graph APPLICATION): RoleManagement.Read.Directory (role definitions, role assignments and eligibility schedule instances, with the member expanded).

Where each fact comes from (read in the Microsoft Graph v1.0 reference): GET /roleManagement/directory/roleAssignments with $expand=principal (properties id, principalId, roleDefinitionId, directoryScopeId; 200), GET /roleManagement/directory/roleEligibilityScheduleInstances (principalId, roleDefinitionId, directoryScopeId, memberType, startDateTime, endDateTime; $expand supported), GET /roleManagement/directory/roleDefinitions, and the Global Administrator role template ID 62e90394-69f5-4237-9190-012177145e10 (permissions reference). Not confirmed in the documentation, so read defensively: that $expand=principal on the eligibility instances returns the member (the page says $expand is supported without an example), which properties the expanded member carries (userPrincipalName, mail, displayName are tried in that order, then the principal ID), the exact error a tenant without P2 gives for the eligibility call (any failure there is a warning, not an error), and whether RoleManagement.Read.Directory alone is enough to expand a user (if the expanded member comes back empty the script shows the principal ID and the run still succeeds).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The Application (client) ID of the app registration that holds the Graph permissions. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (private key in LocalMachine\My or CurrentUser\My). Preferred. When empty, the app secret is read from the environment variable ClientSecret (a secure/hidden RMM field; never an argument). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `IncludeEligible` | true (default) to also list PIM-eligible assignments. false to list active assignments only. | `true` | `IncludeEligible` or `INCLUDE_ELIGIBLE` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-entra-admin-roles.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Lists every admin role assignment and counts the Global Administrators.
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
9 admin role assignment(s) in 5 role(s); 3 Global Administrator(s) (2 to 4 is recommended); 2 eligible
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Role`, `Member`, `MemberType`, `Assignment`, `Scope`, `EndUtc`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/get-entra-admin-roles

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
