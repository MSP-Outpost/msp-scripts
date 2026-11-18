# Mac health and security summary

> One-screen health and security summary of a Mac: OS, SIP, Gatekeeper, FileVault, firewall, MDM, disk.

| | |
|---|---|
| Script | `get-mac-health-summary.sh` |
| Type | Report |
| Category | macOS management |
| Platforms | macOS 13+ |
| Runs as | root |
| Requires | bash 3.2, root recommended |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 15 seconds (up to the timeout when CHECK_UPDATES is true) |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. It collects, in one run: macOS version and build, model and chip, System Integrity Protection, Gatekeeper, FileVault, the application firewall and stealth mode, the XProtect data version, uptime, free space on the data volume, the battery's cycle count and condition (laptops only), MDM enrollment and, only when you ask for it, the number of pending software updates. Checking for updates (softwareupdate -l) contacts Apple and can take a minute or two, so CHECK_UPDATES defaults to false; when it is on, the check is stopped after UPDATE_TIMEOUT_SECONDS and the row says so. Run it as root (an RMM does) so every row can be read; a row that cannot be read says "Unavailable" instead of stopping the run. The answer is one line made for a custom field.

## Inputs

| Input | Meaning | Default | Environment variable | Argument |
|---|---|---|---|---|
| `CHECK_UPDATES` | Count pending software updates (slow, needs internet). Default false. | `false` | `CHECK_UPDATES` | `--check-updates` |
| `UPDATE_TIMEOUT_SECONDS` | Stop the update check after N seconds. 10-1800. Default 120. | `120` | `UPDATE_TIMEOUT_SECONDS` | `--update-timeout-seconds` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./get-mac-health-summary.sh
```

```bash
sudo ./get-mac-health-summary.sh --check-updates true --output-format Json
```

### In an RMM

Add the script to your RMM as a shell script (`#!/bin/bash`) and run it as root on macOS or Linux. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `CHECK_UPDATES`).
- **Command-line arguments:** `--check-updates value`.
- **No variables at all:** edit the `DEFAULT_` line for that input near the top of the script body.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
macOS 15.1 (24B83); SIP on; Gatekeeper on; FileVault on; firewall on; MDM yes; up 6d; 212 GB free
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Item`, `Value`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/get-mac-health-summary

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
