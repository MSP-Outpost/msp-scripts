# Outlook won't open or keeps asking for a password - rebuild the profile

> Outlook keeps asking for a password or will not open: creates a fresh Outlook profile for the signed-in user and makes it the default.

| | |
|---|---|
| Script | `repair-outlook-profile.ps1` |
| Type | Action |
| Category | Browser & application config |
| Platforms | Windows 10, Windows 11 |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, a user signed in at the console, classic Outlook |
| Changes | Creates a new Outlook profile in the signed-in user's registry and makes it the default; with CloseOutlook, closes Outlook; backs up the Outlook registry key first |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS. For the user signed in at the console, in classic Outlook (Office 2013, 2016, 2019, 2021 and Microsoft 365 apps; registry key HKCU\Software\Microsoft\Office\16.0\Outlook, or 15.0), it:

- refuses to continue if Outlook is running, unless CloseOutlook is true: then it asks Outlook to close, and stops it after CloseWaitSeconds if it is still open (unsaved drafts are lost),
- backs up the whole Outlook registry key to %ProgramData%\MSPOutpost\Backups\repair-outlook-profile,
- creates a new, empty profile named "<ProfileName> <date>" (for example "Outlook 2026-11-16") and sets it as the default profile.

It never deletes the old profile (it stays in the profile list, and the backup can restore it), never touches OST or PST files or mail data, and never starts Outlook. On its next start Outlook finds the new profile has no account and runs its automatic account setup (autodiscover), so the user may be asked to confirm their address or sign in once, and the mailbox is downloaded again into a new OST file. The old OST file is left in place and can be deleted later.

Skipped: nobody signed in; classic Outlook not set up for that user (the new Outlook for Windows has no profiles, so there is nothing to rebuild). If today's new profile already exists and is the default, it says so and changes nothing. Running as an Action twice on the same day is therefore safe; on another day it creates another profile.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `ProfileName` | Base name of the new profile; the date is added. Letters, digits, space, dot, underscore and hyphen, up to 40 characters. Default Outlook. | `Outlook` | `ProfileName` or `PROFILE_NAME` |
| `CloseOutlook` | true to close Outlook if it is running (gracefully, then forced). Default false: a running Outlook ends the run with an error. | `false` | `CloseOutlook` or `CLOSE_OUTLOOK` |
| `CloseWaitSeconds` | With CloseOutlook, how long to wait for Outlook to close by itself before stopping it. Whole number, 5 to 120. Default 30. | `30` | `CloseWaitSeconds` or `CLOSE_WAIT_SECONDS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\repair-outlook-profile.ps1 -DryRun true
```

Lists the profile it would create and whether Outlook is running.

```powershell
.\repair-outlook-profile.ps1 -CloseOutlook true -CloseWaitSeconds 45
```

Closes Outlook (forcing it after 45 seconds) and creates the new default profile.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `ProfileName`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Created Outlook profile 'Outlook 2026-11-16' and set it as default; the old profile is kept. Outlook sets up the account at its next start.
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\repair-outlook-profile.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/repair-outlook-profile

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
