# Download a file safely - https, SHA-256 check, size limit

> Downloads a file from an https address to a path, checks its SHA-256, and only then puts it in place.

| | |
|---|---|
| Script | `invoke-file-download.ps1` |
| Type | Action |
| Category | Utility / misc |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, outbound https |
| Changes | Creates (or, with Overwrite, replaces) one file at DestinationPath and its folder; leaves no temporary files |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Seconds to minutes, by file size |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT CHANGES THINGS. It downloads Url to DestinationPath. It never runs, opens or unpacks what it downloads.

How a download is made safe:

- https only. A redirect to anything but https is refused, and so is an address with a user name or password in it.
- It will not download without a way to check the file: ExpectedSha256 is required. Only AllowUnverified=true downloads without one, and then the result says NOT verified and prints the file's SHA-256 so you can pin it.
- MaxSizeMB is enforced twice: from the server's announced size before any data is saved, and while streaming when the size is not announced.
- The file is saved to a temporary file in the destination folder, its SHA-256 is compared, and only a match is moved into place in one step. A failed or mismatched download leaves nothing behind and the existing file untouched.
- An existing file is never replaced unless Overwrite=true, and then a copy of it is saved to %ProgramData%\MSPOutpost\Backups\invoke-file-download first. If the existing file already has the SHA-256 you expect, nothing is downloaded and the run says it is already in place.

It tries up to 3 times on network errors and server errors (not on 4xx replies, size, redirect or hash problems). Query strings (which can carry access tokens) are never printed or logged: only the host and path.

It refuses a destination inside the Windows folder or the MSP Outpost data folder, a UNC path, a relative path, and a folder name instead of a file. A missing destination folder is created.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Url` | The https address to download. Required. | (empty) | `Url` or `URL` |
| `DestinationPath` | Full path of the file to create, for example C:\Temp\agent.msi. The folder is created if needed. Required. | (empty) | `DestinationPath` or `DESTINATION_PATH` |
| `ExpectedSha256` | The SHA-256 the file must have: 64 hexadecimal characters, any case. Take it from the vendor. Required unless AllowUnverified is true. | (empty) | `ExpectedSha256` or `EXPECTED_SHA256` |
| `AllowUnverified` | true downloads without a hash to check (the file cannot be proven to be the one you meant). true or false. Default false. | `false` | `AllowUnverified` or `ALLOW_UNVERIFIED` |
| `MaxSizeMB` | Refuse a file bigger than this many megabytes. Whole number, 1 to 10240. Default 500. | `500` | `MaxSizeMB` or `MAX_SIZE_MB` |
| `Overwrite` | true replaces an existing file at DestinationPath (after backing it up). Default false. | `false` | `Overwrite` or `OVERWRITE` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\invoke-file-download.ps1 -Url https://vendor.example/agent.msi -DestinationPath C:\Temp\agent.msi -ExpectedSha256 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

Downloads the file, checks the hash and moves it into C:\Temp.

```powershell
.\invoke-file-download.ps1 -Url https://vendor.example/tool.zip -DestinationPath C:\Temp\tool.zip -AllowUnverified true -MaxSizeMB 50
```

Downloads without a hash and prints the SHA-256 it found, so you can pin it.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Url`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Downloaded 12.4 MB from vendor.example to C:\Temp\agent.msi; SHA-256 matched
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\invoke-file-download.log`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/invoke-file-download

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
