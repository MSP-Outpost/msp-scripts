# Install Microsoft 365 Apps (Office) with a generated configuration

> Installs Microsoft 365 Apps (Word, Excel, Outlook and the rest) silently with the Office Deployment Tool and a generated configuration.

| | |
|---|---|
| Script | `install-microsoft-365-apps.ps1` |
| Type | Action |
| Category | Software deployment & updates |
| Platforms | Windows 10 1809+, Windows 11, Windows Server 2019+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, internet access to Microsoft, 8 GB free disk |
| Changes | Downloads the Office Deployment Tool and installs Microsoft 365 Apps |
| Risk | Low |
| Reboot | May |
| Typical runtime | 10 to 60 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT CHANGES THINGS. It downloads the Office Deployment Tool (setup.exe) from Microsoft's own address, refuses to run it unless its Authenticode signature is valid and belongs to Microsoft Corporation, writes a configuration.xml from the inputs into a protected folder under %ProgramData%\MSPOutpost, runs "setup.exe /configure", waits for it, and then checks that Windows lists the product as installed. The setup tool and configuration are deleted afterwards. The ODT's own log is kept in %ProgramData%\MSPOutpost\Logs\microsoft-365-odt.

It installs one Microsoft 365 product. It does not remove an older Office (the configuration has no RemoveMSI), does not sign anyone in or activate anything (users sign in with their Microsoft 365 account), and does not change an Office that is already there: if a Click-to-Run Office with the same Products value is installed, it ends in OK without doing anything; if a different product is installed, it stops with an error and changes nothing. A leftover Windows Installer (MSI) Office can make setup.exe fail; uninstall it first.

The install accepts the Office licence terms on the user's behalf (AcceptEULA), which is what running an unattended Office install means: run it only for people licensed to use the product. It needs about 8 GB free on the system drive, internet access to officecdn.microsoft.com and the Office CDN, and typically takes 10 to 40 minutes (longer on a slow link: raise TimeoutMinutes). A dry run only describes the install; it downloads nothing.

On a Windows Arm64 PC the 64-bit edition installs the native Arm64 build (setup.exe chooses it); Architecture Auto does that for you.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Channel` | Update channel: Current, MonthlyEnterprise or SemiAnnual. Default MonthlyEnterprise (the monthly, predictable one for managed PCs). | `MonthlyEnterprise` | `Channel` or `CHANNEL` |
| `Architecture` | Auto (default), x64, x86 or arm64. Auto installs the 64-bit edition on a 64-bit Windows PC (the native Arm64 build on an Arm PC) and 32-bit on a 32-bit one. arm64 is accepted only on an Arm64 PC and x64 only on an x64 PC; x86 works anywhere. | `Auto` | `Architecture` or `ARCHITECTURE` |
| `Products` | O365BusinessRetail (Microsoft 365 Apps for business, default) or O365ProPlusRetail (Microsoft 365 Apps for enterprise). | `O365BusinessRetail` | `Products` or `PRODUCTS` |
| `ExcludeApps` | Apps to leave out, a list separated by comma or semicolon, from: Access, Bing, Excel, Groove, Lync, OneDrive, OneNote, Outlook, OutlookForWindows, PowerPoint, Publisher, Teams, Word. Groove is the old OneDrive for Business sync app and Lync is Skype for Business. Default Groove,Lync. None means exclude nothing. | `Groove,Lync` | `ExcludeApps` or `EXCLUDE_APPS` |
| `Language` | MatchOS (default: the Windows display language) or a culture such as en-us, fr-ca or de-de. | `MatchOS` | `Language` or `LANGUAGE` |
| `SharedComputerLicensing` | true turns on shared computer activation, for shared PCs and Remote Desktop servers. Default false. | `false` | `SharedComputerLicensing` or `SHARED_COMPUTER_LICENSING` |
| `TimeoutMinutes` | How long to wait for setup.exe. Whole number, 10 to 240. Default 60. | `60` | `TimeoutMinutes` or `TIMEOUT_MINUTES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\install-microsoft-365-apps.ps1
```

Installs Microsoft 365 Apps for business on the monthly enterprise channel, without OneDrive's old sync app and Skype for Business.

```powershell
.\install-microsoft-365-apps.ps1 -Products O365ProPlusRetail -Channel SemiAnnual -ExcludeApps Groove,Lync,Teams,Publisher,Access -Language en-us
```

Installs Microsoft 365 Apps for enterprise on the semi-annual channel in English without Teams, Publisher and Access.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Channel`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Installed Microsoft 365 Apps O365BusinessRetail 16.0.19231.20154 (x64, MonthlyEnterprise)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\install-microsoft-365-apps.log`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/install-microsoft-365-apps

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
