# DKIM signing not on - create the config and turn it on

> Turns on DKIM signing for the tenant's domains: creates the signing config if it is missing, prints the two DNS records to publish, and enables signing once both records resolve.

| | |
|---|---|
| Script | `enable-dkim-signing.ps1` |
| Type | Action |
| Category | Exchange & email |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; DnsClient; Graph: Organization.Read.All; Exchange app access (ManageAsApp), Exchange admin role |
| Changes | Creates DKIM signing configs in Exchange Online; enables DKIM signing for a domain once both selector CNAME records resolve |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 2 minutes |
| Version | 1.0.1 |
| Updated | 2026-11-23 |

## What it does

It connects to Exchange Online as the client's app and, for each domain you name in Domains (default: every authoritative accepted domain; the *.onmicrosoft.com domains are signed by Microsoft and skipped), does the steps Microsoft documents. 1) If the domain has no DKIM signing config it creates one switched off (New-DkimSigningConfig -Enabled $false, KeySize 1024 or 2048). 2) It prints the two CNAME records for you to publish at the domain's DNS host, from the config's Selector1CNAME and Selector2CNAME.

3) When selector1._domainkey.<domain> and selector2._domainkey.<domain> both resolve (Resolve-DnsName, on this computer) to those targets, it enables signing (Set-DkimSigningConfig -Enabled $true); until then it does not enable anything for that domain, so run it again after the DNS change has spread (up to a few hours). It never changes DNS. It never disables signing, and leaves a domain that is already enabled alone. After enabling, it re-reads the config and fails (exit 2) if Enabled is not true. Low risk: a new DKIM config that is switched off changes no mail, and enabling only adds a signature. Add the DKIM change to the client's change log: a receiving server that checks DKIM will now see a signature for the domain. It is SKIPPED when the ExchangeOnlineManagement module or Resolve-DnsName is missing. One tenant per run.

Permissions: Microsoft Graph application permission Organization.Read.All (the shared helper reads the tenant's initial domain, GET /organization); Exchange.ManageAsApp on Office 365 Exchange Online; and an Exchange role that can run New-DkimSigningConfig and Set-DkimSigningConfig (Exchange Administrator works; the DKIM cmdlets are cloud-only).

Where each fact comes from (Microsoft Learn): New-DkimSigningConfig (-DomainName and -Enabled are mandatory; -KeySize 1024 default or 2048), Set-DkimSigningConfig (-Identity is the domain name, -Enabled), Get-DkimSigningConfig, the DKIM configuration article (the two CNAME records, the Status values Valid, CnameMissing and NoDKIMKeys, and the properties Selector1CNAME and Selector2CNAME, copied from the config after it is created), Get-AcceptedDomain, Resolve-DnsName. Not confirmed in the documentation, so read defensively: that the Selector CNAME properties are filled immediately after New-DkimSigningConfig (if empty, run the script again, or read them with Get-DkimSigningConfig -Identity <domain> | Format-List); the DomainName and DomainType property names on Get-AcceptedDomain; that this computer's DNS resolver sees what the internet sees. An enable can still fail if Microsoft's own check of the records fails; the error is shown and the run ends in ERROR.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client's tenant ID (a GUID) or domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate, with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. Leave empty to use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |
| `Domains` | Domains to work on, separated by comma, semicolon or new line. Default empty: every authoritative accepted domain except the *.onmicrosoft.com ones. A name that is not an accepted domain is an error. | (empty) | `Domains` or `DOMAINS` |
| `KeySize` | Key size for a new signing config: 2048 (default) or 1024. Ignored for a domain that already has a config. | `2048` | `KeySize` or `KEY_SIZE` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\enable-dkim-signing.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -DryRun true
Lists the configs it would create and the domains it would enable.
```

```powershell
.\enable-dkim-signing.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -Domains contoso.com
Creates the config for contoso.com if needed, prints the CNAMEs to publish, and enables signing once they resolve.
```

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `TenantId`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
DKIM: created 1 config(s), enabled 1 domain(s); 1 waiting for DNS (CNAMEs printed above)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\enable-dkim-signing.log`.

## Changelog

- 1.0.1 2026-11-23 Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
- 1.0.0 2026-11-18 First version.

## More

Full page: https://mspoutpost.com/scripts/enable-dkim-signing

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
