# Turn off Remote Login and Screen Sharing on a Mac

> Turns off Remote Login (SSH), Screen Sharing and Remote Management (ARD) on a Mac.

| | |
|---|---|
| Script | `disable-mac-remote-access.sh` |
| Type | Action |
| Category | macOS management |
| Platforms | macOS 13+ |
| Runs as | root |
| Requires | bash 3.2, root, Full Disk Access for the agent to turn Remote Login off |
| Changes | Turns off Remote Login (SSH), Screen Sharing and Remote Management (ARD) |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | Under 15 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DRY_RUN=false` **and** `APPROVE=disable-mac-remote-access`. Typing the script name is the deliberate step.
- It refuses to make more than `MAX_CHANGES` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `/Library/Logs/MSPOutpost/disable-mac-remote-access.log` on macOS or `/var/log/mspoutpost/disable-mac-remote-access.log` on Linux.
- Before it edits or deletes configuration, it copies it to `/Library/Application Support/MSPOutpost/Backups/disable-mac-remote-access/<UTC time>/` on macOS or `/var/lib/mspoutpost/backups/disable-mac-remote-access/<UTC time>/` on Linux, and keeps the last 10 runs. If a backup fails, nothing is changed.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. Risk is High, because switching these off can lock out whoever supports the Mac remotely, so it is a dry run unless you set BOTH DRY_RUN=false AND APPROVE=disable-mac-remote-access, and it refuses more than MAX_CHANGES (default 25) changes in one run. For each service that is on and whose DISABLE_* input is true it: Remote Login        runs systemsetup -f -setremotelogin off. Screen Sharing      launchctl disable and bootout of system/com.apple.screensharing (stays off after a restart). Remote Management   kickstart -deactivate -configure -access -off, then kickstart -stop (the Apple Remote Desktop agent).

It then reads each service again and ends in ERROR if one is still on. Nothing else is touched: no account, no firewall rule, no key. Before changing anything it copies launchd's override database (/var/db/com.apple.xpc.launchd/disabled.plist) to /Library/Application Support/MSPOutpost/Backups/disable-mac-remote-access/. REMOTE LOGIN NEEDS FULL DISK ACCESS. On macOS 13 and later, systemsetup -setremotelogin is refused unless the program that runs this script (your RMM agent or MDM agent) has Full Disk Access. When macOS refuses, this script ends in ERROR before changing anything else and says so. Grant Full Disk Access to the agent (a PPPC profile from your MDM), or turn Remote Login off in System Settings > General > Sharing. Screen Sharing and Remote Management do not need it. PROTECTED: a run that was started over SSH never turns Remote Login off (that would cut off the run itself): it warns and leaves it on, and ends SKIPPED if that was all there was to do. Run it from your RMM agent.

## Inputs

| Input | Meaning | Default | Environment variable | Argument |
|---|---|---|---|---|
| `DISABLE_REMOTE_LOGIN` | Turn Remote Login (SSH) off when it is on. Default true. | `true` | `DISABLE_REMOTE_LOGIN` | `--disable-remote-login` |
| `DISABLE_SCREEN_SHARING` | Turn Screen Sharing off when it is on. Default true. | `true` | `DISABLE_SCREEN_SHARING` | `--disable-screen-sharing` |
| `DISABLE_REMOTE_MANAGEMENT` | Turn Remote Management (ARD) off when it is on. Default true. | `true` | `DISABLE_REMOTE_MANAGEMENT` | `--disable-remote-management` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). As an action it also accepts `DRY_RUN`, `APPROVE` and `MAX_CHANGES`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./disable-mac-remote-access.sh
```

```bash
sudo ./disable-mac-remote-access.sh --disable-remote-login false --dry-run=false --approve=disable-mac-remote-access
```

### In an RMM

Add the script to your RMM as a shell script (`#!/bin/bash`) and run it as root on macOS or Linux. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `DISABLE_REMOTE_LOGIN`).
- **Command-line arguments:** `--disable-remote-login value`.
- **No variables at all:** edit the `DEFAULT_` line for that input near the top of the script body.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DRY_RUN` to `false` and `APPROVE` to `disable-mac-remote-access`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Turned off Screen Sharing, Remote Management
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

Every change is also logged to `/Library/Logs/MSPOutpost/disable-mac-remote-access.log` on macOS or `/var/log/mspoutpost/disable-mac-remote-access.log` on Linux.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/disable-mac-remote-access

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
