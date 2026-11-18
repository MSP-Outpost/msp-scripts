# Defender turned off or broken - switch it back on

> Defender is off or broken: removes local policy values that disable it, starts its services, turns real-time protection on and updates signatures.

| | |
|---|---|
| Script | `repair-defender.ps1` |
| Type | Action |
| Category | AV / EDR & incident response |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1; Microsoft Defender installed; administrator rights |
| Changes | Removes local policy values that disable Defender (backed up first); sets WinDefend to Automatic and starts it; turns on real-time protection; updates signatures |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 2 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS. It repairs Microsoft Defender Antivirus when it is the antivirus this PC relies on and it is off or broken. It:

- removes policy values that turn Defender off from HKLM\SOFTWARE\Policies\Microsoft\Windows Defender (DisableAntiSpyware, DisableAntiVirus and the real-time protection values), but only when the value is 1 and no Group Policy file (Registry.pol, local or domain) mentions it. A value Group Policy sets is reported as "managed by Group Policy" and left alone: change the policy instead. The policy key is exported to the MSPOutpost backup folder first,
- sets the WinDefend service to Automatic when it is Disabled and starts WinDefend (and WdNisSvc), where Windows allows it,
- turns real-time, behavior and download scanning back on (Set-MpPreference),
- updates signatures (Update-MpSignature) when UpdateSignatures is true.

It is skipped when another antivirus is active in Windows Security Center on a workstation, or when Defender is in passive mode. Tamper protection stops Windows accepting some of these changes: when it is on and Defender is still not protecting afterwards, the script says so. It does not read Intune (MDM) policy, does not remove other antivirus products and does not touch exclusions.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `UpdateSignatures` | true (default) to run Update-MpSignature after repairing; a failed update is a warning, not an error. | `true` | `UpdateSignatures` or `UPDATE_SIGNATURES` |
| `Force` | false (default): on a server the script does nothing and says so, because a third-party antivirus usually switches Defender off there with DisableAntiSpyware=1, and turning Defender back on would run two engines on a production server. true to repair Defender on servers anyway. | `false` | `Force` or `FORCE` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\repair-defender.ps1 -DryRun true
```

Lists what it would remove, start or turn on.

```powershell
.\repair-defender.ps1 -UpdateSignatures false
```

Repairs Defender without downloading signatures.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `UpdateSignatures`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Defender repaired: removed 2 policy values, started WinDefend, real-time protection on, signatures updated
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\repair-defender.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/repair-defender

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
