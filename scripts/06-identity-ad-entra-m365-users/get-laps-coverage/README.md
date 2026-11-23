# Which computers have a managed local admin password

> Lists which Windows computers have a managed local administrator password (Windows LAPS or legacy LAPS) and which have none.

| | |
|---|---|
| Script | `get-laps-coverage.ps1` |
| Type | Report |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Domain member for AD; any Windows for Entra ID |
| Runs as | Either |
| Requires | PowerShell 5.1; ActiveDirectory module for AD; Graph: DeviceLocalCredential.ReadBasic.All, Device.Read.All |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 2 minutes |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## What it does

THIS SCRIPT IS READ-ONLY. It builds one list of Windows computers from up to two places and says for each whether a LAPS password is being managed:

- Active Directory, when this computer is a member of a domain: Get-ADComputer for computers with a Windows operating system, reading ONLY the password EXPIRATION TIME attributes msLAPS-PasswordExpirationTime (Windows LAPS) and ms-Mcs-AdmPwdExpirationTime (legacy Microsoft LAPS). Microsoft's schema page lists the expiration time attribute with search flags 0, that is, not marked confidential. The password attributes themselves are never requested, so no password is read or printed. The script first checks that each attribute exists in the schema, and tells you which do not.
- Microsoft Entra ID, when TenantId (and ClientId) are given: the list of Windows LAPS records (GET /directory/deviceLocalCredentials, which Microsoft documents as excluding the credentials property) and the device list. The credentials property is never requested; the app needs only DeviceLocalCredential.ReadBasic.All, never DeviceLocalCredential.Read.All. A hybrid joined computer (Entra trustType ServerAd) found in both lists is one row; an Entra-joined or registered device that only shares a name with an AD computer is a row of its own. Domain controllers, disabled computers and computers not seen for StaleDays are left out, so the list is the computers that should have a password. A password counts as Managed when its expiration time is in the future (or less than a day past), as Overdue when it expired more than a day ago (the computer has not rotated it: it is offline or Windows LAPS is not working), and the computer is Not managed when it has no expiration time anywhere. The answer states the coverage: how many of the computers have a managed password and how many have none. Reading the expiration time says that a password was stored, not that it is current for the local account: use test-windows-laps on a device to check its own backup. The Active Directory read covers the domain of this computer only.

Microsoft Graph application permissions (admin consent), only when TenantId is given: DeviceLocalCredential.ReadBasic.All and Device.Read.All. The Active Directory read needs a domain account that may read computer objects (any domain user does by default) and the ActiveDirectory module (RSAT).

Where each fact comes from: GET v1.0/directory/deviceLocalCredentials (list, excludes credentials; permission DeviceLocalCredential.ReadBasic.All) with properties id (the device's deviceId), deviceName, lastBackupDateTime and refreshDateTime (when the credential will be refreshed); GET v1.0/devices with deviceId, displayName, operatingSystem, accountEnabled, approximateLastSignInDateTime. Not confirmed in the documentation, so read defensively: that the list endpoint returns every device in one pass without a size limit (the script follows nextLink); that the expiration time attribute is readable by an ordinary domain user in every environment (when it is not, every computer looks Not managed and the script warns); whether Get-ADComputer returns the large-integer expiration time as a number or text (both are accepted); whether refreshDateTime is the expiry time to compare with now (the page says "will be refreshed").

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client tenant (a GUID or a domain such as contoso.onmicrosoft.com). Optional: empty reads Active Directory only. Required for the Entra ID part. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required when TenantId is set. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint (40 hex characters) of the app's certificate with its private key in LocalMachine\My or CurrentUser\My. Preferred. When empty, the secret is read from the environment variable ClientSecret (a secure RMM field). | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `StaleDays` | Leave out computers not seen (last logon in Active Directory, last sign-in in Entra ID) for this many days. Whole number, 0 to 3650; 0 lists every computer. Default 90. | `90` | `StaleDays` or `STALE_DAYS` |
| `IncludeDisabled` | true to also list disabled computers. Default false. | `false` | `IncludeDisabled` or `INCLUDE_DISABLED` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-laps-coverage.ps1
On a domain-joined server: the Active Directory computers and whether each has a LAPS password.
```

```powershell
.\get-laps-coverage.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Also reads the Windows LAPS records in Entra ID and merges hybrid computers into one row.
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
LAPS coverage: 41 of 52 Windows computers (79%) have a managed password (38 Windows LAPS, 3 legacy); no password on 11; 2 overdue (not rotated)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Computer`, `Os`, `Directory`, `Source`, `Status`, `ExpiresUtc`, `LastBackupUtc`, `LastSeenUtc`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/get-laps-coverage

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
