# Stale or duplicate devices in Intune

> Alerts when Intune holds devices that have not synced for StaleDays or that are duplicates of a newer record with the same serial number.

| | |
|---|---|
| Script | `test-stale-intune-devices.ps1` |
| Type | Monitor |
| Category | Cloud & Intune |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: DeviceManagementManagedDevices.Read.All; an Intune license |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 2 minutes (longer for tens of thousands of devices) |
| Version | 1.0.0 |
| Updated | 2026-11-18 |

## What it does

THIS SCRIPT IS READ-ONLY. It lists every managed device in the tenant's Intune with Microsoft Graph and writes one row per device that is either:

- Stale: its lastSyncDateTime is older than StaleDays (or it has never synced), or
- Duplicate: another Intune record has the same serial number and a more recent sync. The newest record of each serial number is the one kept; every older one is listed. Blank and placeholder serial numbers (0, None, Default string, System Serial Number, To be filled by O.E.M.) are never treated as duplicates.

It alerts (exit 1) when it lists anything and is OK otherwise. Devices named in ExcludeDevices (exact names) are never listed. The companion script remove-stale-intune-devices removes what this one lists.

Run it from any computer that holds the app's certificate. Graph application permission: DeviceManagementManagedDevices.Read.All.

Where each fact comes from (read in Microsoft's documentation, Graph v1.0): managedDevice list: GET /deviceManagement/managedDevices with DeviceManagementManagedDevices.Read.All (application); managedDevice properties id, deviceName, serialNumber, userPrincipalName, operatingSystem, lastSyncDateTime ("the date and time that the device last completed a successful sync with Intune"), enrolledDateTime, azureADDeviceId. Not confirmed in Microsoft's documentation, so read defensively: what lastSyncDateTime holds for a device that never synced (the script treats a missing value or a date before the year 2000 as never synced), and whether $filter works on lastSyncDateTime for the list (the resource page says it supports lt and gt, but the script lists every device and compares dates itself). A large tenant makes the listing slow (Graph returns pages; the script follows them all).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The tenant ID (a GUID) or a domain such as contoso.onmicrosoft.com. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (with its private key) in LocalMachine\My or CurrentUser\My on this computer. Leave empty only if you use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `StaleDays` | A device is stale when it has not synced for more than this many days. Whole number, 1 to 3650. Default 30. | `30` | `StaleDays` or `STALE_DAYS` |
| `CheckDuplicates` | true (default) also lists older records that share a serial number with a newer one. | `true` | `CheckDuplicates` or `CHECK_DUPLICATES` |
| `ExcludeDevices` | Device names never to list, separated by comma, semicolon or new line (exact names). Default empty. | (empty) | `ExcludeDevices` or `EXCLUDE_DEVICES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-stale-intune-devices.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Lists devices with no sync for 30 days and older duplicate records.
```

```powershell
.\test-stale-intune-devices.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -StaleDays 90 -CheckDuplicates false -OutputFormat Json
Only devices idle for 90 days, as one JSON object.
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
Intune: 14 stale device(s) (no sync in 30+ days) and 3 older duplicate(s) among 412 devices
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Device`, `DeviceId`, `Serial`, `User`, `OperatingSystem`, `LastSyncUtc`, `DaysSinceSync`, `Issue`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-18 First version (untested).

## More

Full page: https://mspoutpost.com/scripts/test-stale-intune-devices

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
