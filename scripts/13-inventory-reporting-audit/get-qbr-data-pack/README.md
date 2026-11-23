# PC facts for the quarterly review

> Collects one PC's quarterly-review facts (OS, patching, security, disk, hardware) from the PC itself.

| | |
|---|---|
| Script | `get-qbr-data-pack.ps1` |
| Type | Report |
| Category | Inventory, reporting & audit |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## What it does

THIS SCRIPT IS READ-ONLY. It reads local facts only (no PSA, no internet) and writes one Fact/Value row per item: computer name; Windows edition, version and build (with the update revision); Windows install date; uptime in days; date of the newest installed update (the newer of Windows Update history and Get-HotFix) and which one; whether a restart is pending (Windows servicing or Windows Update flags); Microsoft Defender state and signature age in days; BitLocker protection of the system drive; free space of the system drive in percent and GB; installed RAM in GB; processor; manufacturer and model; BIOS serial number. Run it on each PC and collect the rows (OutputFormat Json or Csv, or ExportPath) into the review. A fact that cannot be read says "Unknown" or "Not available" with the reason; one unreadable fact never stops the run. Warranty is NOT included: it needs the manufacturer's service, which the script get-warranty-status does. The install date is the date of the last Windows feature update (an upgrade resets it), not the date the PC was bought.

Where each fact comes from: Win32_OperatingSystem (Caption, Version, BuildNumber, InstallDate, LastBootUpTime), Win32_ComputerSystem (Manufacturer, Model, TotalPhysicalMemory), Win32_Processor (Name, NumberOfCores), Win32_BIOS (SerialNumber), Win32_LogicalDisk (Size, FreeSpace), Win32_EncryptableVolume in root\CIMV2\Security\MicrosoftVolumeEncryption (GetProtectionStatus: 0 off, 1 on, 2 unknown), Get-MpComputerStatus (AMServiceEnabled, AntivirusEnabled, RealTimeProtectionEnabled, AMRunningMode, AntivirusSignatureLastUpdated), the Windows Update Agent history (Microsoft.Update.Session), Get-HotFix, and the registry keys CBS RebootPending and WindowsUpdate RebootRequired. Not confirmed in the documentation read for this script, so read defensively: the Defender property AMRunningMode and the registry values DisplayVersion and UBR of HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion (both proven on Windows 11 by other library scripts, not stated on the pages above). Pending file renames are not counted as a pending restart (they are common and noisy); use test-pending-reboot for that.

## Inputs

This script has no inputs of its own. The [standard inputs](#standard-inputs) below still apply.

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-qbr-data-pack.ps1
Prints the facts for this PC, one per line.
```

```powershell
.\get-qbr-data-pack.ps1 -OutputFormat Json
Prints one JSON object with the facts as rows, for the review tool to read.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `OutputFormat`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
DESK-014: Windows 11 Pro 24H2 (26100.2605), patched 9 days ago, Defender on (signatures 0 d), BitLocker on, C: 41% free, 16 GB RAM
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Fact`, `Value`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-18 First version.

## More

Full page: https://mspoutpost.com/scripts/get-qbr-data-pack

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
