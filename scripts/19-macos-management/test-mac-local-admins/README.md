# Unapproved administrators on this Mac

> Alerts when a Mac has administrator accounts that are not approved, or more than you allow.

| | |
|---|---|
| Script | `test-mac-local-admins.sh` |
| Type | Monitor |
| Category | macOS management |
| Platforms | macOS 13+ |
| Runs as | root or a user |
| Requires | bash 3.2, dscl |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 5 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. It lists the members of the local admin group (dscl, /Groups/admin) and alerts (exit 1) when

- ALLOWED_ADMINS is set and an admin account is not on it, or
- there are more admin accounts than MAX_ADMINS.

The root account and system accounts (user ID below 500, such as _mbsetupuser on a fresh Mac) are shown but never counted or flagged. Each row shows the account, its user ID, whether it is the signed-in console user, and whether it is hidden. Account names are compared ignoring case. Admin rights that come only from a nested group are not listed. Pair it with remove-mac-local-admin-members, which demotes the unapproved ones.

## Inputs

| Input | Meaning | Default | Environment variable | Argument |
|---|---|---|---|---|
| `ALLOWED_ADMINS` | Account short names allowed to be admins, comma-separated, e.g. "msp-admin, jsmith". Default empty: no name check. | (empty) | `ALLOWED_ADMINS` | `--allowed-admins` |
| `MAX_ADMINS` | Alert when there are more than N admin accounts (root not counted). 0 = no limit. Default 2. | `2` | `MAX_ADMINS` | `--max-admins` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./test-mac-local-admins.sh --allowed-admins "msp-admin, jsmith"
```

```bash
ALLOWED_ADMINS=msp-admin MAX_ADMINS=1 ./test-mac-local-admins.sh
```

### In an RMM

Add the script to your RMM as a shell script (`#!/bin/bash`) and run it as root on macOS or Linux. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `ALLOWED_ADMINS`).
- **Command-line arguments:** `--allowed-admins value`.
- **No variables at all:** edit the `DEFAULT_` line for that input near the top of the script body.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
1 of 3 admin account(s) not approved: jsmith
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Account`, `UserId`, `IsConsoleUser`, `IsHidden`, `IsAllowed`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/test-mac-local-admins

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
