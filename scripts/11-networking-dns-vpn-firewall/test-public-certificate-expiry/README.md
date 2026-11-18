# Public SSL certificate about to expire (TLS check of your sites)

> Alerts when a public site's TLS certificate is about to expire, has expired, or does not match its name or chain.

| | |
|---|---|
| Script | `test-public-certificate-expiry.ps1` |
| Type | Monitor |
| Category | Networking, DNS, VPN, firewall |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | Either |
| Requires | PowerShell 5.1, outbound TCP to each host and port |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | A second or two per host |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. For each host in Hosts it opens a TCP connection to host:port (443 unless you give a port), completes a TLS handshake with the host name as SNI, reads the certificate the server presents, and closes the connection without sending any data. It alerts (exit 1) when a certificate:

- expires within WarningDays days, or has already expired,
- does not match the host name, or
- does not chain to a root this computer trusts.

The handshake uses a validation callback that RECORDS what Windows found wrong (name mismatch, chain errors) so it can be reported; it never hides a problem: every recorded problem becomes an ALERT. A revocation check that could not be completed (no OCSP/CRL access) is not an alert.

A host that cannot be reached or does not finish a TLS 1.2 handshake gets State Unreachable. If nothing else alerts, that is an ERROR (the monitor could not look), never OK. IPv6 literals are not supported. Hosts behind a required client certificate or a STARTTLS protocol (mail ports) are not supported. The check sees what THIS computer sees: a site that serves a different certificate to different networks is judged from here.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Hosts` | The sites to check, separated by commas, semicolons or new lines. Each is a host name or host:port, for example "www.contoso.com, mail.contoso.com:8443". Required. At most 100. | (empty) | `Hosts` or `HOSTS` |
| `WarningDays` | Alert when a certificate expires within this many days. Whole number, 1 to 365. Default 21. | `21` | `WarningDays` or `WARNING_DAYS` |
| `TimeoutSeconds` | Seconds to wait for the connection and for the handshake of each host. Whole number, 2 to 120. Default 10. | `10` | `TimeoutSeconds` or `TIMEOUT_SECONDS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-public-certificate-expiry.ps1 -Hosts "www.contoso.com, shop.contoso.com:8443"
```

Alerts if either certificate expires within 21 days or fails validation.

```powershell
.\test-public-certificate-expiry.ps1 -Hosts www.contoso.com -WarningDays 30 -OutputFormat Json
```

Prints one JSON object with the expiry date, issuer and days left.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Hosts`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
www.contoso.com expires in 9 day(s); warning at 21 days
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Host`, `Port`, `State`, `Subject`, `Issuer`, `NotAfterUtc`, `DaysLeft`, `Problem`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/test-public-certificate-expiry

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
