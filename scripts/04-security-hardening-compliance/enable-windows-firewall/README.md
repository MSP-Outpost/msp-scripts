# Windows Firewall is off - turn it on and block inbound

> Turns on the Domain, Private and Public Windows Firewall profiles and sets default inbound to Block, unless Group Policy controls them.

| | |
|---|---|
| Script | `enable-windows-firewall.ps1` |
| Type | Action |
| Category | Security hardening & compliance |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1; NetSecurity module; administrator rights |
| Changes | Turns Windows Firewall profiles on and sets default inbound to Block (local settings only); starts the firewall service; saves a backup of the firewall policy first |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS. It reads the Domain, Private and Public firewall profiles twice: as they are in force (the active store, which includes Group Policy and MDM) and as they are set on this PC (the persistent store). For each profile that is off, or that allows inbound connections by default, it:

- saves the firewall policy first: a registry export of HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy and a netsh export (firewall-policy.wfw, restorable with "netsh advfirewall import") in the MSPOutpost backup folder,
- turns the profile on and, when BlockInbound is true, sets its default inbound action to Block,
- starts the Windows Defender Firewall service (MpsSvc) when it is stopped.

It changes the local settings only. When Group Policy (or MDM) sets a value that is not what is wanted, that profile is reported as "managed by Group Policy" and left alone: the script never fights a policy. It never adds, edits or deletes a firewall rule and never changes outbound defaults. It does not look at third-party firewall products: use test-firewall-profiles to see those.

It is skipped on servers unless AllowServers is true, and when Windows Security Center lists an enabled firewall product that is not Microsoft's (that product is doing the job).

Inbound Block is Windows' own default; turning it back on does not remove any Allow rule, so the remote desktop, file sharing and other rules that are enabled stay enabled.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `BlockInbound` | true (default) to also set the default inbound action of each profile to Block; false to only turn the profiles on. | `true` | `BlockInbound` or `BLOCK_INBOUND` |
| `AllowServers` | false (default): on a server the script does nothing and says so, because blocking inbound on a server that ran with the firewall off can cut off SQL and line-of-business ports. true to act on servers too (check the open ports first). | `false` | `AllowServers` or `ALLOW_SERVERS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\enable-windows-firewall.ps1 -DryRun true
```

Lists the profiles it would turn on or set to Block inbound.

```powershell
.\enable-windows-firewall.ps1 -BlockInbound false
```

Turns profiles on but leaves their default inbound action as it is.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `BlockInbound`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Public: turned on; Private: default inbound set to Block; Domain managed by Group Policy
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\enable-windows-firewall.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/enable-windows-firewall

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
