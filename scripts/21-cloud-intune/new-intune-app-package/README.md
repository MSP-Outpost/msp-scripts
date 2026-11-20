# Package an app for Intune - build the .intunewin file

> Packages an installer folder into an Intune .intunewin file with Microsoft's Win32 Content Prep Tool (IntuneWinAppUtil.exe).

| | |
|---|---|
| Script | `new-intune-app-package.ps1` |
| Type | Action |
| Category | Cloud & Intune |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | Either |
| Requires | PowerShell 5.1; Microsoft's IntuneWinAppUtil.exe on this computer; read access to the installer folder |
| Changes | Writes one .intunewin file under OutputFolder; nothing is uploaded to Intune |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 5 minutes (longer for large installers) |
| Version | 1.0.0 |
| Updated | 2026-11-18 |

## What it does

THIS SCRIPT CHANGES THINGS, ON THIS COMPUTER ONLY. It runs Microsoft's IntuneWinAppUtil.exe on a folder of installer files and writes the resulting .intunewin file to OutputFolder (created when missing; an existing .intunewin of the same name is overwritten, as Microsoft's page says the tool does). It reads SourceFolder and never changes it. It does NOT talk to Microsoft Graph or Intune: uploading the .intunewin, and the detection rules, requirements and return codes of the Win32 app, are the next step (in the Intune admin center, or a separate script).

THE TOOL IS NOT DOWNLOADED. Set IntuneWinAppUtilPath to a copy you already have. Microsoft publishes the tool as a ZIP of the repository (Microsoft-Win32-Content-Prep-Tool-master, reached from https://go.microsoft.com/fwlink/?linkid=2065730); its GitHub release page (tag v1.8.7, 2025-08-13) lists no downloadable assets and no checksum, so there is no published SHA256 to pin and this script will not fetch anything. Keep the tool OUTSIDE SourceFolder: the tool zips every file and subfolder of the source folder, so the script refuses a tool that sits inside it. Because the tool runs as SYSTEM from an RMM, the script also checks the file's Authenticode signature is valid and issued to Microsoft, and refuses it otherwise unless AllowUnsignedTool is true.

If OutputFolder already holds a .intunewin newer than every file in SourceFolder, the script says so and does nothing, unless Rebuild is true.

Where each fact comes from (Microsoft's Win32 prepare page): the command line IntuneWinAppUtil -c <setup_folder> -s <setup_file> -o <output_folder> [-q]; all files in the setup folder are compressed into the .intunewin file; the output folder is created if it does not exist; an existing output file is overwritten; a setup file inside the folder is given as a path in it; the tool must stay apart from the installer files. Not confirmed in Microsoft's documentation, so read defensively: the tool's exit codes (any non-zero status, or no new .intunewin file, is treated as a failure), the output file's name (the script takes the newest .intunewin that appears in OutputFolder during the run; it is normally the setup file's name with .intunewin) and that Microsoft signs IntuneWinAppUtil.exe (hence AllowUnsignedTool).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `SourceFolder` | Folder holding all the installer files. Required. | (empty) | `SourceFolder` or `SOURCE_FOLDER` |
| `SetupFile` | The setup file (for example setup.exe or app.msi), as a path inside SourceFolder or just its name. Required. | (empty) | `SetupFile` or `SETUP_FILE` |
| `IntuneWinAppUtilPath` | Full path of IntuneWinAppUtil.exe on this computer, outside SourceFolder. Required (the script downloads nothing). | (empty) | `IntuneWinAppUtilPath` or `INTUNE_WIN_APP_UTIL_PATH` |
| `OutputFolder` | Where the .intunewin file is written. Default: the IntuneWin folder under the MSP Outpost data folder (ProgramData\MSPOutpost\IntuneWin). | (empty) | `OutputFolder` or `OUTPUT_FOLDER` |
| `Rebuild` | true packages again even if an up-to-date .intunewin is already in OutputFolder. Default false. | `false` | `Rebuild` or `REBUILD` |
| `AllowUnsignedTool` | true runs a tool whose signature is not a valid Microsoft one. Default false. | `false` | `AllowUnsignedTool` or `ALLOW_UNSIGNED_TOOL` |
| `TimeoutMinutes` | Stop the tool and fail after this many minutes. Whole number, 1 to 240. Default 30. | `30` | `TimeoutMinutes` or `TIMEOUT_MINUTES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\new-intune-app-package.ps1 -SourceFolder C:\Packages\7zip -SetupFile 7z2501-x64.msi -IntuneWinAppUtilPath C:\Tools\IntuneWinAppUtil.exe
Builds 7z2501-x64.intunewin into the MSP Outpost data folder.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `SourceFolder`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Packaged 7z2501-x64.msi into 7z2501-x64.intunewin (2 MB) in C:\ProgramData\MSPOutpost\IntuneWin; upload it to Intune next
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\new-intune-app-package.log`.

## Changelog

- 1.0.0 2026-11-18 First version.

## More

Full page: https://mspoutpost.com/scripts/new-intune-app-package

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
