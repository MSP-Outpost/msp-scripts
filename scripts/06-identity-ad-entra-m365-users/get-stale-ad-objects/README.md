# Stale AD users and computers - who has not signed in for 90 days

> Lists enabled Active Directory users and computers that have not signed in for a number of days.

| | |
|---|---|
| Script | `get-stale-ad-objects.ps1` |
| Type | Report |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows Server 2016+ (domain controller or domain member) |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, ActiveDirectory module (RSAT-AD-PowerShell) |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 1 minute for 1,000 accounts |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. It lists enabled user and computer accounts that look abandoned, one row per account, so you can review them before disabling anything (disable-stale-ad-objects uses the same selection).

An account is stale when:

- Reason "Inactive": its lastLogonTimestamp is older than InactiveDays; or
- Reason "NeverLoggedOn": it has no lastLogonTimestamp at all and was created more than InactiveDays ago (whenCreated).

lastLogonTimestamp is refreshed only when it is more than about 14 days old, so use an InactiveDays of 30 or more for anything you will act on. Accounts that are already disabled are not listed.

Never listed, whatever the inputs: the built-in accounts (RIDs 500 to 503: Administrator, Guest, krbtgt, DefaultAccount), anything Active Directory marks as a critical system object, domain controllers, the computer running this script, managed service accounts (gMSA, MSA), trust accounts (names ending in $), and every account named in ExcludeAccounts. Put your service accounts in ExcludeAccounts: this script cannot tell a service account that only authenticates by Kerberos from an abandoned one.

Run it on a domain controller or a member server with the ActiveDirectory module (RSAT). If the module is missing it ends ERROR; on a computer that is not in a domain it ends SKIPPED.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `InactiveDays` | Days without a sign-in before an account is stale. Whole number, 0 to 3650. Default 90. (0 lists every account that has not signed in this moment; meant for testing, with SearchBase.) | `90` | `InactiveDays` or `INACTIVE_DAYS` |
| `SearchBase` | Only look under this OU or container, as a distinguished name, e.g. "OU=Staff,DC=contoso,DC=com". Default empty: the whole domain. It must exist. | (empty) | `SearchBase` or `SEARCH_BASE` |
| `ExcludeAccounts` | Sign-in names (SamAccountName) to leave out, separated by commas or semicolons, e.g. "svc-backup, svc-sql, PRINTSRV01". A computer may be written with or without its trailing $. * and ? are wildcards, but a wildcard needs at least 3 literal characters. Default empty. | (empty) | `ExcludeAccounts` or `EXCLUDE_ACCOUNTS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-stale-ad-objects.ps1
```

Lists every enabled user and computer that has been idle for 90 days or more.

```powershell
.\get-stale-ad-objects.ps1 -InactiveDays 180 -ExcludeAccounts "svc-backup, svc-sql" -ExportPath C:\Temp\stale.csv
```

Six months idle, leaving out two service accounts, and also saves a CSV.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `InactiveDays`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Found 14 stale account(s) idle 90+ days: 9 user(s), 5 computer(s)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `ObjectType`, `SamAccountName`, `Reason`, `LastLogonUtc`, `CreatedUtc`, `DaysIdle`, `Ou`, `Description`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/get-stale-ad-objects

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
