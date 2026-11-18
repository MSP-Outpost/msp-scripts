# End network isolation and restore the firewall

> Ends the network isolation made by enable-network-isolation and checks the PC is back on the network.

| | |
|---|---|
| Script | `disable-network-isolation.ps1` |
| Type | Action |
| Category | AV / EDR & incident response |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | Deletes the Windows Firewall rule group MSP Outpost Isolation and restores the saved firewall profile settings (or a policy backup) |
| Risk | Low |
| Reboot | Never |
| Typical runtime | 10 to 40 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS. It undoes enable-network-isolation exactly:

- saves the firewall policy as it is now (netsh advfirewall export, kept in %ProgramData%\MSPOutpost\Backups\disable-network-isolation);
- deletes the Windows Firewall rule group "MSP Outpost Isolation";
- puts the Domain, Private and Public profiles back to the settings enable-network-isolation saved before it isolated the PC (firewall on or off, default inbound and outbound action, inbound rules). When no saved settings exist it sets the default outbound action to Allow and lets inbound allow rules apply again, which is how Windows ships, and says so in a WARNING;
- switches the outbound allow rules that the isolation switched off back on (the list is in the saved state) and deletes the auto-undo scheduled task MSPOutpost-IsolationAutoUndo if enable-network-isolation made one;
- deletes its saved state file;
- tests a connection to the first host that was allowed, then to the default gateway (ping, a TCP connect or refusal on 443, 80 or 53, or a DNS reply). If nothing answers, it ends in ERROR: the firewall is restored, so look at the network itself.

BackupPath is the other way back: the path of a policy backup made by enable-network-isolation (the Backups folder named in its change log, a .wfw file; its path is also in BackupFile inside %ProgramData%\MSPOutpost\Isolation\state.json). The WHOLE firewall policy is then restored from it (netsh advfirewall import), which also undoes any firewall rule changed since.

If this PC is not isolated (no rule group and no saved state), it changes nothing and says so. It leaves a firewall that someone else set to block outbound traffic alone and warns about it.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `BackupPath` | Optional. A .wfw policy backup to restore with netsh advfirewall import instead of the saved profile settings. | (empty) | `BackupPath` or `BACKUP_PATH` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\disable-network-isolation.ps1
```

Removes the isolation rules, restores the saved firewall settings and tests the network.

```powershell
.\disable-network-isolation.ps1 -BackupPath "C:\ProgramData\MSPOutpost\Backups\enable-network-isolation\20261116-141500\C__ProgramData_MSPOutpost_Isolation_policy-20261116-141459.wfw"
```

Restores the whole firewall policy from that backup.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `BackupPath`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Isolation removed; firewall restored; connection ok (192.168.1.1 via ping)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\disable-network-isolation.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/disable-network-isolation

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
