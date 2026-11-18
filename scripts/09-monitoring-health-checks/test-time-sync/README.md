# Clock out of sync

> Alerts when the PC clock is more than MaxOffsetSeconds from a reference time server or the Windows Time service is stopped.

| | |
|---|---|
| Script | `test-time-sync.ps1` |
| Type | Monitor |
| Category | Monitoring & health checks |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, UDP port 123 to the reference server |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 20 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It checks three things, one row each:

- The Windows Time service (W32Time): running or not. A stopped service is an alert.
- The configured time source, read from the registry (HKLM\SYSTEM\ CurrentControlSet\Services\W32Time\Parameters: Type and NtpServer). Type NT5DS on a domain-joined PC means it syncs from the domain hierarchy (the domain controller), and the row says so; Type NTP means the listed NtpServer; AllSync means both; NoSync means none.
- The clock offset: it asks ReferenceServer three times with "w32tm /stripchart ... /dataonly" and reads the NUMBERS in its output (never the English text), using the middle sample by size. The alert is raised when the offset is larger than MaxOffsetSeconds, in either direction (the sign is not interpreted).

If the reference server cannot be reached (blocked UDP port 123, no internet) the run ends ERROR and says so, because the clock could not be measured; on a domain-joined PC whose firewall blocks Internet time, set ReferenceServer to a domain controller. The offset is measured, not corrected: nothing is resynchronised.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `ReferenceServer` | Host name or IP address of the time server to measure against. Letters, digits, dots, dashes and colons only. Default time.windows.com. | `time.windows.com` | `ReferenceServer` or `REFERENCE_SERVER` |
| `MaxOffsetSeconds` | Largest clock offset allowed, in seconds. Whole number, 1 to 86400. Default 60. | `60` | `MaxOffsetSeconds` or `MAX_OFFSET_SECONDS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-time-sync.ps1
```

Alerts when the clock is more than 60 seconds from time.windows.com.

```powershell
.\test-time-sync.ps1 -ReferenceServer dc01.contoso.com -MaxOffsetSeconds 5
```

Measures against a domain controller and allows 5 seconds.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `ReferenceServer`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Clock is 142.300 s from time.windows.com (limit 60 s); W32Time running; source NTP time.windows.com,0x9
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Check`, `Value`, `Pass`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-time-sync

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
