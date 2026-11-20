# NTLMv1 and LM hashes still allowed

> Alerts when LM and NTLMv1 are still allowed, or were used to sign in on this server in the last N hours.

| | |
|---|---|
| Script | `test-ntlm-settings.ps1` |
| Type | Monitor |
| Category | Security hardening & compliance |
| Platforms | Windows 10, 11, Server 2016+ (best on each DC) |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights (reads the Security log), Audit Logon success for the sign-in check |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## What it does

THIS SCRIPT IS READ-ONLY. It checks three things on this computer and ALERTs when any fails:

1. LmCompatibilityLevel (HKLM\SYSTEM\CurrentControlSet\Control\Lsa, the policy "Network security: LAN Manager authentication level"). Level 3 sends NTLMv2 only but a domain controller still ACCEPTS LM and NTLM; level 4 refuses LM; level 5 refuses LM and NTLM. The check fails when the level is below MinLmCompatibilityLevel (default 5). A missing value counts as 3, the documented default.
2. NoLMHash (same key, the policy "Do not store LAN Manager hash value on next password change"). Fails when it is 0. A missing value counts as on, the documented default.
3. Sign-ins that used NTLMv1 or LM: successful logon events (4624) in the Security log in the last LookbackHours hours whose LmPackageName is "NTLM V1" or "LM". One row per user, workstation, address and package with a count. This is the audit that tells you what would break before you raise the level. It needs the audit policy "Audit Logon" (success) to be on, and sees only the sign-ins that reached THIS computer: run it on every domain controller. A quiet log looks the same as auditing being off.

It never changes the setting. To raise the level use a Group Policy on the domain controllers (Computer Configuration > Windows Settings > Security Settings > Local Policies > Security Options) after the events are gone.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `MinLmCompatibilityLevel` | The lowest acceptable LmCompatibilityLevel, 0 to 5. Default 5. | `5` | `MinLmCompatibilityLevel` or `MIN_LM_COMPATIBILITY_LEVEL` |
| `LookbackHours` | How far back to look for NTLMv1 or LM sign-ins. Whole number 1 to 720. Default 24. | `24` | `LookbackHours` or `LOOKBACK_HOURS` |
| `CheckEvents` | true to read the Security log. Default true. | `true` | `CheckEvents` or `CHECK_EVENTS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-ntlm-settings.ps1 -LookbackHours 72
```

Checks the settings and lists NTLMv1 and LM sign-ins of the last 3 days.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `MinLmCompatibilityLevel`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
LmCompatibilityLevel 3 (want 5 or more); 4 NTLMv1 or LM sign-in(s) in the last 24 h
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Check`, `Target`, `Status`, `Detail`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/test-ntlm-settings

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
