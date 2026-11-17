# Internet works but nothing loads - reset the network stack

> Resets the Windows network stack (Winsock, TCP/IP, DNS cache, DHCP leases) when the internet works but nothing loads.

| | |
|---|---|
| Script | `reset-network-stack.ps1` |
| Type | Action |
| Category | Networking, DNS, VPN, firewall |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | Resets Winsock and the TCP/IP stack; flushes DNS; renews DHCP leases; restores static IP settings when allowed; optionally clears the WinHTTP proxy |
| Risk | **High** |
| Reboot | Required |
| Typical runtime | Under 2 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=reset-network-stack`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\reset-network-stack.log`.
- Before it edits or deletes configuration, it copies it to `%ProgramData%\MSPOutpost\Backups\reset-network-stack\<UTC time>\` and keeps the last 10 runs. If a backup fails, nothing is changed.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS AND CAN DROP THE NETWORK. Because of that it defaults to a DRY RUN: set DryRun to false and Approve to reset-network-stack to make the changes. It:

- resets Winsock (netsh winsock reset),
- resets the TCP/IP stack (netsh int ip reset, log written to the Windows temp folder),
- flushes the DNS cache (ipconfig /flushdns),
- with ResetProxy, clears the machine-wide WinHTTP proxy (netsh winhttp reset proxy),
- with RenewDhcp, last of all, renews the lease of every connected DHCP adapter (ipconfig /renew).

WARNING: the machine briefly loses its network. A remote-control session or an RMM agent that runs over the network can disconnect while the leases are renewed; the script keeps running and finishes locally. The TCP/IP reset can clear static IP addresses, so the script REFUSES to run when a connected adapter has one, unless AllowStaticAdapters is true (it then saves and restores those settings). The Winsock reset only completes after a restart: the answer says "reboot needed to finish". The script never reboots.

It does not touch firewall rules, VPN profiles, adapter drivers or the WinINET (per-user) proxy.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `RenewDhcp` | true to renew the lease of each connected DHCP adapter, last. Default true. | `true` | `RenewDhcp` or `RENEW_DHCP` |
| `ResetProxy` | true to also clear the WinHTTP machine proxy. Default false. | `false` | `ResetProxy` or `RESET_PROXY` |
| `AllowStaticAdapters` | The script refuses to run while a connected adapter has a static IPv4 address, because the TCP/IP reset can wipe it and leave a server off the network after the restart. true runs anyway: it saves each static adapter's address, prefix, gateway and DNS servers first, sets them again after the reset and checks them. Default false. | `false` | `AllowStaticAdapters` or `ALLOW_STATIC_ADAPTERS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\reset-network-stack.ps1
```

Dry run: lists every reset it would make and changes nothing.

```powershell
.\reset-network-stack.ps1 -DryRun false -Approve reset-network-stack -ResetProxy true
```

Resets the stack, clears the WinHTTP proxy and renews DHCP leases.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `RenewDhcp`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `reset-network-stack`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Reset Winsock and TCP/IP, flushed DNS, renewed 1 DHCP lease; reboot needed to finish
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\reset-network-stack.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/reset-network-stack

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
