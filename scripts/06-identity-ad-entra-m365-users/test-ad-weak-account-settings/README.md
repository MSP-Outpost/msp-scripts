# AD accounts with weak password settings

> Alerts when AD accounts never expire their password, allow a blank password, use reversible encryption or use DES.

| | |
|---|---|
| Script | `test-ad-weak-account-settings.ps1` |
| Type | Monitor |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows Server 2016+ (domain controller or domain member) |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, ActiveDirectory module (RSAT-AD-PowerShell) |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## What it does

THIS SCRIPT IS READ-ONLY. It reads the userAccountControl flags (and the supported Kerberos encryption types) of every enabled user and raises an ALERT when one of these weak settings is found:

NeverExpires          password never expires (DONT_EXPIRE_PASSWORD) BlankPasswordAllowed  a blank password is allowed (PASSWD_NOTREQD) ReversibleEncryption  password stored with reversible encryption (ENCRYPTED_TEXT_PWD_ALLOWED) DesKeyOnly            only DES Kerberos keys (USE_DES_KEY_ONLY) DesEncryptionTypes    DES enabled in msDS-SupportedEncryptionTypes

Person or service: a user with a service principal name is treated as a SERVICE account. A service account that never expires is listed with IsAlert false and does not raise the alert, unless FlagServiceAccounts is true; every other weak setting alerts for both kinds. Accounts in ExcludeAccounts are skipped. Disabled users are skipped unless IncludeDisabled is true. Computer accounts are not checked.

Run it on a domain controller or a member server with the ActiveDirectory module (RSAT). Without the module it ends ERROR; on a computer that is not in a domain it ends SKIPPED.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `IncludeDisabled` | true to also check disabled users. Default false. | `false` | `IncludeDisabled` or `INCLUDE_DISABLED` |
| `FlagServiceAccounts` | true to also alert on service accounts (users with a service principal name) whose password never expires. Default false. | `false` | `FlagServiceAccounts` or `FLAG_SERVICE_ACCOUNTS` |
| `ExcludeAccounts` | Sign-in names to skip, separated by comma, semicolon or new line. No wildcards. Default empty. | (empty) | `ExcludeAccounts` or `EXCLUDE_ACCOUNTS` |
| `SearchBase` | Only check users under this OU or container, as a distinguished name. Default empty: the whole domain. It must exist. | (empty) | `SearchBase` or `SEARCH_BASE` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-ad-weak-account-settings.ps1 -ExcludeAccounts "svc-backup, svc-scan"
```

Checks every enabled user except two named service accounts.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `IncludeDisabled`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
5 weak setting(s) on 4 account(s): 2 never expires, 1 blank password allowed, 1 reversible encryption, 1 DES; first: jsmith
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `SamAccountName`, `Setting`, `Enabled`, `AccountType`, `IsAlert`, `Ou`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/test-ad-weak-account-settings

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
