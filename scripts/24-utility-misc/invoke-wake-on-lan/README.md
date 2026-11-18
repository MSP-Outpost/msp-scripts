# Wake a powered-off PC - Wake-on-LAN

> Wakes powered-off PCs on this network by sending Wake-on-LAN magic packets.

| | |
|---|---|
| Script | `invoke-wake-on-lan.ps1` |
| Type | Action |
| Category | Utility / misc |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | Either |
| Requires | PowerShell 5.1; an online PC on the same subnet as the target |
| Changes | Sends UDP broadcast packets on the network; nothing changes on this PC |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 10 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS, but only on the network: it sends UDP broadcast packets and changes nothing on this PC. For each MAC address it builds a magic packet (six bytes of FF, then the MAC repeated 16 times) and sends it Repeat times to each broadcast address.

Run it on an online PC on the SAME subnet as the sleeping PC: broadcasts do not cross routers. Without Broadcast, the script sends to the directed broadcast address of every up IPv4 interface (for 192.168.1.20/24 that is 192.168.1.255), from that interface. With Broadcast, it sends to the addresses you give.

The script cannot confirm that a target woke up. UDP gives no answer, so "sent" is all it can say. If a PC does not wake, check that Wake-on-LAN (or "Wake on magic packet") is on in its BIOS/UEFI and network adapter settings, that it is plugged into Ethernet, and that Fast Startup is not hiding a full shutdown (hibernate or sleep is more reliable).

Sending the same packets again is harmless, so a second run sends them again and says CHANGED; there is no "already woken" state to detect.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `MacAddresses` | Required. MAC addresses of the PCs to wake, separated by comma, semicolon or newline. Accepts aa:bb:cc:dd:ee:ff, aa-bb-cc-dd-ee-ff, aabb.ccdd.eeff and aabbccddeeff, any case. | (empty) | `MacAddresses` or `MAC_ADDRESSES` |
| `Broadcast` | Optional. IPv4 broadcast address(es) to send to (for example 192.168.1.255), separated by comma or semicolon. Empty (default) uses the directed broadcast of each up IPv4 interface. | (empty) | `Broadcast` or `BROADCAST` |
| `Port` | UDP port, 1 to 65535. Default 9 (7 is the other common choice). | `9` | `Port` or `PORT` |
| `Repeat` | Packets sent to each address for each MAC, 1 to 10. Default 3. | `3` | `Repeat` or `REPEAT` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\invoke-wake-on-lan.ps1 -MacAddresses "aa:bb:cc:dd:ee:01, aa-bb-cc-dd-ee-02"
```

Sends 3 magic packets for each PC to every local subnet.

```powershell
.\invoke-wake-on-lan.ps1 -MacAddresses aabbccddee03 -Broadcast 10.0.5.255 -Repeat 5
```

Sends 5 packets to the 10.0.5.255 broadcast address.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `MacAddresses`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Sent 6 magic packets (3 each) for 2 MACs via 192.168.1.255:9; cannot confirm the PCs woke
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\invoke-wake-on-lan.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/invoke-wake-on-lan

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
