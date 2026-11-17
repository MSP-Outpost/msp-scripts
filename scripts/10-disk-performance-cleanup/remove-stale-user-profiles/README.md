# Shared PC full of ex-staff profiles - remove stale profiles

> Removes Windows user profiles that nobody has used for MinAgeDays days, keeping admins, service accounts and anyone you exclude.

| | |
|---|---|
| Script | `remove-stale-user-profiles.ps1` |
| Type | Action |
| Category | Disk, performance & cleanup |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | Deletes unused user profiles: the profile folder and its registry entry |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | 1 to 15 minutes, depending on profile size |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=remove-stale-user-profiles`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\remove-stale-user-profiles.log`.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS AND DELETES USER DATA. Risk is High, so it is a dry run unless you set BOTH DryRun=false AND Approve=remove-stale-user-profiles (typing the script name is the deliberate step), and it refuses to remove more profiles than MaxChanges (default 25) in one run. First look at the dry-run list, then run it for real.

It lists the user profiles on the PC (Win32_UserProfile) and removes each one that is unused for MinAgeDays days, with the whole profile folder (Desktop, Documents, AppData) and its registry entry, the way Windows itself deletes a profile. A removed profile cannot be recovered; the user gets a fresh one at their next sign-in. Network and OneDrive copies are not touched.

How "unused" is decided: Windows updates LastUseTime on servicing, so it is not trusted. The script takes the NEWER of the profile's NTUSER.DAT last write time and the profile load time Windows keeps in the ProfileList registry key (LocalProfileLoadTime), and falls back to LastUseTime only when neither exists. Each row says which one was used. A profile with no date at all is kept.

Only real user profiles are considered: local accounts and domain accounts (SID S-1-5-21-...) and Entra ID accounts (S-1-12-1-...). Virtual and service profiles (NT SERVICE, IIS app pools, S-1-5-80 and S-1-5-82) are never touched. Domain service accounts and gMSAs look like ordinary users: put them in ExcludeUsers.

Never removed: special and system profiles, profiles that are loaded (someone is signed in or a service runs as them), the account that runs the script, Administrator (any account with RID 500), defaultuser0, anyone in ExcludeUsers, and (unless IncludeAdmins is true) every account that is a direct member of the local Administrators group. Members of a domain group that is itself an administrator group are not detected: list those users in ExcludeUsers. Only profiles stored in a folder named Users are considered.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `MinAgeDays` | Remove profiles unused for at least this many days. Whole number, 7 to 3650. Default 90. | `90` | `MinAgeDays` or `MIN_AGE_DAYS` |
| `ExcludeUsers` | Profiles to keep, as profile folder names or account names, separated by commas or semicolons; * and ? wildcards work. Default empty. | (empty) | `ExcludeUsers` or `EXCLUDE_USERS` |
| `IncludeAdmins` | true to also remove stale profiles of local administrators (Administrator and the account running the script are still kept). Default false. | `false` | `IncludeAdmins` or `INCLUDE_ADMINS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\remove-stale-user-profiles.ps1
```

Dry run: lists the profiles unused for 90 days or more and their size.

```powershell
.\remove-stale-user-profiles.ps1 -MinAgeDays 180 -ExcludeUsers "reception,kiosk*" -DryRun false -Approve remove-stale-user-profiles
```

Removes profiles unused for 180 days, except reception and kiosk accounts.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `MinAgeDays`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `remove-stale-user-profiles`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Removed 3 of 3 stale profiles; freed 41.0 GB
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\remove-stale-user-profiles.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/remove-stale-user-profiles

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
