# SMBv1 still enabled - turn it off (can break old devices)

> Turns off the old, unsafe SMBv1 protocol: the server setting and the Windows optional feature. Needs approval.

| | |
|---|---|
| Script | `disable-smb1.ps1` |
| Type | Action |
| Category | Security hardening & compliance |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1; SmbShare and DISM modules; administrator rights |
| Changes | Sets EnableSMB1Protocol to False; disables the SMB1Protocol optional feature (no restart); saves a registry backup first |
| Risk | **High** |
| Reboot | May |
| Typical runtime | Under 1 minute |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=disable-smb1`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\disable-smb1.log`.
- Before it edits or deletes configuration, it copies it to `%ProgramData%\MSPOutpost\Backups\disable-smb1\<UTC time>\` and keeps the last 10 runs. If a backup fails, nothing is changed.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS, AND CAN BREAK OLD DEVICES. Old scanners, copiers, NAS boxes and Windows XP or Server 2003 era software that still speak only SMB1 stop working when SMB1 is off. It is a High-risk script: it only changes anything when DryRun is false AND Approve is set to disable-smb1; otherwise it prints what it would do. It:

- reads the SMB1 access audit log (event 3000 in Microsoft-Windows-SMBServer/Audit) for AuditDays days. When clients were seen using SMB1 it stops, changes nothing and lists them, unless AllowClientUse is true. It also stops when SMB1 auditing is off (AuditSmb1Access False), because an empty log then means "unknown", not "nobody": turn auditing on with Set-SmbServerConfiguration -AuditSmb1Access $true and read test-smb1 after a few weeks,
- backs up the LanmanServer registry key (where the SMB1 server setting lives) to the MSPOutpost backup folder,
- sets the SMB server's EnableSMB1Protocol to False (Set-SmbServerConfiguration); this takes effect at once,
- disables the Windows optional feature SMB1Protocol (or, when only its client or server parts are enabled, those) with Disable-WindowsOptionalFeature -NoRestart. This removes the SMB1 client too, but only after the next restart; the script never restarts the PC and says "restart needed" in its answer.

Removing the optional feature also removes the SMB1 client: drive mappings and scans to old NAS boxes and copiers that only speak SMB1 stop working after the next restart, not only inbound connections.

It does not change SMB2 or SMB3, signing, firewall rules or shares.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `AuditDays` | How many days of the SMB1 access audit log to read before acting. Whole number 0 to 365; 0 skips the check. Default 30. | `30` | `AuditDays` or `AUDIT_DAYS` |
| `AllowClientUse` | true to disable SMB1 even when the audit log shows clients still using it. Default false. | `false` | `AllowClientUse` or `ALLOW_CLIENT_USE` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\disable-smb1.ps1
```

Dry run: lists the SMB1 pieces that are on and would be turned off.

```powershell
.\disable-smb1.ps1 -DryRun false -Approve disable-smb1
```

Turns SMB1 off for real (after the audit-log check).

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `AuditDays`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `disable-smb1`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
SMB1 disabled: server setting off, feature SMB1Protocol disabled; restart needed to remove the SMB1 client
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\disable-smb1.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/disable-smb1

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
