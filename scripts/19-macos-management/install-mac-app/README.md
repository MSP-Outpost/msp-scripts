# Install or update a Mac app from a link, verified by hash or developer

> Installs or updates a Mac app from a download link you supply, after checking its hash or its developer.

| | |
|---|---|
| Script | `install-mac-app.sh` |
| Type | Action |
| Category | macOS management |
| Platforms | macOS 13+ |
| Runs as | root |
| Requires | bash 3.2, root, internet access to the link (unless SOURCE_FILE is used) |
| Changes | Installs or replaces an app in /Applications, or runs a package installer |
| Risk | Low |
| Reboot | Never |
| Typical runtime | 1 to 10 minutes, mostly the download |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT CHANGES THINGS. It downloads a .dmg, .pkg or .zip from the https link you give (or reads a file already on the Mac), and REFUSES to continue unless you also give a SHA256 of that file or the Developer ID Team ID the app or package must be signed by (or both). The Team ID is checked with codesign and spctl for an app, pkgutil --check-signature and spctl for a package. It then installs: an app is copied into /Applications (an older copy is replaced), a package is run with installer. If the same or a newer version is already installed it changes nothing and says so. A running app is not replaced unless QUIT_APP is true. It ships no list of apps: you supply the link and the proof. Temporary files and the mounted disk image are always cleaned up. It never restarts the Mac and never removes anything except the app it replaces. A DRY_RUN downloads and checks the file, then reports what it would install.

## Inputs

| Input | Meaning | Default | Environment variable | Argument |
|---|---|---|---|---|
| `DOWNLOAD_URL` | https link to a .dmg, .pkg or .zip. Give this or SOURCE_FILE. | (empty) | `DOWNLOAD_URL` | `--download-url` |
| `SOURCE_FILE` | A .dmg, .pkg or .zip already on this Mac (staged by your RMM). | (empty) | `SOURCE_FILE` | `--source-file` |
| `SHA256` | SHA256 the file must have. Give this, TEAM_ID, or both. | (empty) | `SHA256` | `--sha256` |
| `TEAM_ID` | Developer ID Team ID (10 characters) that must have signed it. | (empty) | `TEAM_ID` | `--team-id` |
| `BUNDLE_ID` | Optional. Picks the app inside a disk image or zip with several apps. | (empty) | `BUNDLE_ID` | `--bundle-id` |
| `QUIT_APP` | Quit the app first if it is running and needs replacing. Default false. | `false` | `QUIT_APP` | `--quit-app` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). As an action it also accepts `DRY_RUN`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./install-mac-app.sh --download-url https://example.com/Widget.dmg --team-id ABCDE12345
```

```bash
sudo ./install-mac-app.sh --download-url https://example.com/widget.pkg --sha256 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08
```

### In an RMM

Add the script to your RMM as a shell script (`#!/bin/bash`) and run it as root on macOS or Linux. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `DOWNLOAD_URL`).
- **Command-line arguments:** `--download-url value`.
- **No variables at all:** edit the `DEFAULT_` line for that input near the top of the script body.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Installed Widget 2.1 (com.example.widget); Team ID ABCDE12345 verified
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

Every change is also logged to `/Library/Logs/MSPOutpost/install-mac-app.log` on macOS or `/var/log/mspoutpost/install-mac-app.log` on Linux.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/install-mac-app

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
