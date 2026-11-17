# Unapproved remote-access tool installed

> Alerts when a remote-access tool that is not on your allowed list is installed or running.

| | |
|---|---|
| Script | `test-unapproved-remote-tools.ps1` |
| Type | Monitor |
| Category | Security hardening & compliance |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1 |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It looks for about 28 remote-access tools (AnyDesk, TeamViewer, Splashtop, RustDesk, LogMeIn, GoTo Resolve, Chrome Remote Desktop, ScreenConnect, the VNC family, Zoho Assist, BeyondTrust, Parsec, NoMachine, Ammyy, SimpleHelp, MeshCentral, NetSupport and more) in Windows services, the installed-programs list, program folders and running processes, and alerts (exit 1) when any of them is not matched by AllowedTools. Installed OR running is enough: a tool that is only running from a download counts.

Unless SearchPortable is false it also looks for portable copies and downloaded installers by file name in every user's Downloads, Desktop, Documents and AppData folders (a fixed list of folders, a few levels deep, files up to 300 MB). A portable copy that was never run still alerts.

A program folder with no service, installed-programs entry or running process is a leftover of an uninstall: it is listed but never alerts.

Some products install another tool on purpose: Tactical RMM installs MeshCentral's agent and Atera installs Splashtop. MSPs who use those products must list MeshCentral or Splashtop in AllowedTools.

Every tool found is a row, allowed or not. The report twin is get-remote-access-tools.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `AllowedTools` | The tools you use yourself, separated by commas, e.g. "ScreenConnect, TeamViewer". Wildcards work. Matched against the Tool column of the table. Default none: every remote tool alerts. | (empty) | `AllowedTools` or `ALLOWED_TOOLS` |
| `SearchPortable` | true to also search user folders for portable copies and installers. Default true. | `true` | `SearchPortable` or `SEARCH_PORTABLE` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-unapproved-remote-tools.ps1 -AllowedTools "ScreenConnect"
```

Alerts on every remote tool except ScreenConnect.

```powershell
.\test-unapproved-remote-tools.ps1 -SearchPortable false -OutputFormat Json
```

Checks services, programs, folders and processes only, and prints one JSON object.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `AllowedTools`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
2 unapproved remote-access tool(s): AnyDesk, TeamViewer
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Tool`, `Evidence`, `Path`, `Running`, `AsService`, `Allowed`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-unapproved-remote-tools

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
