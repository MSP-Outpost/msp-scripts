# Mac local admin password - create or rotate a hidden admin

> Creates or rotates a hidden managed admin account on a Mac and stores its new random password in a NinjaOne secure field.

| | |
|---|---|
| Script | `set-mac-local-admin-password.sh` |
| Type | Action |
| Category | macOS management |
| Platforms | macOS 13+ |
| Runs as | root |
| Requires | bash 3.2, root, dscl, dseditgroup, NinjaOne agent (ninjarmm-cli) with a secure custom field |
| Changes | Creates a hidden local administrator account if missing, sets a new random password on it, writes the password to a NinjaOne secure field |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | Under 10 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DRY_RUN=false` **and** `APPROVE=set-mac-local-admin-password`. Typing the script name is the deliberate step.
- It refuses to make more than `MAX_CHANGES` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `/Library/Logs/MSPOutpost/set-mac-local-admin-password.log` on macOS or `/var/log/mspoutpost/set-mac-local-admin-password.log` on Linux.
- Before it edits or deletes configuration, it copies it to `/Library/Application Support/MSPOutpost/Backups/set-mac-local-admin-password/<UTC time>/` on macOS or `/var/lib/mspoutpost/backups/set-mac-local-admin-password/<UTC time>/` on Linux, and keeps the last 10 runs. If a backup fails, nothing is changed.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. Risk is High, so it is a dry run unless you set BOTH DRY_RUN=false AND APPROVE=set-mac-local-admin-password. Every real run sets a NEW random password, so running it twice rotates it twice (the second value replaces the first in the field). What it does for ACCOUNT_NAME (default mspadmin):

- If the account does not exist, it creates it as a hidden administrator: a user ID below 500 (so it is not shown at the login window or in System Settings), IsHidden set, a private home folder under /var, and membership of the admin group.
- If it exists and is hidden, it makes sure it is an administrator and sets a new password.
- It REFUSES (nothing changed) when the account exists but is a visible account (user ID 500 or more, not hidden) or is the person signed in at the console: it will not take over somebody's own login.

The password is generated here from /dev/urandom (PASSWORD_LENGTH characters, at least one upper case, lower case, digit and symbol). It is handed to dscl on its standard input, never as a command-line argument, and written to the NinjaOne custom field named by RESULT_FIELD through ninjarmm-cli's standard input. It is NEVER printed, logged, exported or put in the answer. Make RESULT_FIELD a secure (secret) field in NinjaOne. Without RESULT_FIELD, with OUTPUT_FORMAT Answer, or where ninjarmm-cli is not found, it ends in ERROR before changing anything: on macOS a secret can only be stored through NinjaOne for now. If the field write fails after the password was changed, the run ends in ERROR and the password is lost: run it again to rotate to a stored one. Before changing group membership it copies the admin group record to /Library/Application Support/MSPOutpost/Backups/set-mac-local-admin-password/. SECURETOKEN AND FILEVAULT: an account made this way has NO SecureToken. macOS gives one only when an existing SecureToken administrator's credentials are supplied, and a root script has none. Such an account can administer the Mac and sign in over SSH or at a text login, but it cannot unlock FileVault at start-up and, on Apple Silicon, cannot authorise some macOS updates or enable FileVault for other users. Grant it a token by hand if you need that: sysadminctl -secureTokenOn <account> -password - -adminUser <token admin> -adminPassword -. Rotating the password of an account that already has a token is fine, but if FileVault is on and this account is a token holder, its FileVault password changes with it. Old password hashes are not backed up. Services that logged in with the old password stop working.

## Inputs

| Input | Meaning | Default | Environment variable | Argument |
|---|---|---|---|---|
| `ACCOUNT_NAME` | Short name of the managed admin. Letters, digits, . _ -; starts with a letter or underscore. Default mspadmin. | `mspadmin` | `ACCOUNT_NAME` | `--account-name` |
| `PASSWORD_LENGTH` | Length of the generated password. 16-64. Default 24. | `24` | `PASSWORD_LENGTH` | `--password-length` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). As an action it also accepts `DRY_RUN`, `APPROVE` and `MAX_CHANGES`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./set-mac-local-admin-password.sh --result-field MacAdminPassword
```

```bash
sudo ./set-mac-local-admin-password.sh --result-field MacAdminPassword --dry-run=false --approve=set-mac-local-admin-password
```

### In an RMM

Add the script to your RMM as a shell script (`#!/bin/bash`) and run it as root on macOS or Linux. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `ACCOUNT_NAME`).
- **Command-line arguments:** `--account-name value`.
- **No variables at all:** edit the `DEFAULT_` line for that input near the top of the script body.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DRY_RUN` to `false` and `APPROVE` to `set-mac-local-admin-password`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Rotated password for hidden admin mspadmin; password written to field MacAdminPassword
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

Every change is also logged to `/Library/Logs/MSPOutpost/set-mac-local-admin-password.log` on macOS or `/var/log/mspoutpost/set-mac-local-admin-password.log` on Linux.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/set-mac-local-admin-password

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
