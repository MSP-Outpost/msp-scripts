# BitLocker off or recovery key not escrowed

> Alerts when BitLocker is off on the OS drive or a recovery key is missing or not escrowed.

| | |
|---|---|
| Script | `test-bitlocker-status.ps1` |
| Type | Monitor |
| Category | Security hardening & compliance |
| Platforms | Windows 10 Pro, Windows 11 Pro, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 15 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. For every fixed volume it reads the BitLocker protection status, encryption percentage, encryption method and key protectors, and whether a recovery password protector exists. It then looks for evidence that the recovery key was escrowed:

- Entra ID (Azure AD): event 845 in the "Microsoft-Windows-BitLocker/BitLocker Management" log whose data contains one of the volume's CURRENT recovery password IDs (read from the event XML, so it works in any language and an old event from before a key rotation does not count).
- Active Directory: the key is stored in the msFVE-RecoveryInformation object, which a PC cannot read about itself. On a domain-joined PC with the Group Policy for AD backup switched on, the escrow is reported as "Unknown (AD)" and does NOT raise an alert, because it cannot be proven either way from here. Check it in AD Users and Computers or Entra.

It alerts (exit 1) when the OS drive is not protected, when a protected or named volume has no recovery password, or, only when you switch RequireEscrow on, when a volume's key is provably not escrowed (no event 845 and no AD policy). Keys stored by MBAM or by your RMM are invisible to this check, which is why RequireEscrow is off by default: turn it on only where keys are escrowed to Entra ID or AD. Unprotected data volumes are reported but alert only when you name them in Drives.

Uses Get-BitLockerVolume, and manage-bde.exe (English output) when the cmdlet is missing. Skipped on Windows Home editions and on PCs without the BitLocker tools. Needs administrator rights.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `RequireEscrow` | true to alert when a recovery key has no escrow evidence. Only meaningful when keys are escrowed to Entra ID or AD. Default false: check only protection and the recovery password. | `false` | `RequireEscrow` or `REQUIRE_ESCROW` |
| `Drives` | Drive letters to check, separated by commas, e.g. "C:, D:". Default empty: every fixed drive. A letter that BitLocker cannot protect on this PC (not a fixed drive or an encryptable volume) is an error. | (empty) | `Drives` or `DRIVES` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-bitlocker-status.ps1
```

Alerts when the OS drive is unprotected or its key is not escrowed.

```powershell
.\test-bitlocker-status.ps1 -RequireEscrow true -Drives "C:, D:"
```

Checks C: and D: for protection, a recovery password and escrow evidence.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `RequireEscrow`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
BitLocker ON for C:; recovery key escrow: Entra ID
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Volume`, `Type`, `Protection`, `EncryptionPercent`, `Method`, `Protectors`, `HasRecoveryPassword`, `Escrow`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-bitlocker-status

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
