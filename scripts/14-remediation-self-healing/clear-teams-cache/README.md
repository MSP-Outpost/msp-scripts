# Teams won't load - clear the Teams cache

> Clears the Microsoft Teams cache (new and classic Teams) for every user on the PC; users may need to sign in to Teams again afterwards.

| | |
|---|---|
| Script | `clear-teams-cache.ps1` |
| Type | Action |
| Category | Remediation & self-healing |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | Deletes the cache folders of new and classic Teams in each user profile; with CloseTeams, stops that user's Teams processes |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS. For every user profile under C:\Users (or only the ones in Users) it deletes the contents of these cache folders:

- new Teams: AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams
- classic Teams, inside AppData\Roaming\Microsoft\Teams: Cache, blob_storage, databases, GPUCache, IndexedDB, Local Storage, tmp, Code Cache, Service Worker\CacheStorage and Application Cache\Cache.

It never deletes the whole Teams folder, a profile, or anything else, so classic Teams keeps its settings (desktop-config.json) and backgrounds. Teams rebuilds its cache the next time the user opens it and may ask them to sign in again.

If Teams is running for a user, that user is skipped and the row says so, unless CloseTeams is true: then that user's Teams processes are stopped first (the user loses any unsent message in Teams). If the script cannot tell whether Teams is running for a user (the account name of the profile or of a Teams process cannot be read), it treats Teams as running and skips that user, even with CloseTeams. The script never starts Teams again. Users with no Teams cache are not listed.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Users` | Only these users (profile folder names or account names, separated by commas or semicolons). Default empty: every profile. | (empty) | `Users` or `USERS` |
| `CloseTeams` | true to stop a user's running Teams before clearing their cache. Default false: a user whose Teams is running is skipped. | `false` | `CloseTeams` or `CLOSE_TEAMS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\clear-teams-cache.ps1 -DryRun true
```

Lists the Teams caches it would clear and how large they are.

```powershell
.\clear-teams-cache.ps1 -Users jsmith -CloseTeams true
```

Closes jsmith's Teams and clears the cache for that user only.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Users`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Cleared Teams cache for 3 user(s), 412.6 MB
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\clear-teams-cache.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/clear-teams-cache

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
