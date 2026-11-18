# Patch this Linux server now

> Installs the waiting package updates on a Linux server (all, or security only) and says whether a reboot is needed.

| | |
|---|---|
| Script | `install-linux-updates.sh` |
| Type | Action |
| Category | Linux management |
| Platforms | Ubuntu 22.04+, Debian 12+, RHEL/Rocky/Alma 9+ |
| Runs as | root |
| Requires | bash 3.2, root, apt-get or dnf, network access to the package repositories |
| Changes | Installs package updates (and any new packages they need); optionally schedules a reboot |
| Risk | Low |
| Reboot | Restarts |
| Typical runtime | 1 to 30 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT CHANGES THINGS. It refreshes the package list, works out which installed packages have an update waiting, installs them, and checks the list again. apt (Ubuntu, Debian) and dnf (RHEL, Rocky, Alma, Fedora) are supported; SUSE and Arch are not. UPDATE_SCOPE=Security (default) installs only updates published as security updates; All installs every update. Held packages (apt-mark hold, dnf versionlock) are left alone. New packages that an update needs (a new kernel image, for example) are installed with it; nothing is ever removed. EXCLUDE_PACKAGES names packages never to update. Refreshing the package list is not counted as a change, so it also happens in a dry run: otherwise the dry run would list yesterday's updates. Services are not restarted behind your back: needrestart is set to list mode, so a service that still runs old libraries keeps running until you restart it or reboot. Reboots: it NEVER reboots unless REBOOT_IF_REQUIRED is true AND nobody is signed in at the console or a desktop session (SSH sessions, which include the RMM, do not count); then it schedules a reboot in one minute ("shutdown -c" cancels it). In every other case the answer says "reboot required" when the machine needs one. A reboot already pending from earlier updates is also done when REBOOT_IF_REQUIRED is true. The package manager's own output goes to /var/log/mspoutpost/install-linux-updates.pm.log (the last run only); every installed package is also written to the change log. Tested on Ubuntu 24.04 (Arm64), apt only. The dnf path, Debian 12 and RHEL/Rocky/Alma 9 are written for but not yet run.

## Inputs

| Input | Meaning | Default | Environment variable | Argument |
|---|---|---|---|---|
| `UPDATE_SCOPE` | Security (default) or All. | `Security` | `UPDATE_SCOPE` | `--update-scope` |
| `EXCLUDE_PACKAGES` | Package names never to update, comma-separated. Default none. | (empty) | `EXCLUDE_PACKAGES` | `--exclude-packages` |
| `REBOOT_IF_REQUIRED` | true to reboot (in one minute) when needed and nobody is signed in. Default false. | `false` | `REBOOT_IF_REQUIRED` | `--reboot-if-required` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). As an action it also accepts `DRY_RUN`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./install-linux-updates.sh --dry-run true
```

```bash
sudo UPDATE_SCOPE=All REBOOT_IF_REQUIRED=true ./install-linux-updates.sh
```

### In an RMM

Add the script to your RMM as a shell script (`#!/bin/bash`) and run it as root on macOS or Linux. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `UPDATE_SCOPE`).
- **Command-line arguments:** `--update-scope value`.
- **No variables at all:** edit the `DEFAULT_` line for that input near the top of the script body.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Installed 7 security updates; reboot required
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

Every change is also logged to `/Library/Logs/MSPOutpost/install-linux-updates.log` on macOS or `/var/log/mspoutpost/install-linux-updates.log` on Linux.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/install-linux-updates

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
