# VPN client ready

> Alerts when a VPN client is not ready: a Windows VPN profile whose server does not resolve, or a VPN client service that is stopped.

| | |
|---|---|
| Script | `test-vpn-client.ps1` |
| Type | Monitor |
| Category | Remediation & self-healing |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1; the VpnClient and DnsClient modules for BuiltIn |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

PARTLY TESTED: written from the vendors' documentation (Fortinet, Cisco, Palo Alto Networks, WireGuard, Microsoft Get-VpnConnection). Tested on Windows 11: the built-in Windows VPN profiles, and WireGuard 1.1.1 with a real tunnel service (running, stopped, disabled, a named and an unknown tunnel). FortiClient, Cisco Secure Client and GlobalProtect were tested only on the not-installed path; their running and stopped paths are unproven.

THIS SCRIPT IS READ-ONLY. It checks the one VPN client named in Client: BuiltIn          the Windows VPN profiles in the all-users phone book (Get-VpnConnection -AllUserConnection). For each profile it reads the connection status and checks that the server name resolves in DNS (a server address that is an IP address is not looked up). A VPN profile that cannot resolve its server is the commonest "VPN won't connect" cause. With RequireConnected true it also alerts when a profile is not Connected. PROFILES THAT BELONG TO ONE USER ARE NOT VISIBLE: an RMM runs as SYSTEM and sees only all-users profiles. FortiClient      the Windows service FA_Scheduler is running. CiscoSecureClient the service "Cisco Secure Client - AnyConnect VPN Agent" (older versions: "Cisco AnyConnect Secure Mobility Agent" or "Cisco AnyConnect VPN Agent") is running. GlobalProtect    the service PanGPS is running. WireGuard        every tunnel service WireGuardTunnel$<name> that exists is running (or only the one tunnel named in ProfileName). A service that is Disabled also alerts. The script cannot tell whether a third-party tunnel is connected, only that its client service is up.

When the chosen client is not on the PC the result is SKIPPED, or ALERT when RequireInstalled is true.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Client` | BuiltIn (default), FortiClient, CiscoSecureClient, GlobalProtect or WireGuard. | `BuiltIn` | `Client` or `CLIENT` |
| `ProfileName` | BuiltIn: check only this profile name. WireGuard: check only this tunnel name. Empty (default) checks all. Ignored for the other clients. | (empty) | `ProfileName` or `PROFILE_NAME` |
| `RequireConnected` | BuiltIn only. true alerts when a profile is not Connected. Default false. | `false` | `RequireConnected` or `REQUIRE_CONNECTED` |
| `RequireInstalled` | true alerts when the client or the named profile is missing; false (default) is SKIPPED. A WireGuard ProfileName that matches no tunnel on a PC that has other tunnels always alerts (it names the tunnels there). | `false` | `RequireInstalled` or `REQUIRE_INSTALLED` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-vpn-client.ps1 -Client BuiltIn -ProfileName "Office VPN" -RequireInstalled true
Alerts when the all-users VPN profile "Office VPN" is missing or its server name does not resolve.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Client`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
VPN profile Office VPN: NotConnected; server vpn.example.com resolves
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

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/test-vpn-client

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
