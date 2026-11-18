# Remote Login or Screen Sharing is on

> Alerts when Remote Login (SSH), Screen Sharing or Remote Management (ARD) is on and you did not allow it.

| | |
|---|---|
| Script | `test-mac-remote-access.sh` |
| Type | Monitor |
| Category | macOS management |
| Platforms | macOS 13+ |
| Runs as | root |
| Requires | bash 3.2, root recommended |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 5 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. It reads whether three remote-access services are running on this Mac and alerts (exit 1) for each one that is on while its ALLOW_* input is false: Remote Login        SSH (systemsetup -getremotelogin; when macOS refuses that without Full Disk Access, the launchd job com.openssh.sshd is read instead). Screen Sharing      the launchd job com.apple.screensharing is loaded. Remote Management   Apple Remote Desktop: the ARDAgent process or a listener on port 3283.

Pair it with disable-mac-remote-access, which turns them off. If YOUR support tool is one of these (for example you manage Macs over SSH), set the matching ALLOW_* input to true.

## Inputs

| Input | Meaning | Default | Environment variable | Argument |
|---|---|---|---|---|
| `ALLOW_REMOTE_LOGIN` | Remote Login (SSH) may be on. Default false. | `false` | `ALLOW_REMOTE_LOGIN` | `--allow-remote-login` |
| `ALLOW_SCREEN_SHARING` | Screen Sharing may be on. Default false. | `false` | `ALLOW_SCREEN_SHARING` | `--allow-screen-sharing` |
| `ALLOW_REMOTE_MANAGEMENT` | Remote Management (ARD) may be on. Default false. | `false` | `ALLOW_REMOTE_MANAGEMENT` | `--allow-remote-management` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./test-mac-remote-access.sh
```

```bash
ALLOW_REMOTE_LOGIN=true sudo -E ./test-mac-remote-access.sh
```

### In an RMM

Add the script to your RMM as a shell script (`#!/bin/bash`) and run it as root on macOS or Linux. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `ALLOW_REMOTE_LOGIN`).
- **Command-line arguments:** `--allow-remote-login value`.
- **No variables at all:** edit the `DEFAULT_` line for that input near the top of the script body.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Remote Login is on; Screen Sharing is on
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Service`, `State`, `IsAllowed`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/test-mac-remote-access

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
