# Linux disk full: clear logs, journal and caches

> Frees disk space on a Linux server: journal, package cache, unused packages and old rotated logs, with before and after numbers.

| | |
|---|---|
| Script | `clear-linux-disk-space.sh` |
| Type | Action |
| Category | Linux management |
| Platforms | Ubuntu 22.04+, Debian 12+, RHEL/Rocky/Alma 9+ |
| Runs as | root |
| Requires | bash 3.2, root, GNU find, df; journalctl, apt-get or dnf, docker when used |
| Changes | Vacuums the journal, clears the package cache, autoremoves unused packages and old kernels, deletes old rotated logs, optionally prunes dangling Docker images and build cache |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 2 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT CHANGES THINGS. It frees space in five places and measures the free space on / and /var before and after:

1. The systemd journal: rotated and vacuumed down to JOURNAL_MAX_MB (journalctl --vacuum-size). Only when it is bigger than that.
2. The package download cache (apt-get clean, dnf clean packages).
3. Packages nothing needs any more, INCLUDING old kernels, through the package manager's own autoremove (apt-get autoremove --purge, dnf autoremove). The running kernel and the newest ones are kept by the package manager. Packages you installed by hand are never candidates. Switch it off with REMOVE_UNUSED_PACKAGES=false.
4. Rotated logs under /var/log: files that logrotate already finished with (names ending .gz .xz .bz2 .zst .old .1 .2 ... or a date such as -20260301) and that have not been modified for LOG_AGE_DAYS days.
5. Docker, only when DOCKER_PRUNE is true: dangling images and the build cache. Containers, volumes and images in use are never touched.

It NEVER deletes a live log (the file a program is writing to), anything in /var/log/journal or /var/log/mspoutpost, home folders, or user data. A live log over 1 GB is reported as a WARNING (fix its logrotate rule); this script leaves it alone. Each of the five is skipped, and says so, when there is nothing to do. Tested on Ubuntu 24.04 (Arm64), apt only. The dnf path, Debian 12 and RHEL/Rocky/Alma 9 are written for but not yet run; the Docker path is not yet run.

## Inputs

| Input | Meaning | Default | Environment variable | Argument |
|---|---|---|---|---|
| `LOG_AGE_DAYS` | Delete rotated logs not modified for this many days. 1-3650. Default 30. | `30` | `LOG_AGE_DAYS` | `--log-age-days` |
| `JOURNAL_MAX_MB` | Vacuum the journal down to this size. 10-1000000, or 0 to leave it alone. Default 500. | `500` | `JOURNAL_MAX_MB` | `--journal-max-mb` |
| `CLEAN_PACKAGE_CACHE` | true to clear the downloaded package files. Default true. | `true` | `CLEAN_PACKAGE_CACHE` | `--clean-package-cache` |
| `REMOVE_UNUSED_PACKAGES` | true to autoremove unused packages and old kernels. Default true. | `true` | `REMOVE_UNUSED_PACKAGES` | `--remove-unused-packages` |
| `DOCKER_PRUNE` | true to prune dangling Docker images and build cache. Default false. | `false` | `DOCKER_PRUNE` | `--docker-prune` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). As an action it also accepts `DRY_RUN`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./clear-linux-disk-space.sh --dry-run true
```

```bash
sudo LOG_AGE_DAYS=14 JOURNAL_MAX_MB=200 DOCKER_PRUNE=true ./clear-linux-disk-space.sh
```

### In an RMM

Add the script to your RMM as a shell script (`#!/bin/bash`) and run it as root on macOS or Linux. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `LOG_AGE_DAYS`).
- **Command-line arguments:** `--log-age-days value`.
- **No variables at all:** edit the `DEFAULT_` line for that input near the top of the script body.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Freed 410 MB (journal 120 MB, package cache 80 MB, 4 unused packages, 14 old logs 210 MB); / 61% free
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

Every change is also logged to `/Library/Logs/MSPOutpost/clear-linux-disk-space.log` on macOS or `/var/log/mspoutpost/clear-linux-disk-space.log` on Linux.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/clear-linux-disk-space

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
