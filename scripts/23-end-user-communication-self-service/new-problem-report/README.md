# Report a problem - diagnostics and description in a zip

> Collects a "something is wrong" report from the signed-in user's PC: basic diagnostics and a description, zipped and optionally sent to your webhook.

| | |
|---|---|
| Script | `new-problem-report.ps1` |
| Type | Action |
| Category | End-user communication & self-service |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, a signed-in user; optional secure field ProblemReportWebhook |
| Changes | Writes a zip under ProgramData\MSPOutpost\ProblemReports; deletes zips there older than KeepDays; optionally sends the zip to the webhook |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.0 |
| Updated | 2026-11-18 |

## What it does

THIS SCRIPT CHANGES THINGS (it writes a report file and may send it). In order it:

- reads diagnostics as SYSTEM: computer name, signed-in user, Windows version, IPv4 addresses, uptime, free space on the system drive, and the Error and Critical events of the Application log from the last EventMinutes minutes (at most 50, each cut to 300 characters);
- writes report.txt (the description and the diagnostics) into one zip under %ProgramData%\MSPOutpost\ProblemReports, a folder only SYSTEM and administrators can read, and deletes zips there older than KeepDays;
- when the secure environment variable ProblemReportWebhook holds an https:// address, sends the zip to it as one HTTP POST with the content type application/zip and checks for a 2xx answer.

No dialog is shown. The library standard forbids prompts and message boxes in a script, and Microsoft's documentation does not establish that a window opened from a one-shot task in the user's session is safe to wait on, so the one-line description comes from the Description input: let your RMM, your shortcut or your help desk fill it in.

It takes NO screenshot. Screen-capture code in a PowerShell script is detected by Microsoft Defender as a hack tool (on 2026-11-18 Defender named this script's first version HackTool:PowerShell/EmpireGetScreenshot.C and blocked the whole script), so ask the user to attach a picture to the ticket instead (Windows key + Shift + S).

With a webhook the zip leaves the PC; the webhook address is a secret and is never printed. The description is placed in report.txt only, not in the web address. The webhook must accept a raw application/zip body (a plain HTTPS endpoint you control or a custom automation trigger). Not confirmed against any ticketing product: Slack, Teams and most PSA "email in" or "webhook" doors do not take a file this way, so put a small receiver in front of them.

Where each fact comes from: Get-WinEvent -FilterHashtable with the keys LogName, Level (1 Critical, 2 Error) and StartTime, and -MaxEvents; Win32_OperatingSystem, Win32_NetworkAdapterConfiguration and Win32_LogicalDisk (CIM). Not confirmed in the documentation read here, so treated defensively: Compress-Archive behaviour; the error id NoMatchingEventsFound that Get-WinEvent raises when no event matches (read as "no events").

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Description` | One line from the user about what is wrong, up to 500 characters. Default empty, which is recorded as "(no description given)". | (empty) | `Description` or `DESCRIPTION` |
| `EventMinutes` | How far back to read Application-log errors, in minutes. Whole number, 1 to 1440. Default 10. | `10` | `EventMinutes` or `EVENT_MINUTES` |
| `KeepDays` | Reports older than this many days are deleted from the ProblemReports folder. Whole number, 1 to 3650. Default 30. | `30` | `KeepDays` or `KEEP_DAYS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\new-problem-report.ps1 -Description "Outlook closes when I open a PDF"
Saves a report zip for the signed-in user's PC.
```

```powershell
.\new-problem-report.ps1 -EventMinutes 60 -OutputFormat Json
A report with an hour of errors, as JSON.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Description`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Problem report problem-report-DESK-014-20261118-091500.zip saved (3 app errors); sent to the webhook
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\new-problem-report.log`.

## Changelog

- 1.0.0 2026-11-18 First version.

## More

Full page: https://mspoutpost.com/scripts/new-problem-report

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
