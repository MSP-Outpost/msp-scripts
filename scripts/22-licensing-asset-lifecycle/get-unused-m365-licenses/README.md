# Paying for unused Microsoft 365 licences

> Lists Microsoft 365 licences paid for but not used: assigned to disabled or inactive users, and bought but unassigned.

| | |
|---|---|
| Script | `get-unused-m365-licenses.ps1` |
| Type | Report |
| Category | Licensing & asset lifecycle |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: User.Read.All, LicenseAssignment.Read.All, AuditLog.Read.All; Entra ID P1 or P2 |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 3 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-18 |

## What it does

THIS SCRIPT IS READ-ONLY. It signs in to ONE client tenant as an app registration (TenantId, ClientId and a certificate, or a ClientSecret in the environment) and writes one row per finding:

- Disabled: a user whose account is disabled (sign-in blocked) and who still holds licences.
- Inactive: an enabled user who holds licences and last signed in InactiveDays or more ago.
- NeverSignedIn: an enabled user who holds licences, was created at least InactiveDays ago and has no recorded sign-in (Microsoft does not return sign-ins before April 2020).
- UnassignedSeats: for each licence SKU, the seats bought minus the seats assigned. Each user row names the licences, marking those assigned through a group (they cannot be removed from the user directly). Users in ExcludeUsers are skipped. Licensed shared mailboxes, mailboxes over 50 GB and mailboxes on hold are disabled accounts that may NEED their licence: check each Disabled row before reclaiming it. Free and trial SKUs can show very large unassigned counts. SIGN-IN ACTIVITY NEEDS A LICENCE AND A PERMISSION: Microsoft returns signInActivity only for tenants with Microsoft Entra ID P1 or P2, and only to an app with AuditLog.Read.All. Without them the run ends in ERROR and says so; set InactiveDays=0 to skip the inactivity check and report disabled users and unassigned seats only.

Microsoft Graph application permissions (admin consent): User.Read.All, LicenseAssignment.Read.All, and AuditLog.Read.All (only when InactiveDays is above 0).

Where each fact comes from (read in Microsoft's reference): GET v1.0/users with $select of accountEnabled, assignedLicenses, licenseAssignmentStates (assignedByGroup is null for a direct assignment), createdDateTime and signInActivity (lastSignInDateTime, lastSuccessfulSignInDateTime, lastNonInteractiveSignInDateTime; page size 500 when signInActivity is selected; P1 or P2 and AuditLog.Read.All required; not returned for a user who never signed in or last signed in before April 2020); GET v1.0/subscribedSkus (skuId, skuPartNumber, consumedUnits, prepaidUnits.enabled, capabilityStatus, appliesTo). Not confirmed in the documentation, so read defensively: the exact error Graph returns without P1 (any failure of the signInActivity read is reported with the service's own text); whether appliesTo is always present on a SKU (a SKU without it is counted as a user SKU).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint (40 hex characters) of the app's certificate with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. When empty, the secret is read from the environment variable ClientSecret (a secure RMM field). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `InactiveDays` | An enabled user counts as inactive after this many days without a sign-in. Whole number, 0 to 3650. 0 skips the inactivity check (disabled users and unassigned seats only, no P1 needed). Default 90. | `90` | `InactiveDays` or `INACTIVE_DAYS` |
| `ExcludeUsers` | User principal names to skip, separated by comma, semicolon or new line. Default empty. | (empty) | `ExcludeUsers` or `EXCLUDE_USERS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-unused-m365-licenses.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Lists licences on disabled users, on users silent for 90 days, and unassigned seats.
```

```powershell
.\get-unused-m365-licenses.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -InactiveDays 0 -ExportPath C:\Temp\licences.csv
Without the sign-in check (no Entra ID P1 needed) and saved to a file.
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
Licences: 4 disabled and 7 inactive users hold licences; 12 unassigned seats in 3 SKUs
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Kind`, `Item`, `Licences`, `LastSignInUtc`, `DaysInactive`, `Detail`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-18 First version (untested).

## More

Full page: https://mspoutpost.com/scripts/get-unused-m365-licenses

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
