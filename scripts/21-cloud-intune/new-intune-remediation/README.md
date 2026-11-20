# Intune remediation - create the detection and remediation pair

> Creates an Intune Proactive Remediation (script package) from a detection script file and a remediation script file.

| | |
|---|---|
| Script | `new-intune-remediation.ps1` |
| Type | Action |
| Category | Cloud & Intune |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: DeviceManagementScripts.ReadWrite.All (beta); an Intune license |
| Changes | Creates (or with Update replaces) one Proactive Remediation in Intune; assigns it to nobody |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.0 |
| Updated | 2026-11-18 |

## What it does

THIS SCRIPT CHANGES THINGS. It reads two PowerShell files from this computer (the detection script and the remediation script) and creates one Proactive Remediation, which Graph calls a deviceHealthScript, in the tenant's Intune. With Update=true and an existing remediation of the same display name it replaces that remediation's scripts and settings instead.

IT DOES NOT ASSIGN. A remediation created here runs on no device: the code reaches devices only when you assign it to a group or filter and give it a schedule in the Intune admin center (or with a later script). That is why it is Low risk. It never deletes a remediation.

It refuses when a remediation with the same display name already exists unless Update=true. When the existing one already holds exactly these two scripts it says so and changes nothing. Before an update it writes the old remediation, scripts included, to a JSON file under the MSP Outpost data folder (named in the output) so it can be restored.

THIS IS A BETA GRAPH CALL. Microsoft publishes deviceHealthScripts only in Graph beta (https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts) and says beta APIs can change; every call in this script is beta. There is no schedule input: the documented deviceHealthScript object has no schedule property; a remediation's schedule belongs to its assignment, which this script does not create. Graph application permission: DeviceManagementScripts.ReadWrite.All.

Where each fact comes from (read in Microsoft's documentation, Graph beta): deviceHealthScript create: POST /deviceManagement/deviceHealthScripts, 201 Created, body properties displayName, description, publisher, version, detectionScriptContent and remediationScriptContent (Binary, sent as base64), runAsAccount (system or user), runAs32Bit, enforceSignatureCheck, isGlobalScript, deviceHealthScriptType (deviceHealthScript or managedInstallerScript); update: PATCH /deviceManagement/deviceHealthScripts/{id}, 200 OK; list: GET /deviceManagement/deviceHealthScripts; list and get need DeviceManagementScripts.Read.All, create and update DeviceManagementScripts.ReadWrite.All (application). Not confirmed in Microsoft's documentation, so read defensively: whether the list returns the script content (the page's example does, so the script compares it and falls back to updating when it is absent), the size limit of a script, and which Windows licences Intune requires for Remediations.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The tenant ID (a GUID) or a domain such as contoso.onmicrosoft.com. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate (with its private key) in LocalMachine\My or CurrentUser\My on this computer. Leave empty only if you use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `DisplayName` | Name of the remediation in Intune. Required. | (empty) | `DisplayName` or `DISPLAY_NAME` |
| `DetectionScriptPath` | Full path of the detection script (.ps1) on this computer. Required. | (empty) | `DetectionScriptPath` or `DETECTION_SCRIPT_PATH` |
| `RemediationScriptPath` | Full path of the remediation script (.ps1) on this computer. Required. | (empty) | `RemediationScriptPath` or `REMEDIATION_SCRIPT_PATH` |
| `Description` | Description shown in Intune. Default empty. | (empty) | `Description` or `DESCRIPTION` |
| `Publisher` | Publisher shown in Intune. Default MSP Outpost. | `MSP Outpost` | `Publisher` or `PUBLISHER` |
| `RunAsAccount` | System (default) or User: whose context the scripts run in on the device. | `System` | `RunAsAccount` or `RUN_AS_ACCOUNT` |
| `RunAs32Bit` | true runs the scripts in 32-bit PowerShell on 64-bit Windows. Default false. | `false` | `RunAs32Bit` or `RUN_AS32_BIT` |
| `EnforceSignatureCheck` | true requires the scripts to be signed by a trusted publisher. Default false. | `false` | `EnforceSignatureCheck` or `ENFORCE_SIGNATURE_CHECK` |
| `Update` | true replaces an existing remediation with the same display name. Default false (refuse). | `false` | `Update` or `UPDATE` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\new-intune-remediation.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -DisplayName "Clear Teams cache" -DetectionScriptPath C:\Scripts\test-teams-cache.ps1 -RemediationScriptPath C:\Scripts\repair-teams-cache.ps1
Creates the remediation (not assigned to anyone).
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
Created the Intune remediation Clear Teams cache (ID 4c1f...); not assigned to any group yet
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\new-intune-remediation.log`.

## Changelog

- 1.0.0 2026-11-18 First version (untested).

## More

Full page: https://mspoutpost.com/scripts/new-intune-remediation

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
