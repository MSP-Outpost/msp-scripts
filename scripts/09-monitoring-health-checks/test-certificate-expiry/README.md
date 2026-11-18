# Certificate about to expire on this PC

> Alerts when a certificate in the PC's machine store has expired or expires soon.

| | |
|---|---|
| Script | `test-certificate-expiry.ps1` |
| Type | Monitor |
| Category | Monitoring & health checks |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1; administrator rights |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 10 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It reads the certificates in the LocalMachine certificate stores named in Stores (default: Personal, shown as "My") and alerts when any has already expired or expires within Days days.

Self-signed certificates (the subject equals the issuer) are left out, because Windows creates many of them itself (Remote Desktop, WinRM, device certificates) and renews them on its own. Set IncludeSelfSigned to true to check them too. Root and intermediate authority stores are not checked unless you name them in Stores: a certificate authority's own certificate is normally self-signed and managed elsewhere.

A certificate is not flagged when a newer one with the same subject and issuer is in the same store (an IIS or win-acme renewal that left the old certificate behind), and Windows' own short-lived Entra device certificates (issuer MS-Organization-Access or MS-Organization-P2P-Access) are ignored.

Each flagged certificate is one row: store, subject, issuer, expiry date (UTC), days left (negative = expired), thumbprint and whether the PC holds its private key. Certificates in users' own stores (CurrentUser) and certificates bound by IIS, RDP or LDAPS that live in other stores are only checked if that store is listed. Needs administrator rights.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Days` | Alert on certificates that expire within this many days (and on those already expired). Whole number, 0 to 3650. Default 30. | `30` | `Days` or `DAYS` |
| `Stores` | LocalMachine certificate stores to check, separated by commas or semicolons. Default My. Examples: My, WebHosting, "Remote Desktop". | `My` | `Stores` or `STORES` |
| `IncludeSelfSigned` | Also check self-signed certificates. true or false. Default false. | `false` | `IncludeSelfSigned` or `INCLUDE_SELF_SIGNED` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-certificate-expiry.ps1
```

Alerts on any non-self-signed certificate in LocalMachine\My that expires within 30 days.

```powershell
.\test-certificate-expiry.ps1 -Days 60 -Stores "My,WebHosting" -IncludeSelfSigned true
```

A wider check across two stores that includes self-signed certificates.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Days`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
2 certificates expired or expiring within 30 days (1 expired); first: CN=mail.contoso.com in 6 day(s)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Store`, `Subject`, `Issuer`, `NotAfterUtc`, `DaysLeft`, `Thumbprint`, `HasPrivateKey`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/test-certificate-expiry

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
