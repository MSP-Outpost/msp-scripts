# Windows not activated - activation status and edition

> Alerts when Windows is not activated, or is a Home edition on a business PC.

| | |
|---|---|
| Script | `test-windows-activation.ps1` |
| Type | Monitor |
| Category | Licensing & asset lifecycle |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1; the Software Protection service |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 15 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It reads the Windows licence through SoftwareLicensingProduct (the same data as slmgr /dli) and checks:

- activation: the licence status must be Licensed. Every other status (not licensed, grace period, non-genuine, notification mode, extended grace) is an alert, with the grace time left when there is one. A PC with no product key installed at all is also an alert,
- edition: Windows Home, Home N and Home Single Language cannot join a domain or be managed like a business PC, so on a PC that is meant to be a business machine the edition is a finding. Turn that check off with AlertOnHomeEdition false for a fleet where Home is expected.

The table also shows the edition, the licence channel (Retail, OEM, Volume KMS or MAK) and the last five characters of the product key. A volume licence activated by a key management server shows Licensed while it is in its 180-day renewal window; this script does not alert on the renewal countdown, only on a real failure.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `AlertOnHomeEdition` | Alert when the edition is Windows Home (any Home variant), even when it is activated. true or false. Default true. | `true` | `AlertOnHomeEdition` or `ALERT_ON_HOME_EDITION` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-windows-activation.ps1
```

Alerts when Windows is not activated or is a Home edition.

```powershell
.\test-windows-activation.ps1 -AlertOnHomeEdition false
```

Checks activation only.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `AlertOnHomeEdition`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Windows 11 Pro is activated (Volume KMS channel)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Check`, `Value`, `Healthy`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-windows-activation

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
