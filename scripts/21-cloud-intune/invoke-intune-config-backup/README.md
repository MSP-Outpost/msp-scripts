# Back up the whole Intune configuration to JSON

> Exports the tenant's Intune policies (configuration, compliance, settings catalog, endpoint security, app protection, assignment filters) to JSON files.

| | |
|---|---|
| Script | `invoke-intune-config-backup.ps1` |
| Type | Action |
| Category | Cloud & Intune |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: DeviceManagementConfiguration.Read.All, DeviceManagementApps.Read.All; Intune |
| Changes | Writes JSON files and an index under OutputFolder; changes nothing in the tenant |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 10 minutes (longer for hundreds of policies) |
| Version | 1.0.0 |
| Updated | 2026-11-18 |

## What it does

THIS SCRIPT WRITES FILES ONLY. It changes nothing in the tenant: every Graph call is a read. It reads these Intune objects and writes each one to its own JSON file in a new time-stamped folder under OutputFolder, plus an index.json that lists every file:

DeviceConfigurations       device configuration profiles (BETA: v1.0 leaves out profile types it does not know, such as a Wi-Fi profile, without saying so) CompliancePolicies         device compliance policies (BETA, for the same reason) SettingsCatalog            settings catalog policies with their settings (BETA) EndpointSecurityIntents    endpoint security intents with their settings (BETA) AppProtectionPolicies      managed app policies and iOS app protection policies (v1.0) AssignmentFilters          assignment filters (BETA)

Each run makes a new folder, so older backups are kept (the script deletes nothing). If any category cannot be read (for example the app lacks the permission or the tenant lacks the feature) the run stops with an error before writing anything; name that category in SkipCategories to leave it out.

NOT EXPORTED, because the documentation pages read do not confirm a call for it: assignments (who each policy is assigned to), compliance scheduled actions, enrollment restrictions and status page, Win32/store app definitions, scripts and remediations, Autopilot profiles, and security baselines other than the endpoint security intents. This is a configuration backup for comparing and rebuilding, not a tested restore: there is no import.

SECRETS: the script removes any property whose name ends in secret, password, passphrase, preSharedKey or privateKey and writes the text [removed by MSP Outpost] in its place, and counts them in the output. Microsoft's pages do not say which properties hold secrets; Graph itself does not return the value of some. The files can still hold tenant details (names, group IDs, URLs): keep the folder as private as the tenant. With the default folder (under the MSP Outpost data folder) the runtime restricts access to administrators.

Graph application permissions (read only): DeviceManagementConfiguration.Read.All (configurations, compliance, settings catalog, intents, assignment filters) and DeviceManagementApps.Read.All (app protection policies).

Where each fact comes from (read in Microsoft's documentation): GET /deviceManagement/deviceConfigurations and /deviceCompliancePolicies (beta, DeviceManagementConfiguration.Read.All); GET /deviceManagement/configurationPolicies and its /settings (beta, same permission, or DeviceManagementEndpointSecurity.Read.All); GET /deviceManagement/intents and /intents/{id}/settings (beta); GET /deviceAppManagement/managedAppPolicies and /iosManagedAppProtections (v1.0, DeviceManagementApps.Read.All); GET /deviceManagement/assignmentFilters (beta, DeviceManagementConfiguration.Read.All). Not confirmed in Microsoft's documentation, so read defensively: that the list calls return every property of each object (the pages show only a sample; the script exports exactly what the list returns), that the managed app policies list includes Android and Windows protection policies, and which properties are secrets. The beta calls can change; Microsoft publishes the settings catalog, intents and assignment filters in beta only on the pages read.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The tenant ID (a GUID) or a domain such as contoso.onmicrosoft.com. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (with its private key) in LocalMachine\My or CurrentUser\My on this computer. Leave empty only if you use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `OutputFolder` | Folder that receives one new time-stamped sub-folder per run. Default: IntuneBackup under the MSP Outpost data folder (ProgramData\MSPOutpost\IntuneBackup). | (empty) | `OutputFolder` or `OUTPUT_FOLDER` |
| `SkipCategories` | Categories to leave out, separated by comma, semicolon or new line: DeviceConfigurations, CompliancePolicies, SettingsCatalog, EndpointSecurityIntents, AppProtectionPolicies, AssignmentFilters. Default empty (all). | (empty) | `SkipCategories` or `SKIP_CATEGORIES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\invoke-intune-config-backup.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Backs up everything into a new folder under ProgramData\MSPOutpost\IntuneBackup.
```

```powershell
.\invoke-intune-config-backup.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -OutputFolder D:\Backups\Intune -SkipCategories AssignmentFilters
Backs up to D:\Backups\Intune without the assignment filters.
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
Backed up 143 Intune object(s) in 6 categories (index.json lists every file); 2 secret field(s) removed
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\invoke-intune-config-backup.log`.

## Changelog

- 1.0.0 2026-11-18 First version.

## More

Full page: https://mspoutpost.com/scripts/invoke-intune-config-backup

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
