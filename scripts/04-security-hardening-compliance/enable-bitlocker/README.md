# Turn on BitLocker and store the recovery key

> Turns on BitLocker for the Windows drive with a TPM protector and makes sure the recovery key is stored before encrypting.

| | |
|---|---|
| Script | `enable-bitlocker.ps1` |
| Type | Action |
| Category | Security hardening & compliance |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, TPM 1.2 or 2.0 ready, Windows Pro or higher |
| Changes | Adds BitLocker key protectors to the Windows drive, backs up the recovery key to Entra ID or Active Directory (or the RMM field), starts encryption |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 2 minutes; encryption continues in the background |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS. It protects the Windows drive (the one holding C:\Windows) with BitLocker and a TPM, and makes sure the recovery key is stored before encrypting. It handles three states of that drive:

- Not encrypted: adds a recovery password protector, stores the key (below), then starts encryption with the TPM protector (Enable-BitLocker -UsedSpaceOnly -SkipHardwareTest).
- Encrypted with protection Off (Windows 11 automatic device encryption leaves C: like this, often with no protectors at all): adds the missing recovery and TPM protectors, stores the key, then Resume-BitLocker.
- Protected: nothing to change when the recovery key is known to be stored (Entra ID: a "backup succeeded" event for the recovery protector; Active Directory cannot be verified from the PC and is reported as such). When it is protected but the key escrow is not confirmed, it escrows the key (CHANGED).

Where the key is stored, in order: Microsoft Entra ID when the PC is Entra-joined (dsregcmd; BackupToAAD-BitLockerKeyProtector), Active Directory when it is domain-joined (Backup-BitLockerKeyProtector), both when hybrid. With EscrowRequired true (default) and neither, it ends in ERROR BEFORE encrypting anything: the script never encrypts without a recorded key. It also needs a TPM that is present and ready.

-SkipHardwareTest means no restart test: if the firmware or boot configuration cannot release the key from the TPM, the PC asks for the 48-digit recovery password at the next start. That is why the key is stored first, and why you should not use this on a PC you cannot reach or in front of when no one holds the key.

If a step fails after the recovery protector was added and encryption has not started, the protector it added is removed again.

EscrowRequired false, workgroup PC (no Entra ID, no Active Directory): the recovery password is written to your RMM custom field named by ResultField, BEFORE encryption starts, and nowhere else. Make that a secure / secret field. The recovery password is NEVER printed, logged or put in the answer or the rows: the run reports only the key protector IDs, and the BitLocker warning that contains the key is discarded. Without a ResultField, or on an RMM this library cannot write to (NinjaOne, Datto RMM, Syncro), it refuses before changing anything. OutputFormat Answer is refused in this mode. On a workgroup PC a ResultField is treated as that secret field on every run, so a status message never overwrites the key; when the key goes to Entra ID or Active Directory, ResultField is an ordinary answer field.

Not touched: data drives and other protectors. BitLocker needs Windows Pro, Enterprise or Education (Home is skipped) and a recovery partition.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `EscrowRequired` | true (default): refuse to encrypt unless the recovery key can be stored in Entra ID or Active Directory. false: when neither exists, put the recovery password in ResultField instead. | `true` | `EscrowRequired` or `ESCROW_REQUIRED` |
| `EncryptionMethod` | XtsAes256 (default), XtsAes128, Aes256 or Aes128. | `XtsAes256` | `EncryptionMethod` or `ENCRYPTION_METHOD` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\enable-bitlocker.ps1 -DryRun true
```

Lists what it would do; ends in ERROR when the key could not be stored.

```powershell
.\enable-bitlocker.ps1 -EscrowRequired false -ResultField RecoveryKey
```

On a workgroup PC, encrypts C: and writes the recovery password to the RecoveryKey custom field.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `EscrowRequired`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
BitLocker enabled on C: (XtsAes256, used space only); key escrowed to Entra ID; protector IDs RP {1111aaaa-0000-0000-0000-000000000001} TPM {2222bbbb-0000-0000-0000-000000000002}
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\enable-bitlocker.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/enable-bitlocker

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
