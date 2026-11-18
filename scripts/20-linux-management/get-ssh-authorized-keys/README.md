# Who can SSH in? List authorized keys

> Lists every SSH public key allowed to log in to a Linux server, per account, with its fingerprint and comment.

| | |
|---|---|
| Script | `get-ssh-authorized-keys.sh` |
| Type | Report |
| Category | Linux management |
| Platforms | Ubuntu 22.04+, Debian 12+, RHEL/Rocky/Alma 9+ |
| Runs as | root |
| Requires | bash 3.2, root, getent, ssh-keygen (openssh-client) |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 10 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. It reads the authorized-keys files of every account that has a home folder (root included): the locations from the effective sshd setting AuthorizedKeysFile (default .ssh/authorized_keys and .ssh/authorized_keys2; %h, %u and %U are expanded), and prints one row per key: account, file, key type, size, SHA256 fingerprint, comment, any restrictions in front of the key (command="..." and so on). With ALLOWED_FINGERPRINTS set, each row says whether the key is on that list, and the answer counts the keys that are not. It never alerts: pair it with remove-ssh-authorized-key to remove a key by fingerprint. Not covered: keys handed out by AuthorizedKeysCommand (LDAP, FreeIPA, identity providers), SSH certificate authorities (TrustedUserCAKeys) and keys of accounts whose home folder is not on this machine. Tested on Ubuntu 24.04 (Arm64). Debian 12 and RHEL/Rocky/Alma 9 use the same files; they are written for but not yet run.

## Inputs

| Input | Meaning | Default | Environment variable | Argument |
|---|---|---|---|---|
| `ALLOWED_FINGERPRINTS` | SHA256 fingerprints that are approved (SHA256:abc...), comma-separated. Default none. | (empty) | `ALLOWED_FINGERPRINTS` | `--allowed-fingerprints` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./get-ssh-authorized-keys.sh
```

```bash
sudo ALLOWED_FINGERPRINTS="SHA256:Qm3...,SHA256:x9K..." OUTPUT_FORMAT=Csv ./get-ssh-authorized-keys.sh
```

### In an RMM

Add the script to your RMM as a shell script (`#!/bin/bash`) and run it as root on macOS or Linux. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `ALLOWED_FINGERPRINTS`).
- **Command-line arguments:** `--allowed-fingerprints value`.
- **No variables at all:** edit the `DEFAULT_` line for that input near the top of the script body.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
7 key(s) in 3 file(s) for 3 account(s); 2 not on the allow list
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Account`, `File`, `Type`, `Bits`, `Fingerprint`, `Comment`, `Options`, `OnAllowList`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/get-ssh-authorized-keys

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
