# Remove a Mac app and everything it left behind

> Removes a Mac app by name or bundle ID, plus the files it left behind.

| | |
|---|---|
| Script | `uninstall-mac-app.sh` |
| Type | Action |
| Category | macOS management |
| Platforms | macOS 13+ |
| Runs as | root |
| Requires | bash 3.2, root; Full Disk Access for the RMM agent to clear some protected folders |
| Changes | Deletes the app bundle, its launchd jobs, per-user and system leftover folders and preference files, and package receipts |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DRY_RUN=false` **and** `APPROVE=uninstall-mac-app`. Typing the script name is the deliberate step.
- It refuses to make more than `MAX_CHANGES` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `/Library/Logs/MSPOutpost/uninstall-mac-app.log` on macOS or `/var/log/mspoutpost/uninstall-mac-app.log` on Linux.
- Before it edits or deletes configuration, it copies it to `/Library/Application Support/MSPOutpost/Backups/uninstall-mac-app/<UTC time>/` on macOS or `/var/lib/mspoutpost/backups/uninstall-mac-app/<UTC time>/` on Linux, and keeps the last 10 runs. If a backup fails, nothing is changed.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. It finds the app bundle by exact name or exact bundle ID in /Applications and each user's Applications folder, then removes: the bundle; the app's launchd jobs (LaunchAgents/LaunchDaemons in /Library and in each user's Library) whose Program points into the bundle; per-user and system leftovers in known folders derived from the bundle ID (Application Support, Caches, HTTPStorages, WebKit, Containers, Application Scripts, Saved Application State, Logs, the Preferences plist and its ByHost copies) and the Application Support folder named after the app; and package receipts that list the bundle itself (pkgutil --forget). The list of removed paths and each removed launchd plist are backed up first. It never touches Apple apps (com.apple.* IDs, anything in /System), bundle IDs starting com.ninjarmm., com.jamf., com.jamfsoftware., io.kandji., com.addigy. or com.splashtop. (management and remote-support agents), or any name with a wildcard. A running app is left alone (the run is SKIPPED) unless QUIT_APP is true, which asks it to quit, then ends its processes. High risk: it is a dry run unless DRY_RUN=false AND APPROVE=uninstall-mac-app are both set. By default it makes at most 25 changes per run (MAX_CHANGES). Needs root. If macOS refuses to delete a protected folder, grant the RMM agent Full Disk Access.

## Inputs

| Input | Meaning | Default | Environment variable | Argument |
|---|---|---|---|---|
| `APP` | REQUIRED. App name (Zoom for Zoom.app) or bundle ID, exact. | (empty) | `APP` | `--app` |
| `QUIT_APP` | Quit the app first if it is running. Default false. | `false` | `QUIT_APP` | `--quit-app` |
| `TARGET_USER` | Only this user's leftovers. Default every user. | (empty) | `TARGET_USER` | `--target-user` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). As an action it also accepts `DRY_RUN`, `APPROVE` and `MAX_CHANGES`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./uninstall-mac-app.sh --app com.example.widget
```

```bash
sudo ./uninstall-mac-app.sh --app Widget --quit-app true --dry-run false --approve uninstall-mac-app
```

### In an RMM

Add the script to your RMM as a shell script (`#!/bin/bash`) and run it as root on macOS or Linux. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `APP`).
- **Command-line arguments:** `--app value`.
- **No variables at all:** edit the `DEFAULT_` line for that input near the top of the script body.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DRY_RUN` to `false` and `APPROVE` to `uninstall-mac-app`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Removed Widget (com.example.widget): the app and 7 related item(s)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

Every change is also logged to `/Library/Logs/MSPOutpost/uninstall-mac-app.log` on macOS or `/var/log/mspoutpost/uninstall-mac-app.log` on Linux.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/uninstall-mac-app

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
