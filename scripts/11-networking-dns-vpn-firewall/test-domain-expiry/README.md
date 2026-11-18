# Client domain about to expire (RDAP expiry check)

> Alerts when a domain name you manage is about to expire, read from the public RDAP registration record.

| | |
|---|---|
| Script | `test-domain-expiry.ps1` |
| Type | Monitor |
| Category | Networking, DNS, VPN, firewall |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | Either |
| Requires | PowerShell 5.1, outbound https to data.iana.org and the registries' RDAP servers |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | A few seconds per domain |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. For each domain in Domains it finds the registry's RDAP server through the IANA bootstrap file (https://data.iana.org/rdap/dns.json), asks that server for the domain's registration record, and reads the "expiration" event. It alerts (exit 1) when a domain expires within WarningDays days, has already expired, or is not found at its registry. It writes one row per domain. No WHOIS text is read or scraped.

Give the registered domain (example.com, example.co.uk), not a host name such as www.example.com: RDAP has no record for a subdomain. The script only contacts data.iana.org and the registry's RDAP server over https; it sends the domain name and nothing else.

A domain is reported but not judged when its top-level domain has no RDAP service (State NoRdapService) or the record carries no expiration event (State NoExpiryDate): some registries hide it. If NO domain could be judged the result is SKIPPED. If a lookup fails (no internet, registry down, rate limited) and nothing else alerts, the result is ERROR, so a blind monitor is never reported as healthy.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Domains` | The domains to check, separated by commas, semicolons or new lines. Required. At most 100. Lower or upper case, a trailing dot is ignored. Internationalised names must be written in punycode (xn--...). | (empty) | `Domains` or `DOMAINS` |
| `WarningDays` | Alert when a domain expires within this many days. Whole number, 1 to 3650. Default 30. | `30` | `WarningDays` or `WARNING_DAYS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\test-domain-expiry.ps1 -Domains "contoso.com, contoso.ca" -WarningDays 45
```

Alerts if either domain expires within 45 days.

```powershell
.\test-domain-expiry.ps1 -Domains contoso.com -OutputFormat Json
```

Prints one JSON object with the expiry date and days left.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Domains`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
contoso.com expires in 12 days (2026-11-29); warning at 30 days
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Domain`, `ExpiresUtc`, `DaysLeft`, `State`, `RdapHost`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/test-domain-expiry

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
