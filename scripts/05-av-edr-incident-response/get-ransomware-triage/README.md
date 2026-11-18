# Ransomware triage: collect the evidence before a reboot

> Collects ransomware evidence into one ZIP before anyone reboots: processes, services, tasks, autoruns, notes, connections, logs.

| | |
|---|---|
| Script | `get-ransomware-triage.ps1` |
| Type | Report |
| Category | AV / EDR & incident response |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, 1 GB free on the system drive |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | 1 to 5 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It changes nothing on the PC except to write its own ZIP, %ProgramData%\MSPOutpost\Triage\<UTC time>.zip (the folder is locked to SYSTEM and Administrators when the script creates it, because command lines and logs can hold secrets). Run it BEFORE rebooting or reimaging: a reboot clears running processes and connections.

The ZIP holds, as CSV and text files:

- processes: every running process with its command line, parent, program path, the Authenticode signature status and signer, and the SHA-256 of the program file (up to 400 distinct program files);
- services and scheduled tasks (non-Microsoft tasks with last run);
- autoruns: the Run and RunOnce keys of the machine and of loaded user profiles, the Winlogon Shell and Userinit values, and the startup folders;
- possible ransom notes: files named README*.txt, *DECRYPT*, *RECOVER*, *RESTORE*FILES* or *RANSOM* in user folders (profile root, Desktop, Documents, Downloads, Pictures, OneDrive) changed in the last 7 days, at most 200 files and 60 seconds, with the first 300 characters of text notes;
- network connections: TCP connections and UDP endpoints with the owning process, and the DNS client cache;
- the Security, System and Microsoft Defender Operational event logs of the last Hours hours, exported with wevtutil (.evtx);
- local users, members of the local Administrators group, and who is signed in;
- Volume Shadow Copy state (vssadmin list shadows and shadowstorage; a ransomware often deletes the shadow copies);
- summary.txt: what was collected, what failed, how long it took.

A section that cannot be collected is a WARNING and noted in summary.txt; the rest still goes into the ZIP. The answer is the ZIP path and size; the ZIP path is also what ResultField receives. Copy the ZIP off the PC (it is not uploaded anywhere) and treat it as sensitive.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Hours` | How many hours of Security, System and Defender events to export. Whole number, 1 to 720. Default 24. | `24` | `Hours` or `HOURS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-ransomware-triage.ps1
```

Collects the evidence with 24 hours of event logs and prints the ZIP path.

```powershell
.\get-ransomware-triage.ps1 -Hours 72 -OutputFormat Answer
```

Collects 72 hours of event logs; prints only the ZIP path.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Hours`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Triage ZIP: C:\ProgramData\MSPOutpost\Triage\20261116-141500.zip (12.3 MB, 16 files, events of the last 24h); possible ransom notes: 2
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Section`, `Items`, `File`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/get-ransomware-triage

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
