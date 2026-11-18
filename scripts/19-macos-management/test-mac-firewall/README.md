# Mac firewall is off

> Alerts when the Mac's application firewall is off, or stealth mode is off.

| | |
|---|---|
| Script | `test-mac-firewall.sh` |
| Type | Monitor |
| Category | macOS management |
| Platforms | macOS 13+ |
| Runs as | root or a user |
| Requires | bash 3.2, socketfilterfw |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 5 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. It asks the macOS application firewall (socketfilterfw) whether it is on, whether stealth mode is on (the Mac does not answer pings or probes on closed ports) and whether "block all incoming connections" is set, and alerts (exit 1) when the firewall is off or, when REQUIRE_STEALTH_MODE is true, when stealth mode is off. Block all is reported only; it is a stricter choice some Macs make on purpose. A Mac whose firewall tool is missing is skipped. Pair it with enable-mac-firewall, which turns the firewall (and stealth mode) on.

## Inputs

| Input | Meaning | Default | Environment variable | Argument |
|---|---|---|---|---|
| `REQUIRE_STEALTH_MODE` | Alert when stealth mode is off. Default true. | `true` | `REQUIRE_STEALTH_MODE` | `--require-stealth-mode` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./test-mac-firewall.sh
```

```bash
sudo ./test-mac-firewall.sh --require-stealth-mode false
```

### In an RMM

Add the script to your RMM as a shell script (`#!/bin/bash`) and run it as root on macOS or Linux. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `REQUIRE_STEALTH_MODE`).
- **Command-line arguments:** `--require-stealth-mode value`.
- **No variables at all:** edit the `DEFAULT_` line for that input near the top of the script body.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Firewall off; stealth mode off
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Setting`, `Value`, `Healthy`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/test-mac-firewall

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
