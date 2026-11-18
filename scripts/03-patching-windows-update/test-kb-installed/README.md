# Is a specific Windows update installed

> Alerts when a Windows update (KB) is not installed, or Windows is below a minimum build.

| | |
|---|---|
| Script | `test-kb-installed.ps1` |
| Type | Monitor |
| Category | Patching & Windows Update |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1 |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It answers "is this fix on the machine?" two ways, and you can use either or both.

KBs: a list of update numbers such as KB5044284. A KB counts as installed when any of these shows it: Get-HotFix, the Windows Update history (its newest successful entry for that KB must be an install, not an uninstall), or the Windows servicing store (the registry packages that cumulative updates leave, which Get-HotFix often misses; a package that a newer update superseded counts as covered). Each KB is one row saying which source saw it.

MinimumBuild: the first safe Windows build as build.revision, for example 26100.4351. The script reads the build and the update revision (UBR) from the registry and alerts when the PC is below it. The numbers compare only inside one Windows release, so give the build of the release you run (a PC still on an older release is below it, which is what you want when that release is the problem).

Check cumulative updates (the monthly rollups) with MinimumBuild, not KBs: once a newer cumulative update replaces an older one, the older KB may no longer show in any source, so a fully patched PC could read "Missing". KBs suits one-off fixes such as .NET or Office security updates and out-of-band updates.

ALERT when any KB is missing or the build is too low. OK otherwise.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `KBs` | Update numbers, comma or semicolon separated, with or without the KB prefix: KB5044284,KB5043145. Set KBs, MinimumBuild or both. Default empty. | (empty) | `KBs` or `K_BS` |
| `MinimumBuild` | The lowest acceptable build.revision, for example 26100.4351. Default empty. | (empty) | `MinimumBuild` or `MINIMUM_BUILD` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-kb-installed.ps1 -KBs KB5044284,KB5043145
```

Alerts unless both updates are installed.

```powershell
.\test-kb-installed.ps1 -MinimumBuild 26100.4351
```

Alerts when Windows 11 24H2 is older than build 26100.4351.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `KBs`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Missing KB5044284; build 26100.3194 is below 26100.4351
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Check`, `Item`, `Result`, `Source`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-kb-installed

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
