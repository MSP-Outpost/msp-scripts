# Cyber-insurance questionnaire - device evidence pack

> Collects the device half of a cyber-insurance questionnaire as one evidence table with a Pass, Fail or Unknown for each control.

| | |
|---|---|
| Script | `get-cyber-insurance-evidence.ps1` |
| Type | Report |
| Category | Security hardening & compliance |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1; administrator rights |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 60 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. One run answers the questions an insurer asks about a Windows device. It writes one row per control (Control, Value, Status, Evidence) and ends with "N of M controls pass; fails: ...". Set ExportPath to a .csv file to hand the table to the client file.

Controls: operating system support status; age of the last patch (quality update); BitLocker on the operating system drive; antivirus active (Windows Security Center on workstations, Defender status); an EDR agent (Microsoft Defender for Endpoint, CrowdStrike, SentinelOne, Huntress, Cylance, Carbon Black, Cortex XDR); the three firewall profiles as enforced; the local Administrators group (a list); Remote Desktop and Network Level Authentication; SMB1; Secure Boot; TPM; the machine screen lock timeout policy (InactivityTimeoutSecs); local password length, complexity and account lockout (read with secedit, no text parsed from net accounts); a backup product present; remote access tools present.

Pass and Fail are stated only when the evidence supports them. Unknown means the script could not read it, or that a person has to judge it: the EDR row is Unknown when no product from the short list is found (the list is not every product), and the remote access row is Unknown when tools are found (the script cannot tell your approved tool from an unapproved one). Limits to know:

- Patch age is the newest of Get-HotFix and the KB-numbered updates in the Windows Update history (Defender definitions and the malicious software removal tool are ignored). Confidence: medium.
- OS support uses a built-in table of end-of-support dates for Windows 10, Windows 11 and Windows Server (Home/Pro and Enterprise/Education dates differ). Windows 10 Extended Security Updates and Long-Term Servicing releases are not detected (an LTSC edition is Unknown). A build newer than the table is Pass.
- The screen lock row reads only the machine policy InactivityTimeoutSecs; per-user screen saver policies are not read.
- On a domain-joined PC the password rows show the effective policy, which includes domain Group Policy.
- The backup row only shows that a product is present; run test-backup-status to know whether it succeeded.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `MaxPatchAgeDays` | Fail the patch row when the newest update is older than this many days. Whole number, 1 to 3650. Default 45. | `45` | `MaxPatchAgeDays` or `MAX_PATCH_AGE_DAYS` |
| `MaxScreenLockSeconds` | Fail the screen lock row when InactivityTimeoutSecs is not set or is longer than this. Whole number, 1 to 86400. Default 900 (15 minutes). | `900` | `MaxScreenLockSeconds` or `MAX_SCREEN_LOCK_SECONDS` |
| `MinPasswordLength` | Fail the password length row when the local minimum is shorter than this. Whole number, 1 to 128. Default 8. | `8` | `MinPasswordLength` or `MIN_PASSWORD_LENGTH` |
| `MaxLocalAdmins` | Fail the local administrators row when the Administrators group has more members than this. Whole number, 1 to 100. Default 3. | `3` | `MaxLocalAdmins` or `MAX_LOCAL_ADMINS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-cyber-insurance-evidence.ps1 -ExportPath C:\Temp\insurance-evidence.csv
```

Prints the table and saves it as a CSV for the client file.

```powershell
.\get-cyber-insurance-evidence.ps1 -MinPasswordLength 12 -MaxScreenLockSeconds 600 -OutputFormat Json
```

Holds the device to a 12 character password and a 10 minute lock, as JSON.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `MaxPatchAgeDays`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
11 of 17 controls pass; fails: BitLocker, Firewall, Screen lock; 1 unknown
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Control`, `Value`, `Status`, `Evidence`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/get-cyber-insurance-evidence

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
