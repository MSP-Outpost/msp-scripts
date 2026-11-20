# Windows DNS server - forwarders, aging and scavenging

> Reports a Windows DNS server's forwarders (and whether they answer), aging and scavenging settings and each zone's aging.

| | |
|---|---|
| Script | `get-dns-server-config.ps1` |
| Type | Report |
| Category | Server roles (AD DS, Hyper-V, SQL, IIS, file, RDS) |
| Platforms | Windows Server 2016+ (DNS Server role) |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, DnsServer module (RSAT-DNS-Server), run on the DNS server |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## What it does

THIS SCRIPT IS READ-ONLY. It reads this server's DNS configuration and writes one row per setting:

Forwarders   each forwarder address, the forwarder time-out and whether root hints are used when forwarders fail; and, unless TestForwarders is false, whether each forwarder answers a query for TestName (sent straight to it, answer time shown) Scavenging   whether server-wide scavenging is on, how often it runs, the default no-refresh and refresh intervals and the last time it ran Zones        for every primary zone (not auto-created): whether aging is on, its no-refresh and refresh intervals and the servers that scavenge it

Aging only removes old records when it is on for the zone AND scavenging is on for at least one server; the answer states both so a stale-record problem is easy to see. Nothing is changed: use the DNS console or Set-DnsServerScavenging to change it.

Run it on the DNS server. If the DNS Server service is not installed it ends SKIPPED; without the DnsServer module it ends ERROR.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TestForwarders` | true to send a test query to every forwarder. Default true. | `true` | `TestForwarders` or `TEST_FORWARDERS` |
| `TestName` | The name to look up through each forwarder. Default www.microsoft.com. | `www.microsoft.com` | `TestName` or `TEST_NAME` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-dns-server-config.ps1 -TestName example.com
```

Reads the DNS configuration and tests each forwarder with example.com.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `TestForwarders`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
DNS server DC1: 2 forwarder(s), 2 answer; scavenging on every 7 days; aging on in 3 of 5 zone(s)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Section`, `Item`, `Setting`, `Value`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-19 First version.

## More

Full page: https://mspoutpost.com/scripts/get-dns-server-config

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
