# SSO and Teams sign-in broken - Entra join and PRT health

> Alerts when an Entra ID or hybrid-joined PC has a broken join, an expired device certificate or no sign-in token.

| | |
|---|---|
| Script | `test-entra-join-health.ps1` |
| Type | Monitor |
| Category | Identity: AD / Entra / M365 users |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | Either |
| Requires | PowerShell 5.1; dsregcmd.exe (in Windows); the Task Scheduler service |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 15 seconds; up to 60 seconds more when it reads the signed-in user's token |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It runs dsregcmd /status and checks:

- the join state: Entra ID joined, hybrid joined (domain and Entra ID), domain only, or neither (workgroup),
- the device certificate's validity dates (an expired one means the PC can no longer authenticate to Entra ID),
- whether the device key is protected by the TPM (shown, never alerted),
- the tenant name and the MDM enrolment URL (shown),
- in a user's context only: the signed-in user's Primary Refresh Token (AzureAdPrt) and its expiry. A joined PC whose user has no PRT cannot do single sign-on to Microsoft 365 and Teams.

WHAT SYSTEM CAN SEE. The device facts are the same for every account, so they are read correctly when an RMM runs the script as SYSTEM. The Primary Refresh Token belongs to a signed-in user, and dsregcmd run as SYSTEM reports SYSTEM's own (always empty) token state, which would be a false alert. So when run as SYSTEM with someone signed in, the script runs dsregcmd inside that user's session (the runtime's Invoke-OutpostAsUser: a one-shot scheduled task for the user, deleted straight afterwards, with the user's rights only) and reads the PRT from that. With nobody signed in, or when that cannot be run, the PRT row says it was not checked and nothing is alerted. When the script is run directly as a user (an Intune remediation set to run with the logged-on credentials, or an RMM option to run as the logged-on user) it reads that user's own state. Only the console user, or the user of a desktop shell, is checked, not every signed-in user.

The dsregcmd field names and YES/NO values are used as English text. They are identifiers, not translated resources, as far as the references show, but this has not been confirmed on a non-English Windows. If the AzureAdJoined field is not in the output, the script ends with an error rather than guessing.

SKIPPED on a workgroup PC, and on a PC joined to a domain only (no Entra ID join to check). Set RequireEntraJoin to true to alert on those instead, for a fleet that must all be Entra ID joined or hybrid joined.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `RequireEntraJoin` | Alert, instead of skipping, when the PC is not Entra ID joined or hybrid joined (workgroup or domain only). true or false. Default false. | `false` | `RequireEntraJoin` or `REQUIRE_ENTRA_JOIN` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-entra-join-health.ps1
```

Checks the join and device certificate; checks the PRT too when run as a user.

```powershell
.\test-entra-join-health.ps1 -RequireEntraJoin true
```

Also alerts on a PC that is only in a workgroup or a domain.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `RequireEntraJoin`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Hybrid joined to Contoso; device certificate valid to 2035-06-01; no PRT for CONTOSO\ana
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Check`, `Value`, `Healthy`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-entra-join-health

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
