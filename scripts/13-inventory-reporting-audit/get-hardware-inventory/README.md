# Hardware and OS inventory

> Reports the PC's make, model, serial, CPU, RAM, disks, Windows version and join state.

| | |
|---|---|
| Script | `get-hardware-inventory.ps1` |
| Type | Report |
| Category | Inventory, reporting & audit |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 20 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It reads the hardware and operating system facts that asset records need, one Property/Value row each:

- Manufacturer, model, serial number, BIOS version and date,
- CPU name, cores and logical processors, installed RAM in GB,
- each internal disk: model, size, media type (SSD, HDD, Unspecified),
- Windows edition, version, build, architecture, install date, last boot,
- domain or workgroup, Entra ID join state (from dsregcmd /status),
- TPM version.

The value written to ResultField is "<Manufacturer> <Model> <Serial>", so an RMM custom field holds a one-line asset tag. Dates are ISO 8601 in UTC. USB disks are not listed. Needs administrator rights.

## Inputs

This script has no inputs of its own. The [standard inputs](#standard-inputs) below still apply.

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-hardware-inventory.ps1
```

Prints the inventory as a table.

```powershell
.\get-hardware-inventory.ps1 -OutputFormat Json -ExportPath C:\Temp\hardware.json
```

Prints one JSON object and also writes the rows to a file.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `OutputFormat`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Dell Latitude 5440, serial 7XK2QY3; Windows 11 Pro; 16 GB RAM
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Property`, `Value`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/get-hardware-inventory

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
