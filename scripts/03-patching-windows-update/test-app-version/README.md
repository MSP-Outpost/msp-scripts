# Is a vulnerable app version installed

> Alerts when an installed application, or a program file, is older than the version you set.

| | |
|---|---|
| Script | `test-app-version.ps1` |
| Type | Monitor |
| Category | Patching & Windows Update |
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

THIS SCRIPT IS READ-ONLY. It answers "which machines still run a vulnerable version?". It looks up the applications whose name matches Name in the machine-wide installed-programs list (64-bit and 32-bit) and compares each one's version with MinimumVersion. When FilePath is set it also reads that file's version (for example chrome.exe) and compares it the same way, which finds per-user and portable installs the list does not show.

Versions are compared number by number as up to four parts, so 1.10 is newer than 1.9. Text around a version ("v23.01 beta") is ignored; a version with more than four parts is cut to four. An application whose version cannot be read at all counts as a problem, because it cannot be shown to be safe.

ALERT: at least one match is below MinimumVersion (or unreadable). OK: every match is at or above it, or nothing is installed (the answer says which). A Name with fewer than 3 letters outside wildcards is refused so one run cannot match everything.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Name` | Application name as shown in Apps & features; * and ? work, and a name without a wildcard matches anywhere in the name. Set Name, FilePath or both. Default empty. | (empty) | `Name` or `NAME` |
| `MinimumVersion` | The first safe version, such as 126.0.6478.55. Numbers separated by dots. Required. | (empty) | `MinimumVersion` or `MINIMUM_VERSION` |
| `FilePath` | A program file whose file version is also checked, for example C:\Program Files\Google\Chrome\Application\chrome.exe. Environment variables such as %ProgramFiles% are expanded; note that %LOCALAPPDATA%, %APPDATA% and %USERPROFILE% are SYSTEM's own profile when this runs from an RMM, not a user's. To check every user's copy write {USERPROFILES} (capitals), for example {USERPROFILES}\AppData\Local\Google\Chrome\Application\chrome.exe: the path is tried once for each folder under C:\Users. A file that does not exist counts as not installed. Default empty. | (empty) | `FilePath` or `FILE_PATH` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-app-version.ps1 -Name "7-Zip" -MinimumVersion 24.07
```

Alerts when any installed 7-Zip is older than 24.07.

```powershell
.\test-app-version.ps1 -Name "Google Chrome" -MinimumVersion 126.0.6478.55 -FilePath "C:\Program Files\Google\Chrome\Application\chrome.exe"
```

Checks the installed-programs entry and the chrome.exe file version.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Name`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
7-Zip 23.01 is below the minimum 24.07 (1 of 1 checked)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Item`, `Source`, `Version`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-app-version

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
