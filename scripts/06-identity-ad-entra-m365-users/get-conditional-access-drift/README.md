# Conditional Access drifted from our baseline

> Compares a tenant's Conditional Access policies with your baseline file, or saves them as the baseline.

| | |
|---|---|
| Script | `get-conditional-access-drift.ps1` |
| Type | Report |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: Policy.Read.All; Entra ID P1 |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## What it does

THIS SCRIPT IS READ-ONLY toward the tenant. It signs in as your app registration (certificate preferred, or the ClientSecret environment variable) and reads every Conditional Access policy.

With BaselinePath (a JSON file this script wrote earlier, or one you edited): it compares policy by policy, matching on the policy display name, and writes one row per difference: Missing (in the baseline, not in the tenant), Extra (in the tenant, not in the baseline), StateChanged (enabled, disabled or report-only differs) and Changed (conditions, grant controls or session controls differ). Policies that match are not listed. Without BaselinePath: it saves the tenant's current policies as a baseline file under %ProgramData%\MSPOutpost\Baselines (the answer and a line of output name the file) and lists every policy as Exported. That is the only thing it writes, and it writes it on this computer, not in the tenant.

The comparison ignores policy IDs and the created and modified dates, ignores empty values and the order of list values, and matches names exactly. IDs of users, groups, roles and named locations inside a policy are specific to one tenant, so a baseline taken from ANOTHER tenant reports every policy that names a group or user as Changed. Use a baseline taken from the same tenant when it was in the state you want, and keep one baseline file per tenant.

Permission (Microsoft Graph APPLICATION): Policy.Read.All. Conditional Access needs Entra ID P1.

Where each fact comes from (read in the Microsoft Graph v1.0 reference): GET /identity/conditionalAccess/policies (properties id, displayName, state, createdDateTime, modifiedDateTime, conditions, grantControls, sessionControls; Policy.Read.All). Not confirmed in the documentation, so read defensively: the state values other than "enabled" are taken from the conditionalAccessPolicyState type (enabled, disabled, enabledForReportingButNotEnforced), which this script only compares as text, so a new value would simply show as a difference.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The Application (client) ID of the app registration that holds the Graph permissions. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (private key in LocalMachine\My or CurrentUser\My). Preferred. When empty, the app secret is read from the environment variable ClientSecret (a secure/hidden RMM field; never an argument). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `BaselinePath` | Path of the baseline JSON file to compare with. Empty (default) means: export the current policies as a baseline. | (empty) | `BaselinePath` or `BASELINE_PATH` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-conditional-access-drift.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
No baseline given: saves the tenant's policies as a baseline file and says where.
```

```powershell
.\get-conditional-access-drift.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -BaselinePath C:\Outpost\contoso-ca-baseline.json
Lists every policy that is missing, extra, in another state or changed.
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
Conditional Access: 14 policies; 3 differ from the baseline (1 missing, 1 extra, 1 changed)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Policy`, `Difference`, `Baseline`, `Tenant`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-18 First version.

## More

Full page: https://mspoutpost.com/scripts/get-conditional-access-drift

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
