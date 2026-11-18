# New Windows PC needs the standard settings - apply the MSP baseline

> Applies the standard safe baseline to a new Windows 10/11 PC: time zone, time sync, sleep on AC power, Fast Startup off, System Restore on and long file paths.

| | |
|---|---|
| Script | `set-windows-pc-baseline.ps1` |
| Type | Action |
| Category | Onboarding & provisioning |
| Platforms | Windows 10, Windows 11 |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | Time zone, Windows Time service and time server, sleep on AC power, Fast Startup, System Restore on the system drive, long file paths (registry values, service start type, power plan) |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT CHANGES THINGS. It checks six settings one by one and fixes only the ones that differ, so it is safe to run on a new PC, again later, or on a PC that is half set up. Nothing is rebooted, no user is signed out and no software is removed or installed.

The settings (each can be left alone with SkipSettings, using the name in brackets):

- Time zone (time-zone): set to TimeZone, a Windows time zone ID such as "Pacific Standard Time" ("tzutil /l" lists them). Left alone when TimeZone is empty, which is the default.
- Time sync (time-sync): the Windows Time service starts automatically and is running, the sync type is NTP and the time server is NtpServer (default time.windows.com; empty keeps the PC's current server). Skipped on a domain-joined PC, where the domain controller is the time source and must not be overridden.
- Sleep on AC power (sleep-on-ac): the active power plan puts the PC to sleep after SleepOnAcMinutes minutes on mains power (default 0 = never). The battery setting and the screen timeout are not touched.
- Fast Startup off (fast-startup): HiberbootEnabled = 0. Fast Startup makes "Shut down" a half-hibernate, which keeps pending updates and driver faults alive across what users think is a restart. Takes effect at the next shutdown.
- System Restore on (system-restore): System Protection is switched on for the system drive. Skipped when a policy disables System Restore.
- Long file paths (long-paths): LongPathsEnabled = 1, so paths longer than 260 characters work in apps that support it.

NOT in the baseline, on purpose: region, language and keyboard (those are per user and an RMM runs as SYSTEM, so the setting would land on the wrong account), removing consumer apps (remove-windows-bloatware), the firewall (enable-windows-firewall), disk encryption (enable-bitlocker) and the computer name (set-computer-name).

Before it changes a registry key it exports that key to %ProgramData%\MSPOutpost\Backups\set-windows-pc-baseline\<time>\ so the old values can be put back with "reg import". A setting that cannot be read on this PC (for example the sleep setting on some virtual machines) is skipped with a warning, not guessed.

Run it again afterwards: it says "Already set". Use DryRun=true to list what it would change.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TimeZone` | Windows time zone ID, for example "Pacific Standard Time" or "Eastern Standard Time". Default empty = leave the time zone alone. | (empty) | `TimeZone` or `TIME_ZONE` |
| `NtpServer` | Time server host name, for example time.windows.com. Default time.windows.com. Empty keeps the PC's current server and only makes sure the service runs. | `time.windows.com` | `NtpServer` or `NTP_SERVER` |
| `SleepOnAcMinutes` | Minutes of inactivity on AC power before the PC sleeps. Whole number, 0 to 1440; 0 means never. Default 0. | `0` | `SleepOnAcMinutes` or `SLEEP_ON_AC_MINUTES` |
| `SkipSettings` | Settings to leave alone, separated by commas: time-zone, time-sync, sleep-on-ac, fast-startup, system-restore, long-paths. Default none. | (empty) | `SkipSettings` or `SKIP_SETTINGS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\set-windows-pc-baseline.ps1 -TimeZone "Pacific Standard Time"
```

Applies the baseline and sets the time zone to Pacific.

```powershell
.\set-windows-pc-baseline.ps1 -DryRun true -SkipSettings "system-restore, sleep-on-ac"
```

Lists what would change, leaving System Restore and sleep alone.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `TimeZone`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Set 3 baseline setting(s): Fast Startup off, Long file paths, Time sync; 3 already set
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\set-windows-pc-baseline.log`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/set-windows-pc-baseline

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
