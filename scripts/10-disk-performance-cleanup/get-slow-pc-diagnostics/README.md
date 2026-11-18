# PC is slow - slow-PC first aid diagnostic

> One-shot "this PC is slow" check: CPU, memory, disk, startup load, updates, power plan, crashes and antivirus.

| | |
|---|---|
| Script | `get-slow-pc-diagnostics.ps1` |
| Type | Report |
| Category | Disk, performance & cleanup |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1; administrator rights |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | About 15 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It collects, in about 15 seconds, the facts a technician checks first when a user says the PC is slow, one row each with a plain-language concern when something looks wrong:

- uptime, CPU now and memory now (3 samples, one second apart),
- the top 5 programs by CPU and by memory (processes of the same name, such as every Chrome process, are added together),
- free space on each fixed drive, how busy the disks are (busy time and queue length), and whether Windows is on a hard disk instead of an SSD,
- how many programs start at sign-in: Run keys (this PC and signed-in users), Startup folders, and scheduled tasks that run at logon (Microsoft's own tasks are not counted),
- a restart waiting for Windows Update, the active power plan, and whether the CPU is running well below its top speed under load,
- the last blue screen in the System log (last 30 days count as a concern),
- whether Defender is scanning or using a lot of CPU, and how many antivirus products are active (two slow a PC badly).

The answer lists the three most important concerns, worst first, or says no obvious cause was found. The table has every check so you can see what was normal. Startup entries that a user switched off in Task Manager are still counted, because Windows keeps that switch somewhere this script does not read. Needs administrator rights.

## Inputs

This script has no inputs of its own. The [standard inputs](#standard-inputs) below still apply.

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-slow-pc-diagnostics.ps1
```

Prints every check with its concerns and a one-line answer.

```powershell
.\get-slow-pc-diagnostics.ps1 -OutputFormat Json -ExportPath C:\Temp\slow-pc.json
```

The same as JSON, also saved to a file.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `OutputFormat`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
3 concerns: memory 6% available; C: has 8% free; up 41 days - restart it
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Check`, `Value`, `Concern`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/get-slow-pc-diagnostics

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
