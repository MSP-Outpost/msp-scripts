# Windows Firewall off or wide open - profile and port monitor

> Alerts when a Windows Firewall profile is off or allows inbound by default, or when risky ports are open to anyone.

| | |
|---|---|
| Script | `test-firewall-profiles.ps1` |
| Type | Monitor |
| Category | Security hardening & compliance |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1; NetSecurity module; administrator rights |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 20 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It checks that the Domain, Private and Public firewall profiles are all enabled and that none of them allows inbound connections by default. It then lists every enabled inbound Allow rule whose remote address is Any and whose local port covers one of the risky ports 3389 (Remote Desktop), 445 (SMB), 5985 and 5986 (WinRM), 22 (SSH) and 23 (Telnet), unless the port is in AllowedPorts.

It reads the rules and profile settings in force (the active store, so domain Group Policy counts). A rule is flagged even when it is limited to a program or service: the built-in Remote Desktop, SMB and WinRM rules all are. A rule limited to a subnet or a list of addresses is not "open to anyone" and is not flagged.

On a workstation with another firewall product enabled in Windows Security Center, that product is listed and a Windows profile that is off is not an alert (the other firewall is doing the job).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `AllowedPorts` | Ports that are fine to leave open to any address, separated by commas, e.g. "3389, 445". Whole numbers 1 to 65535. Default none. | (empty) | `AllowedPorts` or `ALLOWED_PORTS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-firewall-profiles.ps1
```

Alerts when a profile is off or a risky port is open to any address.

```powershell
.\test-firewall-profiles.ps1 -AllowedPorts "3389" -OutputFormat Json
```

Accepts Remote Desktop open to any address and prints one JSON object.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `AllowedPorts`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Public profile is off; 3389 open to any address (Remote Desktop - User Mode (TCP-In))
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Check`, `Item`, `Detail`, `Problem`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-firewall-profiles

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
