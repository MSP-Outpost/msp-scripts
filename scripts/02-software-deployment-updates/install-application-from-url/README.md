# Install an application from a URL, verified

> Downloads an .msi or .exe installer over HTTPS, checks it, installs it silently and verifies the install.

| | |
|---|---|
| Script | `install-application-from-url.ps1` |
| Type | Action |
| Category | Software deployment & updates |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, internet access to the URL |
| Changes | Downloads an installer to a temporary folder, runs it, then deletes it |
| Risk | Low |
| Reboot | May |
| Typical runtime | 1 to 10 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS. It downloads the installer at Url into a temporary folder under %ProgramData%\MSPOutpost\Downloads (3 tries), checks it, runs it silently, optionally checks that the application is now listed as installed, and deletes the download. It installs only what you point it at, and never uninstalls or changes any other software.

The file is never run until it is verified, one of two ways:

- Sha256 is set: the download must match that SHA-256 exactly.
- Sha256 is empty: the file must carry a valid Authenticode signature whose publisher is one of TrustedPublishers. With neither, the script refuses before it downloads anything.

Only https:// is accepted, and a redirect to a plain http:// address is refused. The file type is read from the downloaded bytes (a Windows Installer package or a program), not from the URL.

An .msi is run with msiexec /i and, unless Arguments already holds a /q switch, /qn /norestart. An .exe needs Arguments with its silent switches (for example /S, /VERYSILENT /NORESTART or /quiet /norestart). Exit codes in SuccessCodes count as success; 3010 and 1641 mean a reboot is needed, which the script reports and does not do.

When DetectName is set and an installed application matching it is already listed, the script does nothing and says so (so the same job can run on a schedule). After a real install it must find that application, or it ends in ERROR.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Url` | The https:// address of the installer. Required. | (empty) | `Url` or `URL` |
| `Sha256` | The expected SHA-256 of the file, 64 hex characters, from the vendor. Required unless TrustedPublishers is set. Default empty. | (empty) | `Sha256` or `SHA256` |
| `TrustedPublishers` | Used only when Sha256 is empty: a list (comma or semicolon) of publisher names. The file must be validly signed and the signing certificate's name (CN) or organisation (O) must equal one of them, for example "Igor Pavlov". Default empty. | (empty) | `TrustedPublishers` or `TRUSTED_PUBLISHERS` |
| `Arguments` | Silent switches for the installer. For an .msi the default is /qn /norestart. Required for an .exe. Default empty. | (empty) | `Arguments` or `ARGUMENTS` |
| `SuccessCodes` | Exit codes that mean success. Default 0,3010,1641. | `0,3010,1641` | `SuccessCodes` or `SUCCESS_CODES` |
| `DetectName` | Name of the application as shown in Apps & features; * and ? work, and a name without a wildcard matches anywhere in the name. Skips the install when already present and verifies it afterwards. Default empty. | (empty) | `DetectName` or `DETECT_NAME` |
| `TimeoutMinutes` | How long to wait for the installer. Whole number, 1 to 480. Default 30. | `30` | `TimeoutMinutes` or `TIMEOUT_MINUTES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\install-application-from-url.ps1 -Url https://www.7-zip.org/a/7z2600-x64.msi -Sha256 c388d0444871ca11b21237001af158cfddad7e137851795e5b65cee69b518495 -DetectName 7-Zip
```

Installs 7-Zip from the vendor file after checking its hash, unless 7-Zip is already installed.

```powershell
.\install-application-from-url.ps1 -Url https://example.com/setup.exe -TrustedPublishers "Example Corp" -Arguments "/S"
```

Installs a signed program, only when it is signed by Example Corp.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Url`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Installed 7-Zip 26.00 (x64 edition) from www.7-zip.org; reboot needed
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\install-application-from-url.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/install-application-from-url

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
