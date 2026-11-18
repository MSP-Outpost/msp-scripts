# Tell the user something on a Mac - dialog or notification

> Shows a message to the person at the Mac: a dialog with buttons (and which one they pressed) or a notification.

| | |
|---|---|
| Script | `new-mac-user-notification.sh` |
| Type | Action |
| Category | End-user communication & self-service |
| Platforms | macOS 13+ |
| Runs as | root |
| Requires | bash 3.2, root, a user signed in at the console |
| Changes | Shows a dialog or notification on the signed-in user's screen |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Up to the timeout (default 60 seconds) |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT CHANGES THINGS (it puts a window or banner on the user's screen). It finds the user signed in at the console and shows MESSAGE inside that user's session with osascript. STYLE=Dialog (default) shows a window titled TITLE with 1 to 3 BUTTONS and waits up to TIMEOUT_SECONDS; the answer says which button was pressed, or that nobody answered. STYLE= Notification shows a banner in Notification Centre and does not wait; macOS may hide banners that Script Editor is not allowed to show, so use Dialog when the message must be seen. A line break is written \n in MESSAGE. It shows nothing and ends SKIPPED when nobody is signed in at the console. It changes no setting and starts no app. It never waits longer than the timeout (plus a short margin).

## Inputs

| Input | Meaning | Default | Environment variable | Argument |
|---|---|---|---|---|
| `MESSAGE` | REQUIRED. What to say, up to 1000 characters. | (empty) | `MESSAGE` | `--message` |
| `TITLE` | Window title, up to 100 characters. Default "Message from IT". | `Message from IT` | `TITLE` | `--title` |
| `STYLE` | Dialog (default) or Notification. | `Dialog` | `STYLE` | `--style` |
| `BUTTONS` | Dialog buttons, 1 to 3, comma-separated. The first is the default. Default OK. | `OK` | `BUTTONS` | `--buttons` |
| `TIMEOUT_SECONDS` | Dialog: close after N seconds without an answer. 1-3600, default 60. | `60` | `TIMEOUT_SECONDS` | `--timeout-seconds` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). As an action it also accepts `DRY_RUN`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./new-mac-user-notification.sh --message "Restarting for updates in 10 minutes." --buttons "OK,Later"
```

```bash
sudo ./new-mac-user-notification.sh --message "Your backup finished." --style Notification
```

### In an RMM

Add the script to your RMM as a shell script (`#!/bin/bash`) and run it as root on macOS or Linux. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `MESSAGE`).
- **Command-line arguments:** `--message value`.
- **No variables at all:** edit the `DEFAULT_` line for that input near the top of the script body.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
jsmith pressed Later
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

Every change is also logged to `/Library/Logs/MSPOutpost/new-mac-user-notification.log` on macOS or `/var/log/mspoutpost/new-mac-user-notification.log` on Linux.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/new-mac-user-notification

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
