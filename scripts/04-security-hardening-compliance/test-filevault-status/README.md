# FileVault is off or has no recovery key

> Alerts when FileVault is off or a Mac has no recovery key.

| | |
|---|---|
| Script | `test-filevault-status.sh` |
| Type | Monitor |
| Category | Security hardening & compliance |
| Platforms | macOS 13+ |
| Runs as | root |
| Requires | bash 3.2, root, fdesetup |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 5 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. It runs fdesetup to read whether FileVault disk encryption is on (or encrypting, decrypting, or only waiting for the next login: "deferred enablement"), and whether the Mac has a personal recovery key and an institutional recovery key. It alerts (exit 1) when FileVault is off, when it is being turned off, or when it is on but there is no recovery key of either kind. It never prints a key. A Mac that is still encrypting counts as healthy: the data is protected as it is processed, and the answer says how far along it is. A Mac does not tell us where a recovery key was sent. "A personal key exists" is what fdesetup can say; whether your MDM holds a copy has to be checked in the MDM. A Mac that has no FileVault at all (some virtual machines) is skipped, not alerted. Run as root (an RMM does). Reading the recovery key state needs root.

## Inputs

| Input | Meaning | Default | Environment variable | Argument |
|---|---|---|---|---|
| `ALERT_WHEN_OFF` | Alert when FileVault is off. Default true. | `true` | `ALERT_WHEN_OFF` | `--alert-when-off` |
| `REQUIRE_RECOVERY_KEY` | Alert when FileVault is on but no recovery key exists. Default true. | `true` | `REQUIRE_RECOVERY_KEY` | `--require-recovery-key` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./test-filevault-status.sh
```

```bash
sudo ./test-filevault-status.sh --require-recovery-key false
```

### In an RMM

Add the script to your RMM as a shell script (`#!/bin/bash`) and run it as root on macOS or Linux. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `ALERT_WHEN_OFF`).
- **Command-line arguments:** `--alert-when-off value`.
- **No variables at all:** edit the `DEFAULT_` line for that input near the top of the script body.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
FileVault on; personal recovery key present; no institutional key
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Check`, `Value`, `Healthy`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/test-filevault-status

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
