# Block USB storage with an allow-list

> Blocks USB storage (flash drives, external disks) with Windows policy, optionally letting approved drives through.

| | |
|---|---|
| Script | `disable-usb-storage.ps1` |
| Type | Action |
| Category | Security hardening & compliance |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | Writes the removable-storage and device-installation policies and sets the USBSTOR and UASPStor driver start types; backs the keys up first |
| Risk | **High** |
| Reboot | May |
| Typical runtime | Under 20 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=disable-usb-storage`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\disable-usb-storage.log`.
- Before it edits or deletes configuration, it copies it to `%ProgramData%\MSPOutpost\Backups\disable-usb-storage\<UTC time>\` and keeps the last 10 runs. If a backup fails, nothing is changed.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. Risk is High, so it is a dry run unless you set BOTH DryRun=false AND Approve=disable-usb-storage (typing the script name is the deliberate step). First look at the dry-run list, then run it for real.

Mode Block, no AllowedSerials (default): disables the USB storage drivers (HKLM\SYSTEM\CurrentControlSet\Services\USBSTOR Start = 4, and UASPStor Start = 4 where it exists, because USB 3 drives that use UASP bypass USBSTOR) and sets the "Removable Disks: Deny read access" and "Deny write access" policies (HKLM\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices\ {53f5630d-b6bf-11d0-94f2-00a0c91efb8b}, Deny_Read = 1, Deny_Write = 1). It does not use the "all removable storage" deny, so CD/DVD drives, tape drives and phones that connect as MTP keep working.

Mode ReadOnly: denies write access to Removable Disks (Deny_Write = 1) so a USB drive can be read and not written. It undoes the full block it may have set earlier (Deny_Read, the drivers' Start = 4 back to 3, and the device-installation deny list).

AllowedSerials (Mode Block only): blocks every USB mass-storage device EXCEPT the drives with those serial numbers, through the device-installation policy: it denies USB mass storage (hardware ID USB\Class_08), turns on "layered" evaluation so an allow wins over a deny, and allows the instance IDs of the listed drives. A drive can only be allowed if Windows has seen it before (it appears in the Serial column of test-usb-storage-blocked): plug it in once first. A serial that was never seen is skipped with a warning, and that drive will be blocked. Because the driver must stay on for allowed drives, this mode also undoes Deny_Read, Deny_Write and Start = 4 if they were set. USB 3 drives that use UASP are matched by SCSI instance IDs that this script does not read: with an allow-list they may stay blocked.

Before changing anything it saves the policy keys it will touch (reg export) to %ProgramData%\MSPOutpost\Backups\disable-usb-storage\. A policy is applied when a drive is plugged in: a USB drive that is connected now stays mounted until it is unplugged or the PC restarts (Reboot: May). A domain Group Policy that sets the same values overwrites this script at its next refresh.

Blocking USB storage also stops USB backup drives and anything that copies to a USB disk, such as backup software or a scanner that saves to a stick: the run warns about it. On Windows Server it refuses unless Force is true.

Never touched: keyboards, mice, USB hubs, phones, printers, CD/DVD drives, internal disks, or any device that is not USB mass storage.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Mode` | Block (default) or ReadOnly. | `Block` | `Mode` or `MODE` |
| `AllowedSerials` | Serial numbers of USB drives that stay usable, separated by commas or semicolons, letters, digits, dot, underscore and hyphen only, 4 to 64 characters each, no wildcards. Mode Block only. Default empty. | (empty) | `AllowedSerials` or `ALLOWED_SERIALS` |
| `Force` | true to allow the change on Windows Server (default false: refuse). A server's USB disks are often its backup targets. | `false` | `Force` or `FORCE` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\disable-usb-storage.ps1
```

Dry run: lists the settings it would write.

```powershell
.\disable-usb-storage.ps1 -AllowedSerials "4C530001230456" -DryRun false -Approve disable-usb-storage
```

Blocks all USB drives except the one with that serial number.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Mode`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `disable-usb-storage`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
USB storage blocked (USBSTOR disabled, removable disks deny read and write); 1 USB drive connected now stays mounted until unplugged or restart
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\disable-usb-storage.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/disable-usb-storage

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
