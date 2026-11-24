# VPN won't connect - VPN first aid

> VPN first aid: starts a stopped VPN client service, flushes and re-registers DNS, never deletes a VPN profile.

| | |
|---|---|
| Script | `repair-vpn-client.ps1` |
| Type | Action |
| Category | Remediation & self-healing |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights; the DnsClient module |
| Changes | Starts (or with Force restarts) the VPN client service; flushes the DNS client cache; re-registers DNS |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

PARTLY TESTED: written from the vendors' documentation (Fortinet, Cisco, Palo Alto Networks, WireGuard, Microsoft Get-VpnConnection). Tested on Windows 11: the built-in Windows VPN repair, and WireGuard 1.1.1 with a real tunnel service (start a stopped tunnel, Force restart, a Disabled service refused, an unknown tunnel name refused, dry run, second run Already healthy). FortiClient, Cisco Secure Client and GlobalProtect were tested only on the not-installed path.

THIS SCRIPT CHANGES THINGS. For the one client named in Client it:

- starts a VPN client service that is Stopped (FortiClient FA_Scheduler; Cisco Secure Client / AnyConnect VPN Agent; GlobalProtect PanGPS; WireGuard tunnel services WireGuardTunnel$<name>);
- with Force=true, also RESTARTS a service that is Running, which drops a connected tunnel and its user's session: use it when the client is running but stuck (GlobalProtect "stuck connecting" is documented to be cured by restarting PanGPS);
- flushes the DNS client cache (Clear-DnsClientCache) and re-registers the PC's DNS records (Register-DnsClient). It acts only when something is wrong: a service that is not running, a built-in VPN profile whose server name does not resolve, or Force=true. Otherwise it says the VPN client is already healthy and changes nothing.

It NEVER deletes or edits a VPN profile, never changes a service's start type (a Disabled service is reported, not enabled), and never uninstalls or reinstalls a client. For the built-in Windows VPN (Client BuiltIn) there is no service to restart: the repair is the DNS flush and re-register, and the script then checks that the profile's server name resolves. Profiles that belong to one user are invisible to an RMM running as SYSTEM; only the all-users phone book is read.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Client` | BuiltIn (default), FortiClient, CiscoSecureClient, GlobalProtect or WireGuard. | `BuiltIn` | `Client` or `CLIENT` |
| `ProfileName` | BuiltIn: act only for this profile name. WireGuard: only this tunnel name. Empty (default) means all. Ignored for the other clients. | (empty) | `ProfileName` or `PROFILE_NAME` |
| `Force` | true to restart a service that is already Running, and to flush DNS even when everything looks healthy. Can disconnect a user's VPN. Default false. | `false` | `Force` or `FORCE` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\repair-vpn-client.ps1 -Client GlobalProtect -Force true
Restarts the GlobalProtect service PanGPS, then flushes and re-registers DNS.
```

```powershell
.\repair-vpn-client.ps1 -Client BuiltIn -DryRun true
Says whether a built-in VPN profile's server fails to resolve and what it would flush.
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
Started service PanGPS; DNS cache flushed and re-registered
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\repair-vpn-client.log`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/repair-vpn-client

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
