# Unapproved administrators on this Mac - demote them

> Demotes every administrator on a Mac who is not on your approved list to a standard user.

| | |
|---|---|
| Script | `remove-mac-local-admin-members.sh` |
| Type | Action |
| Category | macOS management |
| Platforms | macOS 13+ |
| Runs as | root |
| Requires | bash 3.2, root, dscl, dseditgroup |
| Changes | Removes accounts from the local admin group (the accounts stay as standard users) |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | Under 10 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DRY_RUN=false` **and** `APPROVE=remove-mac-local-admin-members`. Typing the script name is the deliberate step.
- It refuses to make more than `MAX_CHANGES` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `/Library/Logs/MSPOutpost/remove-mac-local-admin-members.log` on macOS or `/var/log/mspoutpost/remove-mac-local-admin-members.log` on Linux.
- Before it edits or deletes configuration, it copies it to `/Library/Application Support/MSPOutpost/Backups/remove-mac-local-admin-members/<UTC time>/` on macOS or `/var/lib/mspoutpost/backups/remove-mac-local-admin-members/<UTC time>/` on Linux, and keeps the last 10 runs. If a backup fails, nothing is changed.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. Risk is High, so it is a dry run unless you set BOTH DRY_RUN=false AND APPROVE=remove-mac-local-admin-members (typing the script name is the deliberate step), and it refuses to demote more accounts than MAX_CHANGES (default 25) in one run. Look at the dry-run list first, then run it for real. It reads the members of the local admin group and removes each one that is not in ALLOWED_ADMINS (dseditgroup). The account itself is not deleted, not disabled, not signed out and keeps its files, SecureToken and FileVault unlock rights; it just stops being an administrator. Before changing anything it copies the admin group's directory record (/var/db/dslocal/nodes/Default/groups/admin.plist) to /Library/Application Support/MSPOutpost/Backups/remove-mac-local-admin-members/. Always kept, whatever ALLOWED_ADMINS says: root; accounts with a user ID below 500 (system accounts); and the signed-in console user, unless DEMOTE_CONSOLE_USER is true (signing a person out of their admin rights mid-session is surprising, so it is off by default). The last administrator is never removed: a real run refuses, changing nothing, when no kept administrator with a user ID of 500 or more would remain, so the Mac is never left without one. The dry run only warns. ALLOWED_ADMINS entries are plain account short names, matched ignoring case (no wildcards). An entry that is not an admin on this Mac is only a warning, so one list can serve many Macs. Admin rights that come only from a nested group are not seen. Demoting an account does not touch its SecureToken. A standard user with a SecureToken can still unlock FileVault.

## Inputs

| Input | Meaning | Default | Environment variable | Argument |
|---|---|---|---|---|
| `ALLOWED_ADMINS` | Account short names that stay admin, comma-separated, e.g. "msp-admin, jsmith". Default empty: only root and the console user stay. | (empty) | `ALLOWED_ADMINS` | `--allowed-admins` |
| `DEMOTE_CONSOLE_USER` | Also demote the signed-in console user when not approved. Default false. | `false` | `DEMOTE_CONSOLE_USER` | `--demote-console-user` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). As an action it also accepts `DRY_RUN`, `APPROVE` and `MAX_CHANGES`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./remove-mac-local-admin-members.sh --allowed-admins "msp-admin"
```

```bash
sudo ./remove-mac-local-admin-members.sh --allowed-admins "msp-admin" --dry-run=false --approve=remove-mac-local-admin-members
```

### In an RMM

Add the script to your RMM as a shell script (`#!/bin/bash`) and run it as root on macOS or Linux. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `ALLOWED_ADMINS`).
- **Command-line arguments:** `--allowed-admins value`.
- **No variables at all:** edit the `DEFAULT_` line for that input near the top of the script body.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DRY_RUN` to `false` and `APPROVE` to `remove-mac-local-admin-members`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Removed 2 account(s) from the admin group: jsmith, temp1; kept: root, msp-admin
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

Every change is also logged to `/Library/Logs/MSPOutpost/remove-mac-local-admin-members.log` on macOS or `/var/log/mspoutpost/remove-mac-local-admin-members.log` on Linux.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/remove-mac-local-admin-members

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
