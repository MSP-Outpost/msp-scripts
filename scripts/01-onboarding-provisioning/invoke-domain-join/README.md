# Join this PC to the AD domain, into the right OU

> Joins this PC to an Active Directory domain, into a chosen OU, with credentials from secure RMM fields and a restart you control.

| | |
|---|---|
| Script | `invoke-domain-join.ps1` |
| Type | Action |
| Category | Onboarding & provisioning |
| Platforms | Windows 10, 11, Server 2016+ (not a domain controller) |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, DNS that finds the domain, a join account in a secure RMM field (JoinPassword) |
| Changes | Joins the PC to the domain (creates its computer account) and can restart it |
| Risk | **High** |
| Reboot | Restarts |
| Typical runtime | Under 1 minute |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## Safety

> **This is a High-risk script: it makes changes that are hard to undo. It is a dry run by default.**

- It only lists what it would do until you set **both** `DryRun=false` **and** `Approve=invoke-domain-join`. Typing the script name is the deliberate step.
- It refuses to make more than `MaxChanges` changes in one run (default 25). A bigger plan changes nothing and says what to set.
- Every change is logged, one line each, to `%ProgramData%\MSPOutpost\Logs\invoke-domain-join.log`.
- Run the dry run first and read the list.

## What it does

THIS SCRIPT CHANGES THINGS. Risk is High, so it is a dry run unless you set BOTH DryRun=false AND Approve=invoke-domain-join (typing the script name is the deliberate step). It runs ON THE PC that should join.

What it does:

1. Refuses a domain controller (ERROR). If the PC is already joined to DomainName it ends OK "Already joined" and changes nothing. If it is joined to a DIFFERENT domain it refuses (ERROR): it never moves a PC between domains; leave the old one first.
2. Checks that DNS on this PC can find a domain controller of DomainName (the _ldap._tcp.dc._msdcs SRV record), so a PC with the wrong DNS fails early and clearly.
3. Joins the domain with Add-Computer. The computer account is created in TargetOu when you set it, else in the domain's default Computers container. DomainController (a full DNS name, as Windows now requires for domain join) picks the controller to talk to.
4. Checks Windows now reports the PC as a member of that domain.
5. Restarts, depending on RestartMode: Never (default), IfNoUserSignedIn (restart in 60 seconds only when nobody is signed in) or Always (restart in 60 seconds, signed-in users or not). The restart is needed to finish the join; when it does not happen the answer says "restart needed".

CREDENTIALS: JoinUser is the account allowed to join PCs (for example CONTOSO\svc-join or svc-join@contoso.com). JoinPassword is read from the environment variable JoinPassword ONLY, never from an argument: make it a secure / hidden field in your RMM. It is never printed, logged or stored. Give that account only the right to create computer accounts in TargetOu. A dry run does not need the password.

Not checked: whether TargetOu exists (a PC outside the domain cannot read the directory); Windows then ends the join with an error that names the problem. Nothing is changed when the join fails.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `DomainName` | The domain's DNS name, e.g. contoso.com. Required. | (empty) | `DomainName` or `DOMAIN_NAME` |
| `TargetOu` | The OU for the computer account, as a distinguished name, e.g. "OU=Workstations,DC=contoso,DC=com". Default empty: the default Computers container. | (empty) | `TargetOu` or `TARGET_OU` |
| `JoinUser` | The account that joins the PC, DOMAIN\user or user@domain. Required for a real run. | (empty) | `JoinUser` or `JOIN_USER` |
| `DomainController` | Full DNS name of the domain controller to join through, e.g. dc1.contoso.com. Default empty: Windows chooses. | (empty) | `DomainController` or `DOMAIN_CONTROLLER` |
| `RestartMode` | Never (default), IfNoUserSignedIn or Always. | `Never` | `RestartMode` or `RESTART_MODE` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`), `Approve` and `MaxChanges`. Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\invoke-domain-join.ps1 -DomainName contoso.com -TargetOu "OU=Workstations,DC=contoso,DC=com"
```

Dry run: shows that the PC would join contoso.com into the Workstations OU.

```powershell
.\invoke-domain-join.ps1 -DomainName contoso.com -JoinUser CONTOSO\svc-join -RestartMode IfNoUserSignedIn -DryRun false -Approve invoke-domain-join
```

Joins for real (JoinPassword comes from the environment) and restarts when nobody is signed in.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `DomainName`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

To make real changes, set `DryRun` to `false` and `Approve` to `invoke-domain-join`. Without both, the script only lists what it would do.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Joined contoso.com in OU=Workstations,DC=contoso,DC=com; restart needed to finish
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\invoke-domain-join.log`.

## Changelog

- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/invoke-domain-join

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
