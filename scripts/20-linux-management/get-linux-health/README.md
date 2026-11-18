# What is this Linux box? Health summary

> Reports what a Linux server is and how it is doing: OS, uptime, load, memory, disk, failed services, updates, reboot, firewall, SSH.

| | |
|---|---|
| Script | `get-linux-health.sh` |
| Type | Report |
| Category | Linux management |
| Platforms | Ubuntu 22.04+, Debian 12+, RHEL/Rocky/Alma 9+ |
| Runs as | root or a user |
| Requires | bash 3.2, awk, /proc; root for the SSH and firewall rows |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 20 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. It collects one table of facts about this Linux machine and always ends OK unless it cannot run at all: System    distribution, kernel, architecture, virtualisation, CPU, uptime, boot time, signed-in sessions Load      1, 5 and 15 minute load averages and the CPU count Memory    RAM and swap, total and available Disk      free space on every local volume (ext*, xfs, btrfs, zfs) Services  failed systemd units (names) Updates   updates waiting in the package manager's last-refreshed list, how many are security updates, how old that list is, and whether a reboot is needed Firewall  ufw, firewalld, nftables or iptables, whichever is in use SSH       the effective sshd settings that matter (root login, password login, port) Time      time zone and whether the clock is synchronised Process   the five busiest processes by CPU and by memory

It never refreshes package lists, so the update counts are as fresh as the last "apt update" or "dnf makecache"; the row "Package list age" says how old. Run as root for the SSH and firewall rows; without root those rows say "needs root" and everything else still works. Tested on Ubuntu 24.04 (Arm64). The dnf, firewalld and RHEL paths are written for Rocky/Alma/RHEL 9 and Debian 12 but not yet run.

## Inputs

This script has no inputs of its own. The [standard inputs](#standard-inputs) below still apply.

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./get-linux-health.sh
```

```bash
OUTPUT_FORMAT=Json ./get-linux-health.sh
```

### In an RMM

Add the script to your RMM as a shell script (`#!/bin/bash`) and run it as root on macOS or Linux. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `OUTPUT_FORMAT`).
- **Command-line arguments:** `--output-format value`.
- **No variables at all:** edit the `DEFAULT_` line for that input near the top of the script body.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Ubuntu 24.04.1 LTS, up 12d 3h; load 0.2; memory 41% used; / 70% free; 5 updates (2 security); no reboot needed; 0 failed units
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Area`, `Item`, `Value`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/get-linux-health

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
