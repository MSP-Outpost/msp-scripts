# Who has root? Unexpected sudo or UID 0 accounts

> Alerts when an account other than the ones you approve has root rights on a Linux server (sudoers, sudo/wheel/admin groups, extra UID 0).

| | |
|---|---|
| Script | `test-linux-privileged-users.sh` |
| Type | Monitor |
| Category | Linux management |
| Platforms | Ubuntu 22.04+, Debian 12+, RHEL/Rocky/Alma 9+ |
| Runs as | root |
| Requires | bash 3.2, root, getent, awk |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 5 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. It lists every account that can act as root:

- members of the groups sudo, wheel and admin (primary and secondary),
- users and groups named in /etc/sudoers and in /etc/sudoers.d (files whose names contain a dot or end in ~ are ignored, as sudo does), with User_Alias names expanded and a rule for ALL counted as everyone,
- accounts other than root with UID 0.

Each row says how the account gets its rights, whether the rule covers every command (Scope all) or only some (Scope limited), and whether it needs no password (NoPassword, the NOPASSWD tag). It alerts (exit 1) when an account with Scope all is not in ALLOWED_ACCOUNTS. root is always allowed. A rule that only lets someone run a few commands (Scope limited) is listed but never alerts. REQUIRE_PASSWORD=true also alerts on an allowed account that can use sudo without a password. With no ALLOWED_ACCOUNTS, every account except root that has root rights alerts: list your own admins there (the account your RMM or you use). Limits: the sudoers files are read line by line, not run through visudo, so unusual syntax (host-specific rules, command aliases that hide ALL, netgroups) is read as written and may be missed. Accounts that exist only in LDAP or SSSD are included only if getent lists them. A rule set by Defaults or by AuthorizedKeysCommand is not an admin rule and is not read. Tested on Ubuntu 24.04 (Arm64). Debian 12 and RHEL/Rocky/Alma 9 use the same files and groups; they are written for but not yet run.

## Inputs

| Input | Meaning | Default | Environment variable | Argument |
|---|---|---|---|---|
| `ALLOWED_ACCOUNTS` | Accounts allowed to have root rights, comma-separated. root is always allowed. Default none. | (empty) | `ALLOWED_ACCOUNTS` | `--allowed-accounts` |
| `REQUIRE_PASSWORD` | true to also alert when an allowed account can use sudo without a password. Default false. | `false` | `REQUIRE_PASSWORD` | `--require-password` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./test-linux-privileged-users.sh --allowed-accounts "ops,backup-admin"
```

```bash
sudo ALLOWED_ACCOUNTS=ops REQUIRE_PASSWORD=true OUTPUT_FORMAT=Json ./test-linux-privileged-users.sh
```

### In an RMM

Add the script to your RMM as a shell script (`#!/bin/bash`) and run it as root on macOS or Linux. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `ALLOWED_ACCOUNTS`).
- **Command-line arguments:** `--allowed-accounts value`.
- **No variables at all:** edit the `DEFAULT_` line for that input near the top of the script body.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
2 account(s) with root rights outside the policy: bob (group sudo, NOPASSWD), toor (uid 0)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Account`, `Via`, `Source`, `Scope`, `NoPassword`, `Allowed`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/test-linux-privileged-users

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
