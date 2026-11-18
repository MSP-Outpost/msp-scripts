# Retire a PC - leave domain and Entra ID, remove MDM, write the record

> Retires a PC: leaves Entra ID and the domain, removes MDM enrollment, and writes a retirement record. Does not wipe the disk.

| | |
|---|---|
| Script | `invoke-pc-retirement.ps1` |
| Type | Action |
| Category | Offboarding & decommission |
| Platforms | Windows 10, Windows 11 |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | Leaves Entra ID and the domain, removes MDM enrollments (registry key and tasks), writes a retirement record file; does not wipe or restart |
| Risk | **High** |
| Reboot | May |
| Typical runtime | Under a minute |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=invoke-pc-retirement`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\invoke-pc-retirement.log`.
- Before it edits or deletes configuration, it copies it to `%ProgramData%\MSPOutpost\Backups\invoke-pc-retirement\<UTC time>\` and keeps the last 10 runs. If a backup fails, nothing is changed.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. It is the "PC is leaving service" step, and it does only the parts that apply to this PC:

- Entra ID: if the PC is Entra joined or hybrid joined, it runs dsregcmd /leave (LeaveEntra).
- Domain: if the PC is joined to an Active Directory domain, it leaves the domain and joins the workgroup WorkgroupName (LeaveDomain). The PC must be restarted to finish this; the script never restarts it. It leaves the computer account in Active Directory: delete it there.
- MDM: any remaining MDM enrollment (Intune and similar) is removed from this PC: its registry key (exported to the backup folder first) and its scheduled tasks (UnenrollMdm). The device record in the MDM console is NOT touched: retire or delete it there.
- Record: always writes a retirement record, a text file in %ProgramData%\MSPOutpost\Retirement\ with the computer name, serial number, make and model, OS, disk models and serial numbers, BitLocker status and recovery key IDs (never the keys themselves), what the PC was joined to, what this run did, and the optional Note.

A part that does not apply is SKIPPED with its reason in the table (not domain joined, not Entra joined, no MDM enrollment, or turned off by its input). A PC that is not joined to anything still gets its record.

IT DOES NOT WIPE ANYTHING. User files, profiles, programs and the disk contents are untouched and the record says so: erase the drives (Reset this PC with "Clean the drive", the MDM wipe, or the vendor's secure-erase) before the PC leaves your control. It also does NOT remove the RMM or remote support agent that is running this script, because that would end the run and the record: remove it last, with uninstall-rmm-agent, once the record is written. Cached credentials and saved passwords are not cleared.

Only Windows 10 and 11 PCs; servers and domain controllers are SKIPPED.

A High-risk Action: it only lists what it would do until BOTH DryRun=false AND Approve=invoke-pc-retirement are set. Each part is one change (the record is one), so a run makes at most 4 changes plus one per MDM enrollment; MaxChanges defaults to 25. A second run, with nothing left to leave, says "Already retired". After a domain leave, restart, then run it again to confirm.

Not proven on a joined PC: the Entra, domain and MDM parts need a PC joined to a real tenant or domain. Run the dry run on the PC first and read the table.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `LeaveEntra` | true leaves Entra ID (dsregcmd /leave) when the PC is joined or registered. Default true. | `true` | `LeaveEntra` or `LEAVE_ENTRA` |
| `LeaveDomain` | true leaves the Active Directory domain and joins WorkgroupName. Default true. | `true` | `LeaveDomain` or `LEAVE_DOMAIN` |
| `UnenrollMdm` | true removes the MDM enrollment from this PC. Default true. | `true` | `UnenrollMdm` or `UNENROLL_MDM` |
| `WorkgroupName` | The workgroup to join when leaving the domain. 1 to 15 letters, digits or hyphens. Default WORKGROUP. | `WORKGROUP` | `WorkgroupName` or `WORKGROUP_NAME` |
| `Note` | Free text for the record, for example a ticket number or the reason. Up to 100 characters, plain ASCII. Default empty. | (empty) | `Note` or `NOTE` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\invoke-pc-retirement.ps1
```

Dry run: lists what it would leave and remove, and writes nothing.

```powershell
.\invoke-pc-retirement.ps1 -DryRun false -Approve invoke-pc-retirement -Note "Ticket 4821, replaced"
```

Leaves Entra ID, the domain and MDM as they apply, and writes the record.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `LeaveEntra`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `invoke-pc-retirement`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Retired: left Entra ID, left domain corp.local (restart to finish); record PC042-20261117-101500.txt written; disks NOT wiped
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\invoke-pc-retirement.log`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/invoke-pc-retirement

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
