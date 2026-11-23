# Entra Connect stopped syncing

> Alerts when Entra Connect or Cloud Sync has not synced the on-premises directory to Microsoft 365 for hours.

| | |
|---|---|
| Script | `test-entra-connect-sync.ps1` |
| Type | Monitor |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; app registration with Microsoft Graph application permission Organization.Read.All, admin-consented |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 10 seconds |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## What it does

THIS SCRIPT IS READ-ONLY. It signs in as your app registration (certificate preferred, or the ClientSecret environment variable) and reads the tenant's organization record from Microsoft Graph: whether the tenant is synced from an on-premises directory and when it was last synced. It needs no access to the sync server: this is the view from the cloud (the ADSync module on the server is another script, invoke-entra-delta-sync).

- onPremisesSyncEnabled null: the tenant has never been synced, so the script is SKIPPED.
- onPremisesSyncEnabled false: the tenant was synced once and is no longer, so it ALERTS.
- onPremisesSyncEnabled true: it ALERTS when onPremisesLastSyncDateTime is empty or older than MaxAgeHours. Password hash sync time and sync error counts are not in this Microsoft Graph record, so they are not checked.

Permission (Microsoft Graph APPLICATION): Organization.Read.All. (With only User.Read the page says these properties come back null, which would look like "never synced": grant Organization.Read.All.)

Where each fact comes from (read in the Microsoft Graph v1.0 reference): GET /organization with $select (properties id, displayName, onPremisesLastSyncDateTime, onPremisesSyncEnabled; Organization.Read.All is the least privileged application permission). Not confirmed in the documentation, so read defensively: that onPremisesLastSyncDateTime is updated by Entra Cloud Sync as well as Entra Connect (the page says only "last synced with the on-premises directory"), and how quickly the value moves after a sync.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The Application (client) ID of the app registration that holds the Graph permissions. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (private key in LocalMachine\My or CurrentUser\My). Preferred. When empty, the app secret is read from the environment variable ClientSecret (a secure/hidden RMM field; never an argument). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `MaxAgeHours` | Alert when the last sync is older than this many hours. Whole number, 1 to 720. Default 3. | `3` | `MaxAgeHours` or `MAX_AGE_HOURS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-entra-connect-sync.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Alerts when the tenant has not synced for more than three hours.
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
Directory sync: last sync 5 h ago (2026-11-18T09:12:00Z); limit 3 h
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Tenant`, `SyncEnabled`, `LastSyncUtc`, `AgeHours`, `Status`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-18 First version.

## More

Full page: https://mspoutpost.com/scripts/test-entra-connect-sync

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
