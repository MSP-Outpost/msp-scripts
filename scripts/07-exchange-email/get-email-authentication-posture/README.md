# Is this domain protected from email spoofing - SPF, DKIM and DMARC check

> Reads a domain's public email DNS records (MX, SPF, DMARC, DKIM, MTA-STS, TLS-RPT) and says which ones protect it from spoofing.

| | |
|---|---|
| Script | `get-email-authentication-posture.ps1` |
| Type | Report |
| Category | Exchange & email |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | Either |
| Requires | PowerShell 5.1, the DnsClient module (Resolve-DnsName), internet DNS |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | 10 to 60 seconds per domain |
| Version | 1.0.0 |
| Updated | 2026-11-17 |

## What it does

THIS SCRIPT IS READ-ONLY. It asks DNS (Resolve-DnsName) about one or more domains and writes one row per record found, each with a verdict. It sends no email, connects to no mail server and needs no sign-in; any Windows PC with internet DNS can run it.

Per domain it reads:

- MX: where the domain receives mail ("no MX" and "null MX" are noted: fine for a domain that never receives mail).
- SPF: the "v=spf1" TXT record. Verdict Pass for -all, Warn for ~all, Fail for ?all, +all, no "all" at all, no record, more than one record (receivers treat that as an error) or more than 10 DNS lookups (also an error). The lookup count follows include: and redirect=.
- DMARC: the TXT record at _dmarc.<domain>. Pass for p=reject and for p=quarantine at 100 percent, Warn for p=none (watching only) or quarantine on part of the mail, Fail for no record or an invalid one. The detail says whether a report address (rua) is set.
- DKIM: DKIM keys cannot be listed from DNS, so it tries the common selector names (default, selector1, selector2, google, k1, k2, k3, s1, s2, mail, dkim, smtp, mandrill, everlytickey1, pm, mxvip) plus DkimSelectors, at <selector>._domainkey.<domain>. A key found is Pass, Warn when it is revoked or looks like 1024 bits, Fail under 1024 bits. When none is found the row says Warn: a selector this script does not know may still exist. Give it with DkimSelectors (the selector is in the DKIM-Signature header of a real email from the domain).
- MTA-STS (_mta-sts.<domain>) and TLS-RPT (_smtp._tls.<domain>): optional extras. Present is Pass, absent is Info. The MTA-STS policy file on the web is not downloaded, only the DNS record is read.

It checks exactly the names it is given. DMARC set on a parent domain protects its subdomains, but this script does not guess which part of a name is the parent: give it each domain you care about. A domain that does not exist ends with one row saying so.

Verdicts: Pass, Warn, Fail, Info. The run is OK whatever the verdicts are: the rows and the answer carry the finding. If DNS itself cannot be reached the run ends in an error instead of guessing.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Domain` | The domain(s) to check, separated by commas, for example "example.com". Required. At most 20. | (empty) | `Domain` or `DOMAIN` |
| `DkimSelectors` | Extra DKIM selector names to try, separated by commas, for example "mailchimp, sig1". Default none. | (empty) | `DkimSelectors` or `DKIM_SELECTORS` |
| `DnsServer` | IP address of a DNS server to ask instead of this PC's own, for example 1.1.1.1 to see what the public sees. Default empty = this PC's DNS. | (empty) | `DnsServer` or `DNS_SERVER` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-email-authentication-posture.ps1 -Domain example.com
```

Prints every email-authentication record example.com publishes and a verdict for each.

```powershell
.\get-email-authentication-posture.ps1 -Domain "example.com, example.org" -DkimSelectors mailchimp -DnsServer 1.1.1.1 -OutputFormat Csv
```

Checks two domains, also tries the selector "mailchimp", asking 1.1.1.1.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Domain`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
example.com: SPF -all; DMARC p=reject; DKIM 2 selector(s); 0 fail, 1 warn
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Domain`, `Check`, `Record`, `Verdict`, `Detail`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-17 First version.

## More

Full page: https://mspoutpost.com/scripts/get-email-authentication-posture

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
