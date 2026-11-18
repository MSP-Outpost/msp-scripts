# OneDrive not syncing - health and Known Folder Move monitor

> Alerts when OneDrive is set up for the signed-in user but not running, or Known Folder Move is required and missing.

| | |
|---|---|
| Script | `test-onedrive-sync.ps1` |
| Type | Monitor |
| Category | User profile & desktop config |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, a signed-in user (the probe runs in their session) |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It looks at OneDrive as the signed-in user sees it, by running a short read-only probe in that user's session (the user's own registry and folders, not SYSTEM's):

- whether OneDrive.exe is running in the user's session,
- which accounts are signed in (a key counts only with a UserEmail) (HKCU\Software\Microsoft\OneDrive\Accounts: Business1 ... and Personal; the e-mail, the OneDrive folder and, for work or school accounts, the tenant ID),
- where Desktop, Documents and Pictures live, and whether each sits inside a OneDrive folder (Known Folder Move, "KFM"),
- the last sync progress OneDrive wrote to its own SyncDiagnostics.log, shown as the raw SyncProgressState number and the file time. It is information only and never raises an alert: OneDrive does not document the number.

ALERT when an account is signed in but OneDrive is not running, or when RequireKfm is true and one of KfmFolders is not redirected into OneDrive (including when no account is signed in at all).

SKIPPED when nobody is signed in, or when RequireKfm is false and no OneDrive account is set up for the user (nothing to monitor).

It checks the console user. On a PC where several people are signed in (a terminal server) only that session is looked at.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `RequireKfm` | true to alert when a folder in KfmFolders is not inside the user's OneDrive folder. Default false. | `false` | `RequireKfm` or `REQUIRE_KFM` |
| `KfmFolders` | Folders that must be redirected when RequireKfm is true: any of Desktop, Documents, Pictures, separated by commas. Default Desktop,Documents. | `Desktop,Documents` | `KfmFolders` or `KFM_FOLDERS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-onedrive-sync.ps1
```

Alerts if a signed-in OneDrive account is not running.

```powershell
.\test-onedrive-sync.ps1 -RequireKfm true -KfmFolders Desktop,Documents,Pictures
```

Also alerts when any of the three folders is not backed up to OneDrive.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `RequireKfm`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
OneDrive running; 1 account (anna@contoso.com); Known Folder Move: Desktop, Documents in OneDrive
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Check`, `Value`, `Problem`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-onedrive-sync

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
