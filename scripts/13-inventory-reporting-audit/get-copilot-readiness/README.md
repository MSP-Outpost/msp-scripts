# Is this PC ready for Microsoft 365 Copilot?

> Lists what this PC needs for Microsoft 365 Copilot and answers Ready or names the blockers.

| | |
|---|---|
| Script | `get-copilot-readiness.ps1` |
| Type | Report |
| Category | Inventory, reporting & audit |
| Platforms | Windows 10, Windows 11 |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It reads, one row each (Check, Value, Ready):

- Windows: version and build. Windows 10 22H2 (build 19045) or later counts as ready; Windows Server is SKIPPED.
- Microsoft 365 Apps: installed (Click-to-Run, a product ID containing O365 or Microsoft365), its build, and 32- or 64-bit.
- Update channel: Current Channel and Monthly Enterprise Channel are ready; Semi-Annual Enterprise Channel is NOT ready ("Copilot limited") unless AllowSemiAnnual is true; any other channel (Preview, Beta, unknown) is not ready. The channel is the one a Group Policy "update branch" names, else the one named by the Click-to-Run content-delivery (CDN) address.
- Entra ID: from "dsregcmd /status" (run as SYSTEM): AzureAdJoined, WorkplaceJoined and DomainJoined. Entra joined, hybrid joined or Entra registered is ready; a PC with none of them has no work account sign-in for Copilot. Only the machine state is read: whether a USER is signed in with a licensed account is not visible to SYSTEM.
- New Outlook (Microsoft.OutlookForWindows) and Microsoft Teams (new Teams, MSTeams): present or not, for information, always ready.
- The Windows Copilot app, the Microsoft 365 Copilot app (Microsoft.MicrosoftOfficeHub) and the Windows Recall optional feature: present or not, for information, always ready.

The answer is "Ready for Microsoft 365 Copilot" or "Not ready for Microsoft 365 Copilot:" followed by the blockers. A Report never alerts: the status is OK either way, and the custom field receives "Ready" or "Not ready". Licences in the tenant are not checked.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `AllowSemiAnnual` | true to count Semi-Annual Enterprise Channel as ready (default false). | `false` | `AllowSemiAnnual` or `ALLOW_SEMI_ANNUAL` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-copilot-readiness.ps1
```

One row per requirement and a Ready / Not ready answer.

```powershell
.\get-copilot-readiness.ps1 -AllowSemiAnnual true -OutputFormat Json
```

Counts Semi-Annual Enterprise Channel as ready and prints JSON.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `AllowSemiAnnual`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Not ready for Microsoft 365 Copilot: Microsoft 365 Apps on Semi-Annual Enterprise Channel (Copilot limited); not Entra joined or registered
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Check`, `Value`, `Ready`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/get-copilot-readiness

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
