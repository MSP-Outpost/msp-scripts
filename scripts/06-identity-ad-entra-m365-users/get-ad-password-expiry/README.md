# Passwords expiring soon - which AD users to warn

> Lists the enabled Active Directory users whose password expires within N days, with the password policy that applies to each, so you can warn them.

| | |
|---|---|
| Script | `get-ad-password-expiry.ps1` |
| Type | Report |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows Server 2016+ (domain controller or domain member) |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, ActiveDirectory module (RSAT-AD-PowerShell) |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute for 1,000 users |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## What it does

THIS SCRIPT IS READ-ONLY and sends no mail. It lists one row per enabled user whose password expires within WithinDays days (and, unless IncludeExpired is false, users whose password has already expired): sign-in name, display name, e-mail address, when the password expires (UTC), days left (negative when expired), the policy that applies and its maximum password age. Feed the rows (ExportPath, or OutputFormat Json or Csv) to whatever sends your reminders.

The expiry time is the one Active Directory computes itself (msDS-UserPasswordExpiryTimeComputed), which already follows the user's EFFECTIVE policy: the Default Domain Policy, or a fine-grained password policy (PSO) that applies to the user or one of the user's groups. The Policy column names that policy (the PSO name, or "Default Domain Policy").

Left out: disabled users, users whose password never expires, users that must smartcard-log on, and users who must change their password at next sign-in (nothing to warn about). If the Default Domain Policy sets no maximum password age and no PSO applies, nobody expires and the answer says so.

Run it on a domain controller or a member server with the ActiveDirectory module (RSAT). Without the module it ends ERROR; on a computer that is not in a domain it ends SKIPPED.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `WithinDays` | List users whose password expires within this many days. Whole number 1 to 365. Default 14. | `14` | `WithinDays` or `WITHIN_DAYS` |
| `IncludeExpired` | true to also list users whose password has already expired. Default true. | `true` | `IncludeExpired` or `INCLUDE_EXPIRED` |
| `SearchBase` | Only look at users under this OU or container, as a distinguished name. Default empty: the whole domain. It must exist. | (empty) | `SearchBase` or `SEARCH_BASE` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-ad-password-expiry.ps1 -WithinDays 7 -ExportPath C:\Temp\expiring.csv
```

Lists users whose password expires within a week and saves the list.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `WithinDays`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
7 user(s) with a password expiring within 14 days (1 already expired); soonest: jsmith in 2 day(s)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `SamAccountName`, `DisplayName`, `Email`, `ExpiresUtc`, `DaysLeft`, `Policy`, `MaxPasswordAgeDays`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/get-ad-password-expiry

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
