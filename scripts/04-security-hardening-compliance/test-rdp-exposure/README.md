# Remote Desktop open to the internet or without NLA

> Alerts when Remote Desktop is on and reachable from any address, or on without Network Level Authentication.

| | |
|---|---|
| Script | `test-rdp-exposure.ps1` |
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

THIS SCRIPT IS READ-ONLY. It reads, as Windows enforces them (a Group Policy value wins over the local one):

- whether Remote Desktop connections are allowed (fDenyTSConnections),
- whether Network Level Authentication is required (UserAuthentication),
- the listening port (RDP-Tcp PortNumber) and the RDP security layer (SecurityLayer: 0 RDP security, 1 negotiate, 2 TLS),
- when Remote Desktop is on: every enabled inbound Allow rule in the active firewall store (domain Group Policy included) for that TCP port, and the remote addresses each rule accepts.

It alerts when Remote Desktop is on AND (a rule accepts Any address, Internet or a 0.0.0.0/0 range, or, when AllowedSources is set, accepts an address outside it), or when Remote Desktop is on and NLA is not required. The keywords LocalSubnet, Intranet, DefaultGateway, DHCP, DNS and WINS are treated as local and are fine. A rule is counted when it names the RDP port; rules that open every port and Block rules are not evaluated. A firewall profile that is off while Remote Desktop is on also alerts. A weak security layer (0) is shown but does not alert on its own.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `AllowedSources` | Addresses, CIDR blocks (10.0.0.0/24) or ranges (10.0.0.1-10.0.0.9) from which Remote Desktop is acceptable, separated by commas. When set, a rule that accepts any address outside them alerts. Default none (only Any/Internet alerts). | (empty) | `AllowedSources` or `ALLOWED_SOURCES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-rdp-exposure.ps1
```

Alerts when RDP is on and open to any address or runs without NLA.

```powershell
.\test-rdp-exposure.ps1 -AllowedSources "10.9.0.0/24,192.168.1.10"
```

Also alerts when an RDP rule accepts addresses outside the management range.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `AllowedSources`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
RDP is on and reachable from any address via Remote Desktop - User Mode (TCP-In); restrict the rule's RemoteAddress; NLA is not required
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

Full page: https://mspoutpost.com/scripts/test-rdp-exposure

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
