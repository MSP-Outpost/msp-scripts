# Install macOS updates now (all or recommended)

> Installs the macOS and app updates Apple offers (all or recommended), without restarting unless you say so.

| | |
|---|---|
| Script | `install-macos-updates.sh` |
| Type | Action |
| Category | macOS management |
| Platforms | macOS 13+ |
| Runs as | root |
| Requires | bash 3.2, root, internet access to Apple; a volume owner's credentials for macOS updates on Apple silicon without MDM |
| Changes | Installs Apple software updates; restarts the Mac only when RESTART is true |
| Risk | Low |
| Reboot | Restarts |
| Typical runtime | 5 minutes to over an hour, depending on the updates |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT CHANGES THINGS. It runs softwareupdate -l to list what Apple offers, picks the updates for UPDATE_SCOPE (Recommended: only those Apple marks recommended; All: everything listed), and installs them by label with softwareupdate -i. A new major macOS version (for example 26 to 27) is never installed unless INCLUDE_MAJOR_UPGRADES is true. It does not restart the Mac unless RESTART is true AND an update needs one AND nobody is signed in at the console (FORCE_RESTART=true restarts even with someone signed in, which loses their unsaved work). Without a restart, an update that needs one is downloaded and staged, and the answer says "restart needed". Apple silicon: installing a macOS update needs a volume owner's credentials unless the Mac has an MDM bootstrap token. Give VOLUME_OWNER_USER and the environment variable VOLUME_OWNER_PASSWORD (a secret field in your RMM; never an argument). If Apple refuses without them the run ends ERROR with that reason. DRY_RUN=true lists what it would install and changes nothing. The list needs internet access to Apple. Parsing relies on softwareupdate's English output. Slow: macOS updates download gigabytes and can take an hour.

## Inputs

| Input | Meaning | Default | Environment variable | Argument |
|---|---|---|---|---|
| `UPDATE_SCOPE` | Recommended (default) or All. | `Recommended` | `UPDATE_SCOPE` | `--update-scope` |
| `INCLUDE_MAJOR_UPGRADES` | Also install a new major macOS version. Default false. | `false` | `INCLUDE_MAJOR_UPGRADES` | `--include-major-upgrades` |
| `RESTART` | Restart after installing if an update needs it. Default false. | `false` | `RESTART` | `--restart` |
| `FORCE_RESTART` | Restart even if someone is signed in. Default false. | `false` | `FORCE_RESTART` | `--force-restart` |
| `TIMEOUT_MINUTES` | Give up on the install after N minutes. 5-720, default 90. | `90` | `TIMEOUT_MINUTES` | `--timeout-minutes` |
| `VOLUME_OWNER_USER` | Apple silicon: a volume owner for macOS updates. Default none. | (empty) | `VOLUME_OWNER_USER` | `--volume-owner-user` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). As an action it also accepts `DRY_RUN`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./install-macos-updates.sh --dry-run true
```

```bash
sudo ./install-macos-updates.sh --update-scope All --restart true
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
Installed 2 update(s); restart needed: Safari 18.2; macOS 27.2.1
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

Every change is also logged to `/Library/Logs/MSPOutpost/install-macos-updates.log` on macOS or `/var/log/mspoutpost/install-macos-updates.log` on Linux.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/install-macos-updates

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
