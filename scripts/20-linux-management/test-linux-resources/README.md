# Linux disk, memory or CPU over limit

> Alerts when a Linux server's disk, memory or CPU load crosses the limits you set.

| | |
|---|---|
| Script | `test-linux-resources.sh` |
| Type | Monitor |
| Category | Linux management |
| Platforms | Ubuntu 22.04+, Debian 12+, RHEL/Rocky/Alma 9+ |
| Runs as | root or a user |
| Requires | bash 3.2, df, awk, /proc |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 5 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. It checks three things and alerts (exit 1) when any of them is past its limit: free disk space on every local volume (ext*, xfs, btrfs, zfs), available memory (MemAvailable, so file cache does not count as used), and the 5-minute load average as a percentage of the CPU count (100 = every CPU busy; a load of 8 on 4 CPUs is 200). Set a limit to 0 to switch that check off. A volume mounted twice (bind mounts, btrfs subvolumes) is checked once. Tested on Ubuntu 24.04 (Arm64). The same commands exist on Debian 12 and RHEL, Rocky and Alma 9; those are written for but not yet run.

## Inputs

| Input | Meaning | Default | Environment variable | Argument |
|---|---|---|---|---|
| `MIN_DISK_FREE_PERCENT` | Alert when a volume has less than this % free. 0-99, 0 = off. Default 10. | `10` | `MIN_DISK_FREE_PERCENT` | `--min-disk-free-percent` |
| `MIN_MEMORY_AVAILABLE_PERCENT` | Alert when less than this % of RAM is available. 0-99, 0 = off. Default 10. | `10` | `MIN_MEMORY_AVAILABLE_PERCENT` | `--min-memory-available-percent` |
| `MAX_LOAD_PERCENT` | Alert when the 5-minute load is above this % of the CPU count. 0-10000, 0 = off. Default 200. | `200` | `MAX_LOAD_PERCENT` | `--max-load-percent` |
| `EXCLUDE_MOUNTS` | Mount points to skip, comma-separated. Default none. | (empty) | `EXCLUDE_MOUNTS` | `--exclude-mounts` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./test-linux-resources.sh
```

```bash
MIN_DISK_FREE_PERCENT=20 MAX_LOAD_PERCENT=150 OUTPUT_FORMAT=Json ./test-linux-resources.sh
```

### In an RMM

Add the script to your RMM as a shell script (`#!/bin/bash`) and run it as root on macOS or Linux. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `MIN_DISK_FREE_PERCENT`).
- **Command-line arguments:** `--min-disk-free-percent value`.
- **No variables at all:** edit the `DEFAULT_` line for that input near the top of the script body.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Disk / 8% free (limit 10%); Load 250% of 4 CPU(s) (limit 200%)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Check`, `Item`, `Value`, `Limit`, `Unit`, `Breached`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/test-linux-resources

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
