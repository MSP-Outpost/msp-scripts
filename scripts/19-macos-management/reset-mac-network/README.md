# Mac network trouble - flush DNS, renew DHCP

> Mac network first aid: flush the DNS cache, and optionally renew DHCP or switch to the Automatic location.

| | |
|---|---|
| Script | `reset-mac-network.sh` |
| Type | Action |
| Category | macOS management |
| Platforms | macOS 13+ |
| Runs as | root |
| Requires | bash 3.2, root |
| Changes | Flushes the DNS cache and restarts mDNSResponder; optionally renews the DHCP lease and switches the network location to Automatic |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT CHANGES THINGS. Always: flushes the DNS cache (dscacheutil -flushcache) and restarts the DNS responder (killall -HUP mDNSResponder); both are harmless and repeatable. Only when you ask: RENEW_DHCP=true renews the DHCP lease on the interface carrying the default route (ipconfig set <interface> DHCP), which drops the connection for a few seconds, so do not use it over a remote session you cannot lose; it is skipped for a static IP address or when there is no default route. RESET_LOCATION=true switches the active network location to "Automatic" (it never deletes or edits any location); it does nothing if Automatic is already active or does not exist. It never touches VPN, Wi-Fi networks, proxies or any other setting. It reports the DNS servers, IP address and whether CHECK_HOST resolves, before and after. Running it twice flushes twice (a flush has no state to be "already" in), so the second run also reports CHANGED.

## Inputs

| Input | Meaning | Default | Environment variable | Argument |
|---|---|---|---|---|
| `RENEW_DHCP` | Renew the DHCP lease (drops the link briefly). Default false. | `false` | `RENEW_DHCP` | `--renew-dhcp` |
| `RESET_LOCATION` | Switch to the Automatic network location. Default false. | `false` | `RESET_LOCATION` | `--reset-location` |
| `CHECK_HOST` | Name to resolve before and after. Default apple.com. | `apple.com` | `CHECK_HOST` | `--check-host` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). As an action it also accepts `DRY_RUN`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./reset-mac-network.sh
```

```bash
sudo ./reset-mac-network.sh --renew-dhcp true --reset-location true
```

### In an RMM

Add the script to your RMM as a shell script (`#!/bin/bash`) and run it as root on macOS or Linux. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `RENEW_DHCP`).
- **Command-line arguments:** `--renew-dhcp value`.
- **No variables at all:** edit the `DEFAULT_` line for that input near the top of the script body.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Flushed DNS; apple.com resolves: before no, after yes; renewed DHCP on en0 (192.168.1.20)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

Every change is also logged to `/Library/Logs/MSPOutpost/reset-mac-network.log` on macOS or `/var/log/mspoutpost/reset-mac-network.log` on Linux.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/reset-mac-network

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
