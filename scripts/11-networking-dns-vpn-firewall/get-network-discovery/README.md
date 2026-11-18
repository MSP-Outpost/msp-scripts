# What is on this network - list the devices on the local subnet

> Lists the devices on the local network this PC sits on, from its neighbor (ARP) table and an optional ping sweep, with host names and MAC addresses.

| | |
|---|---|
| Script | `get-network-discovery.ps1` |
| Type | Report |
| Category | Networking, DNS, VPN, firewall |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | Either |
| Requires | PowerShell 5.1, the NetTCPIP module (Get-NetNeighbor) |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | 5 to 60 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. It never leaves the network this PC is plugged into, scans no ports and uses no outside service.

What it looks at: the IPv4 network of the adapter that holds the default gateway (or the network you name in Subnet, which must lie inside a network this PC is directly attached to; anything else is refused).

How it finds devices:

- The neighbor table (the ARP cache): every device this PC has talked to recently, with its MAC address. Without a sweep this lists only those, so a quiet device can be missing.
- Sweep=true also pings every address of the subnet once (a 1-second wait each, 64 at a time) so quiet devices answer and fill the table. A device that blocks ping still shows up if it answers ARP, which every device on the same network must. The sweep refuses any network bigger than /22 (1022 addresses): name a smaller piece with Subnet.
- Host names come from a reverse DNS lookup (ResolveNames, on by default). Many devices have none, and the column stays blank.

Each row says where it came from (This PC, Ping reply and neighbor table, Neighbor table only) and notes the default gateway. The OuiPrefix column is the first three bytes of the MAC address, which identify the maker in the public IEEE list; this script ships no maker table and invents no vendor names, so look the prefix up when you need it. A MAC whose second digit is 2, 6, A or E is a private (randomized) address, common on phones, and its prefix names nobody.

The answer counts the other devices (this PC is listed too). A sweep takes a few seconds on a /24 and up to a minute on a /22.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Subnet` | The network to list, as CIDR, for example 192.168.1.0/24. Between /22 and /30 and inside a network this PC is attached to. Default empty = the network of the default gateway. | (empty) | `Subnet` or `SUBNET` |
| `Sweep` | true pings every address of the subnet first. Default false (neighbor table only). | `false` | `Sweep` or `SWEEP` |
| `ResolveNames` | true looks up each device's host name. Default true. | `true` | `ResolveNames` or `RESOLVE_NAMES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-network-discovery.ps1 -Sweep true
```

Pings the whole local subnet, then lists every device that answered.

```powershell
.\get-network-discovery.ps1 -Subnet 10.0.5.0/24 -Sweep true -OutputFormat Csv
```

Lists the devices of one /24 inside a bigger local network, as CSV.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Subnet`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Found 13 other device(s) on 192.168.1.0/24 (ping sweep and neighbor table); 5 without a host name
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `IPAddress`, `Hostname`, `MacAddress`, `OuiPrefix`, `Source`, `Notes`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/get-network-discovery

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
