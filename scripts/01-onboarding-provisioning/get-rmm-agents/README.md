# Which other RMM agents are on this PC

> Lists the other RMM and remote-management agents installed on this PC.

| | |
|---|---|
| Script | `get-rmm-agents.ps1` |
| Type | Report |
| Category | Onboarding & provisioning |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1 |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 15 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It looks for about 25 RMM, endpoint-management and remote-management agents (Datto RMM, NinjaOne, N-able N-central and N-sight, Kaseya, ConnectWise Automate and RMM, Atera, Syncro, Tactical RMM, Action1, Pulseway, Level, SuperOps, ManageEngine, Naverisk, ImmyBot, GoTo Resolve, Xcitium and more) in three places: Windows services, the installed-programs list (HKLM, 64-bit and 32-bit) and program folders.

A product counts as installed when it has a service or an installed-programs entry. A program folder on its own is reported as a leftover and is not counted. Microsoft Intune's management extension is listed as "Microsoft (MDM)".

Use it before onboarding a client to see which tool the old provider left behind, and after a migration to prove the old agent is gone.

ResultField receives the product names as a comma list, or "None".

## Inputs

This script has no inputs of its own. The [standard inputs](#standard-inputs) below still apply.

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-rmm-agents.ps1
```

Prints one row per RMM agent found, then the one-line answer.

```powershell
.\get-rmm-agents.ps1 -OutputFormat Json
```

Prints one JSON object with the rows.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `OutputFormat`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
2 RMM agents: Datto RMM, ScreenConnect
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Product`, `Evidence`, `Version`, `ServiceState`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/get-rmm-agents

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
