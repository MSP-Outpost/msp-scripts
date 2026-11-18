# Who can open this folder - NTFS and share permissions

> Lists who can open a folder: the NTFS permissions of the folder and its subfolders, plus its share permissions.

| | |
|---|---|
| Script | `get-folder-permissions.ps1` |
| Type | Report |
| Category | Inventory, reporting & audit |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute for 500 folders |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. It reads the NTFS access control list of FolderPath and of every subfolder down to Depth levels, and writes one row per permission entry (ACE). When the folder is shared, or sits inside a shared folder, it also writes one row per SMB share permission entry.

Each row says who (Identity), allow or deny (Type), what (Rights), whether the entry is inherited from the parent folder, and what it applies to. InheritanceBroken is true on a folder that no longer inherits from its parent (an administrator turned inheritance off there).

The Flag column is filled for the two entries that are almost always a mistake: Everyone or Authenticated Users with Allow and full control, on the folder or on the share. A subfolder with inheritance turned off is also flagged; the starting folder is not, because a share root is normally set up that way. Everyone and Authenticated Users are recognised by SID, so it works on any Windows language.

Junctions and symbolic links are not followed, so a loop cannot occur. The run stops after MaxFolders folders and says so in a warning. Folders it cannot read are listed in warnings, not as errors. No Active Directory is needed: it works on any Windows PC or server.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `FolderPath` | The folder to report on, e.g. D:\Shares\Finance. Required. (Named FolderPath, not Path: Windows already has an environment variable called Path, which the runtime would read instead.) | (empty) | `FolderPath` or `FOLDER_PATH` |
| `Depth` | How many levels of subfolders to include below FolderPath. Whole number, 0 to 20. Default 2 (0 = only the folder itself). | `2` | `Depth` or `DEPTH` |
| `MaxFolders` | The most folders to read, so a huge tree cannot produce a huge report. Whole number, 1 to 100000. Default 500. | `500` | `MaxFolders` or `MAX_FOLDERS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-folder-permissions.ps1 -FolderPath D:\Shares\Finance
```

Lists the NTFS and share permissions of the folder and two levels below it.

```powershell
.\get-folder-permissions.ps1 -FolderPath D:\Shares -Depth 1 -ExportPath C:\Temp\shares.csv
```

Exports every entry on D:\Shares and its direct subfolders to a CSV file.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `FolderPath`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Listed 38 permission entries on 12 folder(s) under D:\Shares\Finance (depth 2); 2 flagged
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Source`, `Path`, `Identity`, `Type`, `Rights`, `Inherited`, `AppliesTo`, `InheritanceBroken`, `Flag`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/get-folder-permissions

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
