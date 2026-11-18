# USB storage not blocked - check the block policy

> Alerts when USB storage (flash drives, external disks) is not blocked on this PC, and lists the USB drives it has seen.

| | |
|---|---|
| Script | `test-usb-storage-blocked.ps1` |
| Type | Monitor |
| Category | Security hardening & compliance |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1 |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 15 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It decides whether USB mass storage is blocked, by any of these three mechanisms:

- the USB storage drivers are disabled (service USBSTOR Start = 4, and UASPStor Start = 4 where that driver exists: USB 3 drives that use UASP bypass USBSTOR);
- the removable-storage policy denies access (HKLM\SOFTWARE\Policies\ Microsoft\Windows\RemovableStorageDevices: Deny_All, or Deny_Read and Deny_Write on the Removable Disks class);
- the device-installation policy denies USB mass storage (DenyDeviceIDs contains USB\Class_08 and DenyDeviceIDsRetroactive = 1), which is how disable-usb-storage blocks everything except AllowedSerials.

With Mode Block (default) any of those counts as blocked. With Mode ReadOnly a write-deny policy (Deny_Write alone) counts as well.

It also lists every USB disk Windows has ever seen (not USB CD/DVD drives) on this PC (HKLM\SYSTEM\CurrentControlSet\Enum\USBSTOR) with its serial number, and whether it is connected now. AllowedSerials marks devices you approved (the Allowed column); it does not change whether the PC alerts. A device that is connected now and not allowed while USB storage is blocked is reported as a warning: the block applies to the next time it is plugged in. A USB drive with no serial shows Windows' own made-up instance number.

Pair: disable-usb-storage fixes what this alerts on.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Mode` | Block (default) or ReadOnly. Block: USB storage must be fully blocked. ReadOnly: a write block also passes. Use the same value as disable-usb-storage. | `Block` | `Mode` or `MODE` |
| `AllowedSerials` | Serial numbers of USB drives you approved, separated by commas or semicolons (see the Serial column of a first run). Default empty. Matched exactly, ignoring case. | (empty) | `AllowedSerials` or `ALLOWED_SERIALS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-usb-storage-blocked.ps1
```

Alerts unless USB storage is blocked; lists the USB drives seen so far.

```powershell
.\test-usb-storage-blocked.ps1 -Mode ReadOnly -AllowedSerials "4C530001230456,0123456789ABCDEF"
```

Accepts a write block, and marks those two drives as approved.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Mode`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
USB storage is NOT blocked (USBSTOR Start=3, no deny policy); 2 USB storage device(s) seen, 1 connected now
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Kind`, `Item`, `Serial`, `State`, `Allowed`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-usb-storage-blocked

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
