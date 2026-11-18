# Which browser extensions are installed?

> Lists the browser extensions installed for every user: Chrome, Edge, Brave and Firefox.

| | |
|---|---|
| Script | `get-browser-extensions.ps1` |
| Type | Report |
| Category | Browser & application config |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1; administrator rights |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It looks in every local user's profile folder (not only the signed-in user) and lists each installed extension with its ID, name and version:

- Chrome, Edge and Brave: every browser profile's Extensions folder. The newest installed version of each extension is read from its manifest.json. A name written as __MSG_appName__ is looked up in the extension's own _locales folder (the manifest's default locale, then English, then any locale), because that is how most extensions name themselves.
- Firefox: each profile's extensions.json. Themes, dictionaries, language packs and Firefox's built-in add-ons are left out.

Extensions that an organisation forces on a browser through policy are listed too once they are installed (they live in the same folders). Only extensions on disk are seen: a browser that has never been opened by a user, or a profile on a roaming or cloud drive, has none. Browsers other than the four above (Opera, Vivaldi, Arc) are not read. Needs administrator rights.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `NameMatch` | Only list extensions whose name or ID contains one of these words (not case sensitive; separate several with commas or semicolons). Each word must be at least 3 characters and is matched as plain text, no wildcards. Default: empty, list every extension. | (empty) | `NameMatch` or `NAME_MATCH` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-browser-extensions.ps1 -ExportPath C:\Temp\extensions.csv
```

Lists every extension for every user and saves the list.

```powershell
.\get-browser-extensions.ps1 -NameMatch "vpn,coupon,ai"
```

Lists only extensions whose name or ID contains vpn, coupon or ai.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `NameMatch`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
48 extensions in 7 browser profiles for 3 users
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `User`, `Browser`, `Profile`, `ExtensionId`, `Name`, `Version`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/get-browser-extensions

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
