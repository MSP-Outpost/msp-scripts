# PC is slow - sustained CPU and memory pressure with top processes

> Alerts when the PC's CPU or memory is under sustained pressure, and names the processes behind it.

| | |
|---|---|
| Script | `test-cpu-memory-pressure.ps1` |
| Type | Monitor |
| Category | Disk, performance & cleanup |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1; performance counters (WMI) working |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | About SampleSeconds plus 5 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It samples total CPU use and available memory for SampleSeconds (one sample every 5 seconds, plus one at the start) and averages them. It alerts when the average CPU use is over CpuPercent, or when the lowest available memory seen is under MemoryPercent of the installed RAM.

CPU comes from the Windows performance counters through CIM (Win32_PerfFormattedData_PerfOS_Processor, instance _Total), so it is Windows' own processor-time counter (Task Manager's figure can differ a little). Available memory is the counter Win32_PerfFormattedData_PerfOS_Memory AvailableMBytes, which counts standby (cached) memory as available.

The table always lists the top 5 processes by average CPU use during the sample and the top 5 by working set (memory in use), so an alert already says who is responsible. Processes with the same name are listed one by one. CPU per process is a share of the whole PC (all cores).

A short sample is a spot check, not a trend: a spike that ends before the run starts is not seen. Schedule it often and raise SampleSeconds for machines with bursts. Needs no special rights beyond reading the counters.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `SampleSeconds` | How long to sample, in seconds. Whole number, 5 to 300. Default 30. One sample every 5 seconds, plus one at the start. | `30` | `SampleSeconds` or `SAMPLE_SECONDS` |
| `CpuPercent` | Alert when the average CPU use over the sample is above this percent. Whole number, 0 to 100. Default 90. | `90` | `CpuPercent` or `CPU_PERCENT` |
| `MemoryPercent` | Alert when available memory dropped below this percent of installed RAM during the sample. Whole number, 1 to 99. Default 10. | `10` | `MemoryPercent` or `MEMORY_PERCENT` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-cpu-memory-pressure.ps1
```

Samples for 30 seconds; alerts above 90% CPU or below 10% available memory.

```powershell
.\test-cpu-memory-pressure.ps1 -SampleSeconds 120 -CpuPercent 80 -MemoryPercent 15
```

A longer sample with tighter limits.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `SampleSeconds`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
CPU 96% average over 30 s (limit 90%); memory 8% available (limit 10%); top CPU: chrome 41%, MsMpEng 22%
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Check`, `Item`, `Value`, `Healthy`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-cpu-memory-pressure

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
