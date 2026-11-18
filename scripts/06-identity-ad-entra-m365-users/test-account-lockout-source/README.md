# User keeps getting locked out - find the source

> Alerts when Active Directory accounts are locked out, and shows which computer is causing each lockout.

| | |
|---|---|
| Script | `test-account-lockout-source.ps1` |
| Type | Monitor |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows Server 2016+ (domain controller or domain member) |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, ActiveDirectory module (RSAT-AD-PowerShell), Security log access on the DC |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. It finds the user accounts that are locked out right now (or, when AccountName is set, looks at only those users) and for each one reports where the bad passwords came from:

- SourceComputer: the "Caller Computer Name" of the newest lockout event 4740 for that user in the Security log of this domain controller and, if it is a different computer and reachable, of the PDC emulator (every lockout is also logged there).
- FailedAttempts and FailureSources: the recent failed sign-ins for that user, from events 4771 (Kerberos pre-authentication failed), 4776 (NTLM password check failed) and 4625 (failed logon), with the computer name or IP address each came from and how many times.

It ends ALERT when any looked-at account is locked out, and OK otherwise. A user named in AccountName who is not locked out is still listed (with LockedOut false) so you can see recent failures before the lockout.

The events only exist when the domain controller audits "User Account Management" (success) and "Kerberos Authentication Service" / "Credential Validation" (failure); the default domain controller policy does. When no lockout event is found the Notes column says so.

Run it on a domain controller, or on a member server (then only the PDC emulator's log is read). It needs the ActiveDirectory module (RSAT); if that is missing it ends ERROR; on a computer that is not in a domain it ends SKIPPED. Pair it with clear-account-lockout to unlock the account.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `AccountName` | Only look at these users, separated by commas or semicolons: the sign-in name (jsmith), DOMAIN\jsmith, or the user principal name. Default empty: every locked-out user. (Named AccountName, not UserName: Windows already has an environment variable called USERNAME, which the runtime would read.) | (empty) | `AccountName` or `ACCOUNT_NAME` |
| `LookbackHours` | How far back to read events. Whole number, 1 to 720. Default 24. | `24` | `LookbackHours` or `LOOKBACK_HOURS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-account-lockout-source.ps1
```

Alerts if any account is locked out and names the computer behind each.

```powershell
.\test-account-lockout-source.ps1 -AccountName jsmith -LookbackHours 72
```

Reports on jsmith only, reading three days of events.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `AccountName`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
1 account(s) locked out: jsmith (source WS-FIN-07, 12 failed attempts)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `AccountName`, `LockedOut`, `LockoutTimeUtc`, `SourceComputer`, `BadPasswordCount`, `FailedAttempts`, `FailureSources`, `Notes`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/test-account-lockout-source

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
