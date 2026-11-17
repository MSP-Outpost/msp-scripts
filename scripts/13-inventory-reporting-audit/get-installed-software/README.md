# Installed software inventory and app finder

> Lists the software installed on this PC, or finds an app by name.

| | |
|---|---|
| Script | `get-installed-software.ps1` |
| Type | Report |
| Category | Inventory, reporting & audit |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It reads the "Uninstall" registry keys that Programs and Features is built from:

- the machine-wide 64-bit and 32-bit keys (HKLM),
- every signed-in user's per-user installs (HKU), and
- with IncludeSignedOutUsers true, every signed-out user's per-user installs: it loads that user's NTUSER.DAT, reads the key and unloads it again. It changes no value, but loading a hive can touch its transaction log files and a user who signs in meanwhile can get a temporary profile, so this is off by default (avoid it on RDS servers).

A registry key that cannot be read is skipped and counted in a warning; it never stops the report. It removes duplicates (same name, version and scope), skips hidden system components and, unless IncludeUpdates is true, Windows and product updates (KB entries, hotfixes, security updates). It never uses Win32_Product, which triggers MSI repairs. Microsoft Store (AppX) apps are not included.

NameMatch narrows the list: a plain word such as chrome matches any name containing it; * and ? work as wildcards. Zero matches is still OK: the answer says no installed app matches.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `NameMatch` | Only list apps whose name matches this text or wildcard, case-insensitive. Default * (all apps). | `*` | `NameMatch` or `NAME_MATCH` |
| `IncludeUpdates` | true to also list Windows and product updates (KB entries). Default false. | `false` | `IncludeUpdates` or `INCLUDE_UPDATES` |
| `IncludeSignedOutUsers` | true to also read the per-user installs of users who are signed out, by loading their NTUSER.DAT. Default false. Per-user installs of signed-in users are always read. | `false` | `IncludeSignedOutUsers` or `INCLUDE_SIGNED_OUT_USERS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-installed-software.ps1 -ExportPath C:\Temp\software.csv
```

Lists every installed app and also writes the list to a CSV file.

```powershell
.\get-installed-software.ps1 -NameMatch chrome
```

Finds Chrome (and anything else with "chrome" in its name).

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `NameMatch`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
142 apps; 3 match 'chrome'
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Name`, `Version`, `Publisher`, `InstallDate`, `Scope`, `Architecture`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/get-installed-software

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
