# Drives missing - map network drives

> Maps network drives (X: to \\server\share) for the signed-in user, keeping them across sign-ins, and checks each one opens.

| | |
|---|---|
| Script | `set-mapped-drives.ps1` |
| Type | Action |
| Category | User profile & desktop config |
| Platforms | Windows 10, Windows 11 |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, a user signed in at the console, network access to the shares |
| Changes | Maps network drive letters for the signed-in user (saved in their profile when Persistent); with Replace, removes a drive mapped to a different path |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS. For the user signed in at the console (the script runs from SYSTEM and maps the drives in that user's own session, with that user's own rights), for every item in Mappings it:

- leaves a drive letter alone when it is already mapped to the same path and opens (OK),
- maps the letter to the share with net use; with Persistent true the mapping is saved in the user's profile and comes back at every sign-in,
- refuses the whole run, before changing anything, when a letter is already mapped to a DIFFERENT path (unless Replace is true: then that mapping is removed and replaced) or is a local disk or other non-network drive such as C: or a virtual disk,
- checks that the drive opens, and for persistent drives that the mapping is saved in the user's registry.

It uses the signed-in user's own credentials only: no user name or password is taken or stored, so the user needs access to the share. It maps the drives of the user signed in at the console only, never other users, and never touches files on the share.

NOT covered: mapping by group membership or per site (do that in Group Policy or Intune, or run this script with different Mappings per group in your RMM), and shares that need a different user name. Nobody signed in: SKIPPED. If a share cannot be reached (server off, VPN down, no rights), the run ends in an error naming the drive and the Windows message.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Mappings` | The drives to map: items like Z:=\\server\share, separated by commas or semicolons. The share may include a sub-folder (Z:=\\server\share\folder). Required. | (empty) | `Mappings` or `MAPPINGS` |
| `Persistent` | true (default) to keep the mappings across sign-ins; false to map them for this sign-in only. | `true` | `Persistent` or `PERSISTENT` |
| `Replace` | true to replace a drive letter that is mapped to a different path. Default false: such a letter ends the run in an error and nothing is changed. | `false` | `Replace` or `REPLACE` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\set-mapped-drives.ps1 -Mappings "S:=\\fileserver\shared,H:=\\fileserver\home"
```

Maps S: and H: for the signed-in user and keeps them across sign-ins.

```powershell
.\set-mapped-drives.ps1 -Mappings "S:=\\newserver\shared" -Replace true
```

Points S: at the new server even if S: is mapped to the old one.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Mappings`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Mapped 2 drive(s) for PC01\jsmith: S: H: (persistent)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\set-mapped-drives.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/set-mapped-drives

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
