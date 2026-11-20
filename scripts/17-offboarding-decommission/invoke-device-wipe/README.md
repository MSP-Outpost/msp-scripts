# Lost or returned laptop - remote wipe or retire in Intune

> Sends an Intune remote wipe (or retire) to one lost or returned device, found by name or ID.

| | |
|---|---|
| Script | `invoke-device-wipe.ps1` |
| Type | Action |
| Category | Offboarding & decommission |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: DeviceManagementManagedDevices.PrivilegedOperations.All and .Read.All; Intune |
| Changes | Queues an Intune Wipe (factory reset, all data erased) or Retire (company data removed) for one device |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.0 |
| Updated | 2026-11-18 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=invoke-device-wipe`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\invoke-device-wipe.log`.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS AND CANNOT BE UNDONE. It finds ONE device in Intune (by DeviceId, or by exact DeviceName) and queues a remote action for it with Microsoft Graph:

- Mode Wipe (default): POST managedDevices/{id}/wipe. The device is reset to factory state and ALL data on it is erased. KeepEnrollmentData and KeepUserData (both default false) keep the enrollment or the user data on a Windows device, as Microsoft describes them.
- Mode Retire: POST managedDevices/{id}/retire. Company data and company apps are removed and the device leaves Intune; the owner's personal data stays. This is the right action for a personal (BYOD) device.

It acts on one device only: a name that matches more than one device is refused and the matching IDs are listed so you can choose with DeviceId. A device that Intune marks as personally owned is refused for Wipe unless AllowPersonalWipe is true. It deletes nothing from Intune or Entra ID and does not disable the user's account.

Intune only QUEUES the action: the device receives it the next time it contacts Intune (a device that is off or offline acts later), and this script reports that the request was accepted, not that the device has wiped. Check the device's Wipe status in the Intune admin center. While a wipe or retire is still queued for the device, a second run ends OK with "Already requested" and sends nothing.

High risk: it is a dry run until DryRun=false AND Approve=invoke-device-wipe.

The Graph application permission is DeviceManagementManagedDevices.PrivilegedOperations.All (wipe and retire) and DeviceManagementManagedDevices.Read.All (to find the device).

Where each fact comes from (read in Microsoft's documentation): wipe action: POST /deviceManagement/managedDevices/{managedDeviceId}/wipe, body keepEnrollmentData, keepUserData (Boolean), also macOsUnlockCode, obliterationBehavior and persistEsimDataPlan (not used here), 204 No Content; retire action: POST .../retire, no body, 204; both need DeviceManagementManagedDevices.PrivilegedOperations.All (application); list managedDevices: GET /deviceManagement/managedDevices with DeviceManagementManagedDevices.Read.All; managedDevice properties id, deviceName, userPrincipalName, operatingSystem, serialNumber, managedDeviceOwnerType (company or personal), lastSyncDateTime. All calls are Graph v1.0. Not confirmed in Microsoft's documentation, so read defensively: the pending-action check reads deviceActionResults (actionName, actionState) and treats a wipe or retire in state pending or active as already requested; Microsoft's page shows the property and one state value (pending) but does not list the others. Tested: a queued wipe on a device that has not checked in reads actionName wipe, actionState pending from GET managedDevices/{id} (the list call does not show it). Whether $filter works on the managedDevices list is not documented, so the script lists every device and compares names itself.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The tenant ID (a GUID) or a domain such as contoso.onmicrosoft.com. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (with its private key) in LocalMachine\My or CurrentUser\My on this computer. Leave empty only if you use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `DeviceName` | The device's name in Intune (exact match, any case). Give DeviceName or DeviceId. | (empty) | `DeviceName` or `DEVICE_NAME` |
| `DeviceId` | The device's Intune managed device ID (a GUID). Give DeviceName or DeviceId. | (empty) | `DeviceId` or `DEVICE_ID` |
| `Mode` | Wipe (default) or Retire. | `Wipe` | `Mode` or `MODE` |
| `KeepEnrollmentData` | Wipe only. true keeps the enrollment state and the user account on a Windows device. Default false. | `false` | `KeepEnrollmentData` or `KEEP_ENROLLMENT_DATA` |
| `KeepUserData` | Wipe only. true keeps the user data on a Windows device. Default false. | `false` | `KeepUserData` or `KEEP_USER_DATA` |
| `AllowPersonalWipe` | true allows a full Wipe of a device Intune lists as personally owned. Default false (use Retire for those). | `false` | `AllowPersonalWipe` or `ALLOW_PERSONAL_WIPE` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\invoke-device-wipe.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -DeviceName LAPTOP-0042
Dry run: finds LAPTOP-0042 and says what it would wipe.
```

```powershell
.\invoke-device-wipe.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -DeviceName LAPTOP-0042 -DryRun false -Approve invoke-device-wipe
Queues a full wipe of LAPTOP-0042.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `TenantId`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `invoke-device-wipe`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Wipe requested for LAPTOP-0042 (Windows, a.chen@contoso.com); the device acts when it next checks in
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\invoke-device-wipe.log`.

## Changelog

- 1.0.0 2026-11-18 First version.

## More

Full page: https://mspoutpost.com/scripts/invoke-device-wipe

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
