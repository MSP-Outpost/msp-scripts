# New PC full of junk apps - Windows 11 debloat (safe MSP profile)

> Removes preinstalled consumer apps (Candy Crush, TikTok, Clipchamp and similar) from a Windows 10/11 PC, for every user and for new users.

| | |
|---|---|
| Script | `remove-windows-bloatware.ps1` |
| Type | Action |
| Category | Onboarding & provisioning |
| Platforms | Windows 10, Windows 11 |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, the Appx and Dism modules (not on Server Core) |
| Changes | Removes listed consumer Appx packages for all users and from the Windows image; optionally sets one policy value |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | 1 to 5 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=remove-windows-bloatware`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\remove-windows-bloatware.log`.
- Before it edits or deletes configuration, it copies it to `%ProgramData%\MSPOutpost\Backups\remove-windows-bloatware\<UTC time>\` and keeps the last 10 runs. If a backup fails, nothing is changed.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. It removes a fixed, safe list of consumer apps twice: from every existing user profile (Remove-AppxPackage -AllUsers) and from the Windows image (Remove-AppxProvisionedPackage), so users created later do not get them back. Optionally it also sets one documented policy that stops Windows installing promoted apps.

The default list: Candy Crush and other King games, Spotify, Disney+, TikTok, Prime Video, Clipchamp, Bing News, Weather, Finance and Sports, Solitaire Collection, People, Feedback Hub, Groove Music and Movies and TV (Zune), Mixed Reality Portal, 3D Builder, 3D Viewer, Print 3D, Tips (Get Started) and Skype. Note that on Windows 11 "Microsoft.ZuneMusic" is also the Media Player app; add it to KeepApps to keep it. Xbox apps are on the list only when RemoveXbox is true, Phone Link only when RemovePhoneLink is true.

It NEVER touches (whatever ExtraApps says): Microsoft Store, App Installer (winget), Calculator, Photos, Notepad, Terminal, Paint, Snipping Tool, Edge, Teams, Outlook, Office, OneDrive, Company Portal, Windows Security, any framework or runtime package (VCLibs, .NET Native, UI.Xaml, Windows App Runtime, image and video codecs), anything Windows marks as non-removable or as a system app, and anything under Microsoft.Windows.* or MicrosoftWindows.*. A name in ExtraApps that falls under that protection is skipped with a warning.

Before the first change the script saves the list of every package it will remove (name, full name, version, install folder) to %ProgramData%\MSPOutpost\Backups\remove-windows-bloatware\<time>\removed-apps.csv, so an app can be put back (Add-AppxPackage -Register, or the Store).

A change is counted per app (its image copy and its user copies are one change) plus one for the policy. The default list is about 21 apps, within the default MaxChanges of 25 for a High-risk script. With many ExtraApps or RemoveXbox, set MaxChanges to the number the dry run plans (its warning says it).

A High-risk Action: it only lists what it would do until BOTH DryRun=false AND Approve=remove-windows-bloatware are set. Run it again afterwards: it says "Nothing to remove". Removing an app that a user has open closes that app. Windows can bring a removed app back with a feature update; run the script again after one.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `RemoveXbox` | true also removes the Xbox app, the Xbox Game Bar overlay and the Gaming app. The Xbox identity and Gaming Services packages stay. Default false. | `false` | `RemoveXbox` or `REMOVE_XBOX` |
| `RemovePhoneLink` | true also removes Phone Link (Microsoft.YourPhone). Default false. | `false` | `RemovePhoneLink` or `REMOVE_PHONE_LINK` |
| `DisableConsumerFeatures` | true sets the policy "Turn off Microsoft consumer experiences" (HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent DisableWindowsConsumerFeatures = 1), so Windows stops installing promoted apps for new users. Microsoft applies this policy on Enterprise and Education editions only; on Pro it is stored but has no effect. The key is exported to the backup folder first. Default false. | `false` | `DisableConsumerFeatures` or `DISABLE_CONSUMER_FEATURES` |
| `ExtraApps` | More package names to remove, a list separated by comma or semicolon. The - and ? wildcards work on the package Name (for example Microsoft.Bing*, ContosoPromo.*). At least 3 characters besides wildcards. Never overrides the protected list. Default empty. | (empty) | `ExtraApps` or `EXTRA_APPS` |
| `KeepApps` | Package names to keep even though they are on the list (wildcards work), for example Microsoft.ZuneMusic or Microsoft.Bing*. Default empty. | (empty) | `KeepApps` or `KEEP_APPS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\remove-windows-bloatware.ps1
```

Dry run: lists every app it would remove and how many changes that is.

```powershell
.\remove-windows-bloatware.ps1 -DryRun false -Approve remove-windows-bloatware -KeepApps Microsoft.ZuneMusic
```

Removes the listed apps for all users and from the image, except Media Player.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `RemoveXbox`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `remove-windows-bloatware`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Removed 14 app(s) for all users and 15 from the image; kept 1 by KeepApps
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\remove-windows-bloatware.log`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/remove-windows-bloatware

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
