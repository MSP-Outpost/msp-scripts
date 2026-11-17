# Website not resolving - flush the DNS cache

> Flushes the Windows DNS resolver cache and reports how many entries it held.

| | |
|---|---|
| Script | `clear-dns-cache.ps1` |
| Type | Action |
| Category | Networking, DNS, VPN, firewall |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights |
| Changes | Clears the DNS client cache; optionally re-registers DNS records |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 10 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS. It:

- counts the entries in the DNS client cache,
- clears the cache (Clear-DnsClientCache, or ipconfig /flushdns when the cmdlet is not available),
- counts again to show the result,
- optionally re-registers this computer's DNS records (RegisterDns).

It does not touch the hosts file, network adapter DNS server settings or any other cache. If the cache is already empty it changes nothing and says so. Windows refills the cache within seconds as programs look up names, so the count after is rarely exactly zero.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `RegisterDns` | true to also run ipconfig /registerdns, which re-registers this computer's name and addresses with its DNS server. Default false. | `false` | `RegisterDns` or `REGISTER_DNS` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\clear-dns-cache.ps1
```

Flushes the DNS cache.

```powershell
.\clear-dns-cache.ps1 -RegisterDns true
```

Flushes the cache and re-registers this computer in DNS.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `RegisterDns`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Flushed the DNS cache (87 entries before, 4 after)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\clear-dns-cache.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/clear-dns-cache

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
