# Someone changed a GPO - alert on any GPO change

> Alerts when a Group Policy Object was added, removed or changed since the last run, and names the account when it can.

| | |
|---|---|
| Script | `test-gpo-changes.ps1` |
| Type | Monitor |
| Category | Server roles (AD DS, Hyper-V, SQL, IIS, file, RDS) |
| Platforms | Windows Server 2016+ (DC, or a member with GPMC) |
| Runs as | System |
| Requires | PowerShell 5.1; admin rights; GroupPolicy module (GPMC); directory change auditing for ChangedBy |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## What it does

THIS SCRIPT DOES NOT CHANGE ANYTHING IN THE DOMAIN OR ON THE SYSTEM; its only write is its own small snapshot file (it must remember the last state). It reads every GPO (Get-GPO -All: name, id, modification time, user and computer version numbers) and compares them with the snapshot of the previous run, kept in %ProgramData%\MSPOutpost\State\test-gpo-changes.json:

Added     a GPO that was not in the snapshot Removed   a GPO that is gone Modified  a GPO whose modification time or version numbers differ

The FIRST run only records the snapshot and ends OK. When changes are found it ends ALERT with one row per change and, unless UpdateBaseline is false, moves the snapshot forward, so each change alerts once. ResetBaseline=true records the current state as the new snapshot and ends OK.

Who changed it: Get-GPO does not say. When FindChangedBy is true the script looks in this computer's Security log for event 5136 (a directory object was modified) on groupPolicyContainer objects since the previous snapshot and shows the account in ChangedBy. That needs the audit subcategory "Audit Directory Service Changes" on and works only on the domain controller that took the change (run it on the PDC emulator, where GPMC writes); otherwise ChangedBy says "unknown".

Run it on a domain controller or a member server with the Group Policy Management feature (GPMC, module GroupPolicy). Without the module it ends ERROR; on a computer that is not in a domain it ends SKIPPED.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `UpdateBaseline` | true to record the current state after reporting, so the next run compares with it. Default true. | `true` | `UpdateBaseline` or `UPDATE_BASELINE` |
| `ResetBaseline` | true to record the current state and end OK without comparing. Default false. | `false` | `ResetBaseline` or `RESET_BASELINE` |
| `FindChangedBy` | true to look up the changing account in the Security log. Default true. | `true` | `FindChangedBy` or `FIND_CHANGED_BY` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-gpo-changes.ps1
```

First run records the GPOs; later runs alert on any difference.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `UpdateBaseline`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
2 GPO change(s) since 2026-11-18T09:00:00Z: 1 modified, 1 added, 0 removed; first: Default Domain Policy
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Gpo`, `Change`, `PreviousModifiedUtc`, `ModifiedUtc`, `PreviousVersion`, `Version`, `ChangedBy`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/test-gpo-changes

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
