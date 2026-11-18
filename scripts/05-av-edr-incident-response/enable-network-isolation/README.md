# Isolate a PC from the network but keep the RMM

> Ransomware containment: blocks all network traffic except to your RMM, EDR and DNS, using Windows Firewall.

| | |
|---|---|
| Script | `enable-network-isolation.ps1` |
| Type | Action |
| Category | AV / EDR & incident response |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, Windows Firewall service running and no third-party firewall |
| Changes | Creates the Windows Firewall rule group MSP Outpost Isolation, blocks all other inbound and outbound traffic on all profiles, switches off other enabled outbound allow rules, saves the old firewall settings, optionally registers a scheduled task that undoes it |
| Risk | **High** |
| Reboot | Never |
| Typical runtime | 10 to 60 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=enable-network-isolation`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\enable-network-isolation.log`.
- Before it edits or deletes configuration, it copies it to `%ProgramData%\MSPOutpost\Backups\enable-network-isolation\<UTC time>\` and keeps the last 10 runs. If a backup fails, nothing is changed.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS AND CAN CUT THIS PC OFF THE NETWORK. It isolates a PC you suspect is infected while keeping your management tools working:

- saves the firewall policy first (netsh advfirewall export, kept in %ProgramData%\MSPOutpost\Backups\enable-network-isolation) and the current settings of the Domain, Private and Public profiles (%ProgramData%\MSPOutpost\Isolation\state.json);
- creates the Windows Firewall rule group "MSP Outpost Isolation": one rule that allows outbound traffic to every address in AllowedHosts, and one outbound rule for each program in AllowedPrograms;
- on all three profiles switches the firewall on, sets the default outbound action to Block, and blocks inbound traffic including the inbound allow rules (like the "Block all incoming connections" setting).

Safeguards against locking yourself out:

- the RMM agent that started this script (the service program found in its own process chain) is allowed automatically, in addition to AllowedPrograms. A real run with no agent found and AllowedPrograms empty stops with an error before changing anything;
- BEFORE isolating, the FIRST host in AllowedHosts must answer (ping, a TCP connect or refusal on 443, 80 or 53, or a DNS reply; at most 15 seconds). If it does not, nothing is changed;
- AFTER isolating, the same test runs again (at most 30 seconds). If it fails, a first isolation rolls back at once (rule group removed, saved settings restored) and ends in ERROR. A failed RERUN leaves the isolation that was already in place and only removes its own new rules;
- AutoUndoMinutes above 0 registers a one-shot SYSTEM scheduled task (MSPOutpost-IsolationAutoUndo) that undoes the isolation by itself after that many minutes, so a mistake cannot be permanent. The answer says so. disable-network-isolation removes the task.

Windows keeps every ENABLED outbound allow rule in force under default Block, which would leave most programs connected. So the script also switches off every other enabled outbound allow rule in this PC's own policy (not the two DHCP client rules), lists them in the saved state, and the undo switches exactly those on again. Group Policy rules cannot be switched off from here.

Host names (FQDNs) are resolved to IP addresses when the script runs, with the DNS the PC has at that moment, and the firewall rules hold those addresses. If a service later moves to other addresses, the rules do not follow: run this script again (it rebuilds the rules). Include your DNS servers in AllowedHosts.

A third-party firewall registered in Windows Security Center makes this script end SKIPPED: Windows Firewall rules would mean nothing there. What it does NOT block: the DHCP client rules stay on; traffic to the loopback address is never filtered by Windows Firewall; and a domain Group Policy that controls the firewall can override these settings (the run then fails its own check, rolls back and says so). It does not disable network adapters, and it leaves signed-in users signed in: they lose network access except to the allowed hosts. Servers are refused unless IncludeServers is true.

Undo with disable-network-isolation. Running this script again with the same inputs and the isolation in place changes nothing and says so.

Risk is High: it changes nothing unless DryRun is false AND Approve is set to enable-network-isolation. The dry run resolves the host names and lists every rule it would create.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `AllowedHosts` | Where this PC may still send traffic: host names (FQDNs), IP addresses or CIDR ranges of your RMM, EDR and DNS servers, separated by commas, semicolons or new lines. The FIRST entry must be one host name or IP address (it is used for the test connection). Required. | (empty) | `AllowedHosts` or `ALLOWED_HOSTS` |
| `AllowedPrograms` | Full paths of programs allowed to use the network to any address (for example the RMM agent executables), separated by commas, semicolons or new lines. Each file must exist. Default empty. | (empty) | `AllowedPrograms` or `ALLOWED_PROGRAMS` |
| `AutoUndoMinutes` | 0 (default) = no automatic undo. 1 to 1440 = a scheduled task removes the isolation by itself after that many minutes. | `0` | `AutoUndoMinutes` or `AUTO_UNDO_MINUTES` |
| `IncludeServers` | true to allow isolating a Windows Server or domain controller. Default false. | `false` | `IncludeServers` or `INCLUDE_SERVERS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\enable-network-isolation.ps1 -AllowedHosts "rmm.example.com,192.168.1.1" -AllowedPrograms "C:\Program Files\NinjaRMMAgent\NinjaRMMAgent.exe"
```

Dry run: shows the rules that would isolate the PC but keep the RMM.

```powershell
.\enable-network-isolation.ps1 -AllowedHosts "192.168.1.1,rmm.example.com" -DryRun false -Approve enable-network-isolation
```

Isolates the PC, keeping traffic to the DNS server 192.168.1.1 and the RMM.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `AllowedHosts`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `enable-network-isolation`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Isolated: traffic allowed only to 2 address(es) (192.168.1.1) and 1 program(s); 140 other outbound rule(s) disabled; test connection ok (192.168.1.1 via dns)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\enable-network-isolation.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/enable-network-isolation

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
