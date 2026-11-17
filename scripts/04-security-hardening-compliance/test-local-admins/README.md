# Unapproved local administrators

> Alerts when someone who is not on your approved list is a local administrator.

| | |
|---|---|
| Script | `test-local-admins.ps1` |
| Type | Monitor |
| Category | Security hardening & compliance |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1 |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 10 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It reads the members of the built-in Administrators group (found by its SID S-1-5-32-544, so it works in any language) and compares each member with ApprovedMembers. It writes one row per member and alerts (exit 1) when any member is not approved.

A member whose SID no longer resolves (a deleted domain account, a PC moved between domains) makes Get-LocalGroupMember fail. Those are the members worth finding, so the script then reads the group through ADSI and reports them by SID.

Domain and Entra groups that sit in the Administrators group are listed as one row with Class Group; their own members are NOT expanded (a PC cannot read them reliably). Approve the group by name or SID.

An approved entry matches the full name (PC\admin), the short name (admin), or a SID (S-1-5-21-...-500), case-insensitive; * and ? are wildcards. When ApprovedMembers is empty the defaults apply: the built-in Administrator account (any SID ending in -500) and Domain Admins (SID ending in -512). Giving a list REPLACES the defaults: name the built-in account in it if you want it approved. Entra-joined PCs add the Global Administrator and Device Administrator roles as S-1-12-1-... members: approve them by SID.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `ApprovedMembers` | Members allowed to be local administrators, separated by commas, e.g. "Administrator, CONTOSO\Domain Admins, CONTOSO\Desk Techs". Default empty: the built-in Administrator and Domain Admins, matched by SID. | (empty) | `ApprovedMembers` or `APPROVED_MEMBERS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-local-admins.ps1
```

Alerts unless only the built-in Administrator and Domain Admins are admins.

```powershell
.\test-local-admins.ps1 -ApprovedMembers "Administrator, helpdesk, CONTOSO\Desk Techs"
```

Approves exactly those three; anyone else raises an alert.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `ApprovedMembers`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
2 of 3 local administrators not approved: PC01\jsmith, S-1-5-21-1-2-3-1104
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Member`, `Class`, `Source`, `Sid`, `Approved`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-local-admins

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
