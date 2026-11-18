# Rename the computer - fixed name or PREFIX-SERIAL pattern

> Renames a workgroup or Entra ID joined PC to a fixed name or a pattern such as PREFIX-SERIAL, without restarting.

| | |
|---|---|
| Script | `set-computer-name.ps1` |
| Type | Action |
| Category | Onboarding & provisioning |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1; administrator rights; a workgroup or Entra ID joined PC |
| Changes | Computer name (takes effect at the next restart) |
| Risk | Low |
| Reboot | Required |
| Typical runtime | Under 10 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS. It sets the computer name and nothing else: it does not restart the PC, change the domain, the DNS suffix, the RMM agent or any user. The new name takes effect at the next restart; until then Windows keeps the old name and the pending name is stored. The answer says a restart is needed (Reboot: Required).

Give the name one of two ways. NewName is for ONE device: a NewName set site-wide in an RMM would try to give every PC the same name (a duplicate name breaks the network), so use Pattern for a fleet:

- NewName: the exact name,
- Pattern: a name built from tokens, for example {PREFIX}-{SERIAL}. {PREFIX} is the Prefix input. {SERIAL} is the BIOS serial number with everything except letters and digits removed, in capitals. When the name would be longer than 15 characters, the serial is shortened from the front (its last characters are kept, as they are the most distinct), and the rest of the pattern is never cut. A serial that is empty or a maker's placeholder ("To be filled by O.E.M.", "0", "Default string") is an error, because two PCs would get the same name.

A computer name must be 1 to 15 characters: letters, digits and hyphens, not starting or ending with a hyphen, and not only digits (the NetBIOS limit). Names are stored in capitals by Windows; the comparison ignores case.

Idempotent: when the PC already has the wanted name, or the rename is already queued for the next restart, it changes nothing and says so. When the PC has the wanted name but another rename is queued, the queued rename is cancelled by setting the wanted name again.

SKIPPED on a PC joined to an Active Directory domain: renaming a domain computer needs domain credentials (and changes the AD account), which this script does not handle. Rename those from AD, or unjoin first. Needs administrator rights. Use DryRun=true to see the name it would set.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `NewName` | The exact new computer name. Do not combine with Pattern. | (empty) | `NewName` or `NEW_NAME` |
| `Pattern` | A name pattern with the tokens {PREFIX} and {SERIAL}, for example {PREFIX}-{SERIAL}. Do not combine with NewName. Other text in the pattern must be letters, digits or hyphens. | (empty) | `Pattern` or `PATTERN` |
| `Prefix` | Text for the {PREFIX} token: letters, digits and hyphens, up to 14 characters. Required when the Pattern uses {PREFIX}. | (empty) | `Prefix` or `PREFIX` |
| `AllowServers` | Windows Server and domain controllers are skipped unless this is true, because renaming a server breaks what depends on its name. true or false. Default false. | `false` | `AllowServers` or `ALLOW_SERVERS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\set-computer-name.ps1 -NewName ACME-FRONTDESK1 -DryRun true
```

Shows the rename without making it.

```powershell
.\set-computer-name.ps1 -Pattern "{PREFIX}-{SERIAL}" -Prefix ACME
```

Names the PC ACME- followed by its BIOS serial number (shortened to fit 15 characters).

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `NewName`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Renamed DESKTOP-4F2K9 to ACME-7XK2QY3; restart needed to finish
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\set-computer-name.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/set-computer-name

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
