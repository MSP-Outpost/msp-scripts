# Teams won't load on a Mac - clear the Teams cache

> Clears the Microsoft Teams cache (new and classic) for every Mac user, or one.

| | |
|---|---|
| Script | `clear-mac-teams-cache.sh` |
| Type | Action |
| Category | macOS management |
| Platforms | macOS 13+ |
| Runs as | root |
| Requires | bash 3.2, root; Full Disk Access for the RMM agent to clear app container folders |
| Changes | Deletes the contents of the Microsoft Teams cache folders in each user's Library |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT CHANGES THINGS. For each user (UID 500 or higher with a home under /Users; or only TARGET_USER) it empties the Teams cache folders: new Teams (com.microsoft.teams2): Containers/.../Library/Caches, the group container's Caches, Library/Caches/com.microsoft.teams2*, and the Cache, Code Cache and GPUCache folders of its web profile; classic Teams: Library/Caches/com.microsoft.teams*, and under Application Support/ Microsoft/Teams the Cache, Code Cache, GPUCache, blob_storage, tmp, Application Cache and Service Worker cache folders. It empties the folders but keeps the folders themselves, and never touches settings, sign-in data, local storage or chats. Teams must not be running for that user: if it is, that user is skipped (SKIPPED when nobody could be cleared) unless QUIT_TEAMS is true, which asks Teams to quit and then ends its processes. Cache is rebuilt by Teams, so its next start is slower.

## Inputs

| Input | Meaning | Default | Environment variable | Argument |
|---|---|---|---|---|
| `TARGET_USER` | Only this user. Default every user. | (empty) | `TARGET_USER` | `--target-user` |
| `QUIT_TEAMS` | Quit Teams first if it is running. Default false. | `false` | `QUIT_TEAMS` | `--quit-teams` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). As an action it also accepts `DRY_RUN`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./clear-mac-teams-cache.sh
```

```bash
sudo ./clear-mac-teams-cache.sh --target-user jsmith --quit-teams true
```

### In an RMM

Add the script to your RMM as a shell script (`#!/bin/bash`) and run it as root on macOS or Linux. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `TARGET_USER`).
- **Command-line arguments:** `--target-user value`.
- **No variables at all:** edit the `DEFAULT_` line for that input near the top of the script body.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Cleared the Teams cache for 2 user(s): 5 folder(s), 612 MB freed
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

Every change is also logged to `/Library/Logs/MSPOutpost/clear-mac-teams-cache.log` on macOS or `/var/log/mspoutpost/clear-mac-teams-cache.log` on Linux.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/clear-mac-teams-cache

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
