# Remove an old SSH key from every account

> Removes one SSH public key, by fingerprint or exact comment, from every account's authorized_keys on a Linux server.

| | |
|---|---|
| Script | `remove-ssh-authorized-key.sh` |
| Type | Action |
| Category | Linux management |
| Platforms | Ubuntu 22.04+, Debian 12+, RHEL/Rocky/Alma 9+ |
| Runs as | root |
| Requires | bash 3.2, root, getent, ssh-keygen (openssh-client) |
| Changes | Deletes the matching key line from authorized_keys files, after backing each file up |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | Under 10 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DRY_RUN=false` **and** `APPROVE=remove-ssh-authorized-key`. Typing the script name is the deliberate step.
- It refuses to make more than `MAX_CHANGES` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `/Library/Logs/MSPOutpost/remove-ssh-authorized-key.log` on macOS or `/var/log/mspoutpost/remove-ssh-authorized-key.log` on Linux.
- Before it edits or deletes configuration, it copies it to `/Library/Application Support/MSPOutpost/Backups/remove-ssh-authorized-key/<UTC time>/` on macOS or `/var/lib/mspoutpost/backups/remove-ssh-authorized-key/<UTC time>/` on Linux, and keeps the last 10 runs. If a backup fails, nothing is changed.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS, and a wrong removal can lock people out, so it is High risk: it does nothing but list what it would remove until BOTH DRY_RUN=false AND APPROVE=remove-ssh-authorized-key are set, and it will not remove more keys than MAX_CHANGES (default 25) in one run. It finds keys in the authorized-keys files of every account with a home folder (the locations from the effective sshd AuthorizedKeysFile setting, default .ssh/authorized_keys and .ssh/authorized_keys2). A key matches when it equals KEY_FINGERPRINT (SHA256:...) and/or KEY_COMMENT exactly; when both are given, both must match. There are no wildcards and no partial matches: a comment with * ? [ or fewer than 3 characters is refused. ACCOUNT limits the search to one account; without it the key is removed everywhere. Before any file is edited it is copied to /var/lib/mspoutpost/backups/remove-ssh-authorized-key/<UTC time>/ (the last 10 runs are kept). Only the matching key lines are deleted; every other line, the owner and the permissions stay as they were. After the edit each file is read again to prove the key is gone. Protected: when this script runs inside an SSH login (the RMM or you connecting over SSH), it never touches keys in the authorized_keys of the account that SSH login belongs to, because it cannot tell which of that account's keys opened the session and removing it could lock you out. Such matches are skipped with a warning; if they are the only matches the run stops with an error saying so. Run it from your RMM agent (not an SSH session), or from an SSH session of a different account, or remove that key by hand. There is no input to switch this off. Not covered: keys handed out by AuthorizedKeysCommand and SSH certificate authorities; a key that was removed here can still come back from whatever put it there (a provisioning tool, a user). Tested on Ubuntu 24.04 (Arm64). Debian 12 and RHEL/Rocky/Alma 9 use the same files; they are written for but not yet run.

## Inputs

| Input | Meaning | Default | Environment variable | Argument |
|---|---|---|---|---|
| `KEY_FINGERPRINT` | SHA256 fingerprint of the key to remove (SHA256:abc...). One of KEY_FINGERPRINT or KEY_COMMENT is required. | (empty) | `KEY_FINGERPRINT` | `--key-fingerprint` |
| `KEY_COMMENT` | Exact comment of the key to remove (the text after the key). At least 3 characters, no wildcards. | (empty) | `KEY_COMMENT` | `--key-comment` |
| `ACCOUNT` | Only look in this account. Default: every account. | (empty) | `ACCOUNT` | `--account` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). As an action it also accepts `DRY_RUN`, `APPROVE` and `MAX_CHANGES`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./remove-ssh-authorized-key.sh --key-fingerprint SHA256:Qm3xY...
```

```bash
sudo ./remove-ssh-authorized-key.sh --key-comment "old-laptop" --dry-run false --approve remove-ssh-authorized-key
```

### In an RMM

Add the script to your RMM as a shell script (`#!/bin/bash`) and run it as root on macOS or Linux. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `KEY_FINGERPRINT`).
- **Command-line arguments:** `--key-fingerprint value`.
- **No variables at all:** edit the `DEFAULT_` line for that input near the top of the script body.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DRY_RUN` to `false` and `APPROVE` to `remove-ssh-authorized-key`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Removed 2 key(s) SHA256:zZH4y0W2... from 2 file(s); backups in /var/lib/mspoutpost/backups/remove-ssh-authorized-key
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

Every change is also logged to `/Library/Logs/MSPOutpost/remove-ssh-authorized-key.log` on macOS or `/var/log/mspoutpost/remove-ssh-authorized-key.log` on Linux.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/remove-ssh-authorized-key

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
