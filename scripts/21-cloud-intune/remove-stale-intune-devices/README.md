# Stale and duplicate Intune devices - delete the old records

> Deletes stale and duplicate device records from Intune (and, if you ask, from Entra ID), after saving each record to a file.

| | |
|---|---|
| Script | `remove-stale-intune-devices.ps1` |
| Type | Action |
| Category | Cloud & Intune |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: DeviceManagementManagedDevices.ReadWrite.All (Device.ReadWrite.All for Entra); Intune |
| Changes | Deletes the Intune records of stale and duplicate devices (and optionally their Entra ID devices); saves the records to a JSON file first |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | Under 5 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-18 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=remove-stale-intune-devices`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\remove-stale-intune-devices.log`.
- Run the dry run first and read the list.

## What it does

PARTLY TESTED: written from https://learn.microsoft.com/graph/api/intune-devices-manageddevice-delete (v1.0), intune-devices-manageddevice-list, https://learn.microsoft.com/graph/api/resources/intune-devices-manageddevice and https://learn.microsoft.com/graph/api/device-delete. Compared on 2026-11-20 with test-stale-intune-devices (tested): the shared runtime, the Graph sign-in and the device selection are identical; the DELETE managedDevices/{id} call was run by hand with the same app and worked; the read-back after deleting now retries 6 times, 5 seconds apart, as the tested scripts do. The delete step itself has not run (it needs a device 7 days unseen).

THIS SCRIPT DELETES THINGS AND CANNOT BE UNDONE. It lists every managed device in Intune with Microsoft Graph and selects:

- Stale devices: lastSyncDateTime older than StaleDays (or never synced), and
- Duplicates (RemoveDuplicates, default true): when several Intune records share one serial number, every record except the one with the newest sync. Blank and placeholder serial numbers (0, None, Default string, System Serial Number, To be filled by O.E.M.) never count.

It never selects a device named in ExcludeDevices, and never a record that synced in the last 7 days, whatever the other rules say. It stops without deleting anything when every device in the tenant looks stale (usually a sync outage, not a clean-up). For each selected device it deletes the INTUNE record only (DELETE managedDevices/{id}); it sends no wipe or retire command. The device's Microsoft Entra ID object is NOT touched unless IncludeEntraDevice is true; then, after the Intune record, it also deletes the Entra device (DELETE devices(deviceId='...')), but never one that a remaining Intune record still uses.

BEFORE-STATE FIRST: before the first deletion it writes the selected records (name, IDs, serial number, user, operating system, last sync, Entra device ID, reason) to a JSON file under the MSP Outpost data folder (...\MSPOutpost\before-state\remove-stale-intune-devices-<time>.json), and names the file in the output. Intune cannot restore a deleted record; a device that is still alive re-enrols and creates a new one.

High risk: it is a dry run until DryRun=false AND Approve=remove-stale-intune-devices, and MaxChanges (default 25, counting each Intune and each Entra deletion) caps one run. Run test-stale-intune-devices first to see the list.

Graph application permissions: DeviceManagementManagedDevices.ReadWrite.All (read and delete the Intune record); with IncludeEntraDevice also Device.ReadWrite.All.

Where each fact comes from (read in Microsoft's documentation, Graph v1.0): managedDevice delete: DELETE /deviceManagement/managedDevices/{managedDeviceId}, 204 No Content, DeviceManagementManagedDevices.ReadWrite.All (application); managedDevice list: GET /deviceManagement/managedDevices; managedDevice properties id, deviceName, serialNumber, userPrincipalName, operatingSystem, lastSyncDateTime, enrolledDateTime, azureADDeviceId; Entra device delete: DELETE /devices/{id} or /devices(deviceId='{deviceId}'), 204 No Content, Device.ReadWrite.All (application). Not confirmed in Microsoft's documentation, so read defensively: what lastSyncDateTime holds for a device that never synced (a missing value or a date before the year 2000 counts as never synced), and what else Intune does when a record is deleted (Microsoft's delete page describes no side effects; the script sends only the DELETE). The Entra deletion is not read back; the Intune deletions are, by listing the devices again.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The tenant ID (a GUID) or a domain such as contoso.onmicrosoft.com. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (with its private key) in LocalMachine\My or CurrentUser\My on this computer. Leave empty only if you use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `StaleDays` | Delete devices that have not synced for more than this many days. Whole number, 7 to 3650. Default 90. | `90` | `StaleDays` or `STALE_DAYS` |
| `RemoveDuplicates` | true (default) also deletes older records that share a serial number with a newer one. | `true` | `RemoveDuplicates` or `REMOVE_DUPLICATES` |
| `ExcludeDevices` | Device names never to delete, separated by comma, semicolon or new line (exact names). Default empty. | (empty) | `ExcludeDevices` or `EXCLUDE_DEVICES` |
| `IncludeEntraDevice` | true also deletes the matching Microsoft Entra ID device object. Default false (Intune record only). | `false` | `IncludeEntraDevice` or `INCLUDE_ENTRA_DEVICE` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\remove-stale-intune-devices.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Dry run: lists the Intune records it would delete.
```

```powershell
.\remove-stale-intune-devices.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -StaleDays 180 -DryRun false -Approve remove-stale-intune-devices
Deletes the Intune records of devices that have not synced for 180 days.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `TenantId`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `remove-stale-intune-devices`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Deleted 11 Intune device record(s) (3 of them duplicates); the records were saved to a before-state file first
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\remove-stale-intune-devices.log`.

## Changelog

- 1.0.0 2026-11-18 First version.

## More

Full page: https://mspoutpost.com/scripts/remove-stale-intune-devices

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
