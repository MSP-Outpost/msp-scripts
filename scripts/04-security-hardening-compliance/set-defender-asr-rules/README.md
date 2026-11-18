# Defender attack surface reduction rules - audit then block

> Turns on Microsoft's recommended Defender attack surface reduction (ASR) rules in Audit or Block mode.

| | |
|---|---|
| Script | `set-defender-asr-rules.ps1` |
| Type | Action |
| Category | Security hardening & compliance |
| Platforms | Windows 10 1709+, Windows 11, Windows Server 2019+ |
| Runs as | System |
| Requires | PowerShell 5.1; Microsoft Defender Antivirus active; administrator rights |
| Changes | Sets Defender attack surface reduction rules to Audit or Block (Add-MpPreference); saves a registry backup of the ASR settings first |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS. It applies a fixed set of 14 Microsoft Defender attack surface reduction rules (the three "standard protection" rules plus the other rules Microsoft recommends for most PCs; the list is written out in the script with names) to Audit or Block mode with Add-MpPreference, and reports each rule before and after:

- Audit (the default) only logs what the rule would have blocked, so nothing breaks. Run in Audit first, read the events with the ASR report, then run again with Mode Block.
- Block stops the behaviour. Office macro and script rules can stop line-of-business software that relies on them: audit first.

A rule that is already at or stricter than the wanted mode is left alone: Audit never lowers a rule that is on Block (or Warn). ExcludeRules lists rule IDs to leave exactly as they are. The rule "Block process creations originating from PSExec and WMI commands" is not in the set because RMM tools and software deployment use those paths.

It is skipped when Microsoft Defender is not the active antivirus (passive mode, or another antivirus is registered in Windows Security Center), because the rules do nothing there. It stops with an error when Defender is off: run repair-defender first. Rules pushed by Intune or Group Policy win over this script; if one does not take, the run ends in an error naming it. It never touches exclusions, Controlled Folder Access or any other Defender setting.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Mode` | Audit (default) or Block. | `Audit` | `Mode` or `MODE` |
| `ExcludeRules` | Rule IDs (GUIDs from the list in this script) to leave unchanged, separated by commas. Default none. | (empty) | `ExcludeRules` or `EXCLUDE_RULES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\set-defender-asr-rules.ps1 -DryRun true
```

Lists the rules that would be set to Audit.

```powershell
.\set-defender-asr-rules.ps1 -Mode Block -ExcludeRules 9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2
```

Moves every rule to Block except credential stealing from LSASS.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Mode`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
ASR rules set to Audit: 11 changed, 3 already set
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\set-defender-asr-rules.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/set-defender-asr-rules

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
