# Autopilot hash not registered - upload this PC's hardware hash

> Reads this PC's Windows Autopilot hardware hash and uploads it to the tenant's Autopilot devices, with an optional group tag.

| | |
|---|---|
| Script | `invoke-autopilot-hash-upload.ps1` |
| Type | Action |
| Category | Onboarding & provisioning |
| Platforms | Windows 10 1703+ or 11 (the PC being registered) |
| Runs as | Either |
| Requires | PowerShell 5.1; admin rights; Graph: DeviceManagementServiceConfig.ReadWrite.All; Intune and Entra ID P1 |
| Changes | Adds this PC's hardware hash to the tenant's Windows Autopilot devices (and a group tag when set) |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 12 minutes (most of it waiting for Microsoft's import) |
| Version | 1.0.0 |
| Updated | 2026-11-18 |

## What it does

THIS SCRIPT CHANGES THINGS. It runs ON the PC being registered (as SYSTEM or an administrator), not from a management server. It:

- reads the hardware hash from the PC's MDM WMI bridge (class MDM_DevDetail_Ext01 in root/cimv2/mdm/dmmap, property DeviceHardwareData) and the serial number from the BIOS,
- checks whether the tenant already holds a device with that serial number (an Autopilot device, or an import that is still running),
- uploads the hash to the tenant's Autopilot devices with Microsoft Graph (POST importedWindowsAutopilotDeviceIdentities), with GroupTag when you set one,
- waits up to WaitMinutes, polling the import until Microsoft reports its state (complete, or an error).

It never assigns an Autopilot profile, never deletes or edits an existing Autopilot device, and never writes the hash to disk or to the output.

The app's CERTIFICATE MUST BE ON THIS PC. Sign-in is the app registration's certificate, with its private key, in Cert:\LocalMachine\My on the PC being registered. Put the same .pfx on every PC you run this on (a Win32 app or a certificate profile in Intune does that), or the run stops with an error. A client secret (environment variable ClientSecret) also works but it then sits on every PC: prefer the certificate. The Graph permission is DeviceManagementServiceConfig.ReadWrite.All (application).

Microsoft's own page recommends registering devices by hardware hash only for testing and limited scenarios; the 4K hash identifies the device.

Where each fact comes from (read in Microsoft's documentation): importedWindowsAutopilotDeviceIdentity create: POST /deviceManagement/importedWindowsAutopilotDeviceIdentities, permission DeviceManagementServiceConfig.ReadWrite.All (application), body properties serialNumber, hardwareIdentifier (Binary, sent as base64), groupTag, state (deviceImportStatus), 201 Created; importedWindowsAutopilotDeviceIdentity get and list: DeviceManagementServiceConfig.Read.All, state.deviceImportStatus is unknown, pending, partial, complete or error, state.deviceErrorName and deviceErrorCode carry the error; windowsAutopilotDeviceIdentity list (the registered devices, with serialNumber); DevDetail CSP: ./DevDetail/Ext/DeviceHardwareData returns the base64 hardware hash; Autopilot add-devices page: the serial number and hardware hash are required, the group tag is optional. All calls are Graph v1.0. Not confirmed in Microsoft's documentation, so read defensively: the WMI class name MDM_DevDetail_Ext01, its namespace root/cimv2/mdm/dmmap and the filter InstanceID='Ext' AND ParentID='./DevDetail' (they are what the community Get-WindowsAutopilotInfo script uses; Microsoft's CSP page documents the node, not the WMI class). The meaning of the partial import status is not documented, so the script keeps waiting on it. Whether $filter works on these list calls is not documented, so the script lists everything and compares serial numbers itself. The service takes minutes to finish an import (Microsoft's page says several); the default wait is 10.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The tenant ID (a GUID) or a domain such as contoso.onmicrosoft.com. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate, which must be installed with its private key on this PC. Leave empty only if you use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `GroupTag` | Optional Autopilot group tag to put on the device (for example Kiosk). Default empty (no group tag). | (empty) | `GroupTag` or `GROUP_TAG` |
| `WaitMinutes` | How long to wait for Microsoft to finish the import. Whole number, 1 to 60. Default 10. | `10` | `WaitMinutes` or `WAIT_MINUTES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\invoke-autopilot-hash-upload.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -GroupTag Sales
Uploads this PC's hash with the group tag Sales and waits for the import to finish.
```

```powershell
.\invoke-autopilot-hash-upload.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -DryRun true
Reads the hash and checks the tenant; uploads nothing.
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
Uploaded the hardware hash of PF3ABCDE to Autopilot with group tag Sales; import complete
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\invoke-autopilot-hash-upload.log`.

## Changelog

- 1.0.0 2026-11-18 First version (untested).

## More

Full page: https://mspoutpost.com/scripts/invoke-autopilot-hash-upload

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
