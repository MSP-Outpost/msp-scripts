# Run a command as the logged-in user (from SYSTEM)

> Runs a PowerShell snippet in the signed-in user's own session from SYSTEM and returns what it printed and its exit code.

| | |
|---|---|
| Script | `invoke-as-logged-in-user.ps1` |
| Type | Action |
| Category | Utility / misc |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, a signed-in user |
| Changes | Runs the supplied PowerShell code in the signed-in user's session; what it changes depends on that code |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | Seconds, up to TimeoutSeconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=invoke-as-logged-in-user`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\invoke-as-logged-in-user.log`.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS, and what it changes is whatever your code does. It finds the user signed in at the console (or in an RDP session with an Explorer shell), runs your PowerShell code in that user's interactive session through a one-shot scheduled task, waits for it, and prints the code's output (up to 40 lines) as the rows of the result. The code runs with that user's rights only (never elevated, never SYSTEM), sees that user's HKCU, profile and mapped drives, and has no visible window.

If nobody is signed in the result is SKIPPED and nothing runs. An exit code other than 0 from the code, or an error thrown by it, ends the run as ERROR with the first line of the output in the answer. A code that runs longer than TimeoutSeconds is stopped and the run ends as ERROR.

This is a High-risk script because this script cannot know what the code does: it can delete the user's files or change their settings. It is a dry run (it checks the user and reports what it would run) until BOTH DryRun=false AND Approve=invoke-as-logged-in-user are set, so one site-wide DryRun=false variable can never unlock it. A run counts as one change.

What is logged. The code itself is NEVER written to the change log, the result, the Json output or an error message, because snippets often hold paths, names or tokens. The change log line holds only the user, the length of the code in characters and the first 12 characters of its SHA-256 (to tell two snippets apart). The code is written to a folder that only SYSTEM, Administrators and that user can read for the seconds it runs, then deleted; do not put secrets in it all the same. The code's OUTPUT is shown in the result rows and may reach your RMM's job history: do not print secrets.

Giving the code. Code takes the snippet as text. Many RMMs refuse characters that PowerShell needs ($ ; | & > < and the backtick), so CodeBase64 takes the same snippet as UTF-8 Base64 instead. Set one of them, not both. To make Base64 in PowerShell: [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('whoami'))

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Code` | The PowerShell snippet to run, as text. Up to 50000 characters. | (empty) | `Code` or `CODE` |
| `CodeBase64` | The same snippet as UTF-8 Base64 text, for RMMs that cannot pass the characters PowerShell needs. | (empty) | `CodeBase64` or `CODE_BASE64` |
| `TimeoutSeconds` | How long to let the code run before it is stopped. Whole number, 5 to 600. Default 120. | `120` | `TimeoutSeconds` or `TIMEOUT_SECONDS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\invoke-as-logged-in-user.ps1 -Code "whoami"
```

Dry run: names the signed-in user and what it would run; runs nothing.

```powershell
.\invoke-as-logged-in-user.ps1 -DryRun false -Approve invoke-as-logged-in-user -Code "Get-Process | Select-Object -First 3"
```

Runs the code as the signed-in user and prints its output.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Code`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `invoke-as-logged-in-user`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Ran code as CONTOSO\jsmith: exit 0, 3 output line(s)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\invoke-as-logged-in-user.log`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/invoke-as-logged-in-user

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
