# Is this PC exposing RDP, SMB or other risky ports through the firewall

> Alerts when this PC listens on a risky port (RDP, SMB, WinRM, VNC, Telnet, FTP) that the Windows firewall lets other computers reach.

| | |
|---|---|
| Script | `test-exposed-ports.ps1` |
| Type | Monitor |
| Category | Networking, DNS, VPN, firewall |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, the NetTCPIP and NetSecurity modules |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | 10 to 60 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. It looks only at this PC and uses no outside scanning service.

1. It lists the TCP ports this PC is listening on, leaving out sockets that only accept connections from the PC itself (127.0.0.1 and ::1), with the program and, when there is only one, the Windows service behind each.
2. For each one it asks the Windows firewall: for the network profile(s) this PC is connected to now (Public, Private or Domain; Public when it cannot tell), is the firewall on, does an enabled inbound BLOCK rule cover the port, and does an enabled inbound ALLOW rule cover it (matching profile, TCP, local port, and program when the rule names one)? A block rule wins over an allow rule. With the firewall off, the profile's default inbound action Allow, or an allow rule, the port is reachable. The row says how far: any address, specific addresses, or the local network only (a rule limited to LocalSubnet, Intranet or private ranges).
3. It alerts (exit 1) when a port on the RiskyPorts list is reachable from ANY address (or the firewall is off). A risky port that is listening but blocked is reported on its row and does not alert. A port that is reachable only from the local network or from named addresses alerts only when AlertOnRestricted is true. Ports in AllowedPorts (a server that is meant to offer RDP, say) never alert.

Not covered: UDP, firewall rules that name a Windows service or a dynamic-RPC range instead of a port, and what a router in front of the PC forwards from the internet. A port can be reachable here and still not be reachable from the internet; to test what the internet sees, use a scanner outside the network. Needs administrator rights (it reads the firewall and every process).

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `RiskyPorts` | TCP ports that alert when reachable, separated by commas. Default 21,23,445,3389,5900,5985,5986 (FTP, Telnet, SMB, RDP, VNC, WinRM and WinRM over HTTPS). | `21,23,445,3389,5900,5985,5986` | `RiskyPorts` or `RISKY_PORTS` |
| `AllowedPorts` | Ports that are meant to be open on this PC and never alert, separated by commas. Default none. | (empty) | `AllowedPorts` or `ALLOWED_PORTS` |
| `AlertOnRestricted` | true also alerts when a risky port is reachable only from the local network or from named addresses. Default false. | `false` | `AlertOnRestricted` or `ALERT_ON_RESTRICTED` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-exposed-ports.ps1
```

Alerts if RDP, SMB, WinRM, VNC, Telnet or FTP is reachable through the firewall.

```powershell
.\test-exposed-ports.ps1 -RiskyPorts "3389, 445, 1433" -AllowedPorts 1433
```

Watches RDP and SMB, and treats SQL Server's port 1433 as expected.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `RiskyPorts`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
2 risky port(s) reachable: 3389 RDP (any address), 445 SMB (any address)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Port`, `Label`, `Process`, `BoundTo`, `Exposure`, `Risky`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/test-exposed-ports

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
