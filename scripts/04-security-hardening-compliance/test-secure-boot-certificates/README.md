# Secure Boot 2023 certificate update

> Alerts when Secure Boot is on but the Windows UEFI CA 2023 certificate is not in the firmware db.

| | |
|---|---|
| Script | `test-secure-boot-certificates.ps1` |
| Type | Monitor |
| Category | Security hardening & compliance |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, UEFI firmware |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 15 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. Microsoft's original Secure Boot certificates (the 2011 generation) expire from June 2026, so every Secure Boot PC needs the 2023 certificates in its firmware. This script checks, one row each:

- Secure Boot: on, off, or not supported (legacy BIOS). Off or legacy BIOS is SKIPPED: there is nothing to update.
- The firmware "db" (the list of certificates allowed to sign boot software): does it contain a certificate whose name includes CertificateName (default "Windows UEFI CA 2023")? It reads the raw db bytes with Get-SecureBootUEFI and searches them for that text, as plain text and as UTF-16 text. Nothing is parsed or trusted beyond that match.
- The firmware "KEK" for "Microsoft Corporation KEK 2K CA 2023", shown for information only; it never raises the alert.
- The Secure Boot servicing registry values, shown RAW and never used to decide the alert: UEFICA2023Status, WindowsUEFICA2023Capable, UEFICA2023Error and AvailableUpdates (from HKLM\SYSTEM\CurrentControlSet\Control\SecureBoot and its Servicing key). As Microsoft's Secure Boot certificate guidance describes them: UEFICA2023Status is NotStarted, InProgress or Updated; WindowsUEFICA2023Capable is 0 (2023 certificate not in db), 1 (in db) or 2 (in db and Windows started from a boot manager signed with the 2023 certificate); AvailableUpdates is the bit mask of certificate updates Windows still intends to apply (0 means none pending). Treat those meanings as Microsoft's, and rely on the db row for the alert.
- The signer of the Windows boot manager file (bootmgfw.efi under Windows\Boot\EFI) when Windows can read it, for information.

ALERT (exit 1): Secure Boot is on and the db has no certificate matching CertificateName, or Secure Boot is on and the db cannot be read at all (the answer says "unknown"; the PC cannot be shown to be safe). OK: Secure Boot is on and the certificate is present. Needs administrator rights. Windows Server is checked the same way.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `CertificateName` | Text the certificate name must contain to count as present in the db. Default "Windows UEFI CA 2023". Spaces are allowed when quoted, but most RMMs cannot pass them: leave the default or edit it in the file. | `Windows UEFI CA 2023` | `CertificateName` or `CERTIFICATE_NAME` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-secure-boot-certificates.ps1
```

Alerts when Secure Boot is on and the 2023 certificate is missing from the db.

```powershell
.\test-secure-boot-certificates.ps1 -OutputFormat Json
```

Same check, one JSON object on stdout.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `CertificateName`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Secure Boot on but the Windows UEFI CA 2023 certificate is not in the firmware db (UEFICA2023Status NotStarted)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Check`, `Value`, `Pass`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-secure-boot-certificates

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
