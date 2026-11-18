# Turn on the Mac firewall and stealth mode

> Turns on the Mac's application firewall and stealth mode.

| | |
|---|---|
| Script | `enable-mac-firewall.sh` |
| Type | Action |
| Category | macOS management |
| Platforms | macOS 13+ |
| Runs as | root |
| Requires | bash 3.2, root, socketfilterfw |
| Changes | Turns on the application firewall and (optionally) stealth mode |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 5 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT CHANGES THINGS. It runs socketfilterfw to turn the macOS application firewall on (--setglobalstate on) and, when ENABLE_STEALTH_MODE is true, to turn stealth mode on (--setstealthmode on). It changes nothing else: no per-app rule, no "block all incoming" setting, no pf rules. A firewall that is already on in the stricter "block all" state is left alone. Before changing anything it copies the firewall settings (/Library/Preferences/com.apple.alf.plist) to /Library/Application Support/MSPOutpost/Backups/enable-mac-firewall/. Apps with a valid signature keep receiving connections (macOS allows signed apps by default); an unsigned server app may be asked to be allowed the next time it is used. Where a configuration profile manages the firewall, a change this script makes may be undone: the verify step then ends in ERROR and says so. It reads the state again after the change and ends in ERROR if it did not take. Run it twice and the second run says it is already on.

## Inputs

| Input | Meaning | Default | Environment variable | Argument |
|---|---|---|---|---|
| `ENABLE_STEALTH_MODE` | Also turn stealth mode on. Default true. | `true` | `ENABLE_STEALTH_MODE` | `--enable-stealth-mode` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). As an action it also accepts `DRY_RUN`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./enable-mac-firewall.sh
```

```bash
sudo ./enable-mac-firewall.sh --enable-stealth-mode false --dry-run=true
```

### In an RMM

Add the script to your RMM as a shell script (`#!/bin/bash`) and run it as root on macOS or Linux. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `ENABLE_STEALTH_MODE`).
- **Command-line arguments:** `--enable-stealth-mode value`.
- **No variables at all:** edit the `DEFAULT_` line for that input near the top of the script body.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Turned on: Firewall, Stealth mode
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

Every change is also logged to `/Library/Logs/MSPOutpost/enable-mac-firewall.log` on macOS or `/var/log/mspoutpost/enable-mac-firewall.log` on Linux.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/enable-mac-firewall

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
