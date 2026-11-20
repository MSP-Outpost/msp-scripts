# Directory sync errors and duplicate UPN or proxy address

> Lists the users, groups and contacts that have directory sync errors in Microsoft 365, with duplicate UPN and proxy address conflicts and the object they clash with.

| | |
|---|---|
| Script | `get-directory-sync-errors.ps1` |
| Type | Report |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: User.Read.All, Group.Read.All, OrgContact.Read.All |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 5 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## What it does

PARTLY TESTED: written from https://learn.microsoft.com/en-us/graph/api/resources/onpremisesprovisioningerror, https://learn.microsoft.com/en-us/graph/api/resources/serviceprovisioningerror, https://learn.microsoft.com/en-us/graph/api/resources/user, group and orgcontact (Microsoft Graph v1.0) and https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/how-to-connect-syncservice-duplicate-attribute-resiliency. Run on 2026-11-20 against the synced test tenant: the lists return both error properties for users, groups and contacts, and the conflict lookups were run against real objects (a bug fixed: Graph refuses "or" inside any(), so every proxy address lookup had failed). Entra never published an error, so the error rows themselves are unproven.

THIS SCRIPT IS READ-ONLY. It signs in as your app registration (certificate preferred, or the ClientSecret environment variable) and reads every user, group and organizational contact in the tenant with two properties:

- onPremisesProvisioningErrors: errors from Microsoft Entra Connect or Cloud Sync. Microsoft documents one category, PropertyConflict (a value that must be unique is already used by another object), for the properties UserPrincipalName and ProxyAddress, with the conflicting value and the time;
- serviceProvisioningErrors: unresolved errors published by a service such as Exchange for the object (resolved ones are left out). For each UPN or proxy address conflict it also looks up which other user, group or contact holds that value (users by userPrincipalName; users, groups and contacts by proxyAddresses) and lists them in ConflictsWith, so you can see the pair to fix. A conflict lookup that fails is shown as "lookup failed" and does not stop the run. The lookups are capped at 100 distinct values; more are shown as "not looked up". With duplicate attribute resiliency (on by default in Microsoft's description) Entra ID does not fail the object: it keeps the object with a temporary UPN or without the proxy address and records the quarantined value in the error. The row therefore shows the object that LOST the value; ConflictsWith shows who holds it. The answer counts the objects and errors. Fixing is a change in Active Directory (or the conflicting cloud object) and is not done here.

Microsoft Graph application permissions (admin consent): User.Read.All, Group.Read.All and OrgContact.Read.All.

Where each fact comes from (read in the Microsoft Graph v1.0 reference): GET /users, /groups and /contacts with $select of onPremisesProvisioningErrors and serviceProvisioningErrors (on the user page onPremisesProvisioningErrors "requires $select"); the onPremisesProvisioningError properties category, occurredDateTime, propertyCausingError, value; the serviceProvisioningError properties createdDateTime, isResolved, serviceInstance; $filter on userPrincipalName (eq) and on proxyAddresses with the any operator (eq, endsWith, startsWith), which needs the advanced query headers (ConsistencyLevel eventual and $count=true). Not confirmed in the documentation, so read defensively: whether the list endpoints return serviceProvisioningErrors with $select for contacts (the script retries without it when the call is refused); whether the value of a ProxyAddress error carries the "SMTP:" or "smtp:" prefix (a value without a prefix is looked up as smtp:; Graph compares proxy addresses without regard to case); whether a list can omit an error property that a single GET returns; the property errorDetail of the service error subtype serviceProvisioningXmlError (shown when present); how long Entra takes to show a fixed object as clean.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint (40 hex characters) of the app's certificate with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. When empty, the secret is read from the environment variable ClientSecret (a secure RMM field). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-directory-sync-errors.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Lists every object with a sync error and the object it conflicts with.
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
Directory sync errors: 5 object(s) with 6 error(s): 4 sync (UPN or proxy address conflicts), 2 service
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `ObjectType`, `Name`, `Identifier`, `ObjectId`, `ErrorType`, `Property`, `Value`, `OccurredUtc`, `ConflictsWith`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/get-directory-sync-errors

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
