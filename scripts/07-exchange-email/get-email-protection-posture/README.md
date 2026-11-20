# Email protection below standard

> Reports the tenant's email protection against Microsoft's recommended Standard settings: preset policies, anti-spam, anti-phishing, anti-malware, Safe Links, Safe Attachments and outbound spam.

| | |
|---|---|
| Script | `get-email-protection-posture.ps1` |
| Type | Report |
| Category | Exchange & email |
| Platforms | Windows 10, 11, Server 2016+, with the app certificate |
| Runs as | Either |
| Requires | PowerShell 5.1; Graph: Organization.Read.All; ExchangeOnlineManagement 3.1+, Exchange.ManageAsApp, read role |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 2 minutes |
| Version | 1.0.0 |
| Updated | 2026-11-19 |

## What it does

THIS SCRIPT IS READ-ONLY. It never applies a preset or changes a policy. It connects to Exchange Online as the client's app and reads the preset security policy rules (Standard and Strict, from Get-EOPProtectionPolicyRule and Get-ATPProtectionPolicyRule), then each policy of these kinds and compares settings with the values Microsoft lists as recommended for the Standard protection level: anti-spam (Get-HostedContentFilterPolicy: HighConfidenceSpamAction, PhishSpamAction and HighConfidencePhishAction Quarantine, BulkThreshold 6 or lower, PhishZapEnabled and SpamZapEnabled), anti-phishing (Get-AntiPhishPolicy: Enabled, EnableSpoofIntelligence, HonorDmarcPolicy, EnableMailboxIntelligence, EnableFirstContactSafetyTips, and where the tenant has Defender for Office 365 EnableMailboxIntelligenceProtection and PhishThresholdLevel 3 or more), anti-malware (Get-MalwareFilterPolicy: EnableFileFilter, ZapEnabled), Safe Attachments (Get-SafeAttachmentPolicy: Enable, Action Block), Safe Links (Get-SafeLinksPolicy: email, Teams and Office links on, URL scanning, wait for scan, internal senders, click tracking, click-through off) and the default outbound spam policy (AutoForwardingMode Off, ActionWhenThresholdReached BlockUser). One data row per checked setting: Area, Policy, Setting, Value, Recommended and Status (Meets, Below or Info). Info rows give facts that are not judged (preset policy state, allow lists, no policy found).

It is a snapshot against ONE recommendation, not a verdict: a custom policy that is scoped to a few people or a setting that is stronger than recommended can show as Below or Meets without that mattering, the built-in protection policies are skipped (Microsoft sets them), the Strict values are not checked (a setting stricter than Standard but different from it, such as PhishThresholdLevel 4 or a stricter action, is not recognised except for the numbers, which are compared as at most or at least), and a setting the cmdlet does not return is not judged. Safe Links, Safe Attachments and some anti-phishing settings need Defender for Office 365; where a cmdlet returns nothing they show as Info. A Report: always ends OK. SKIPPED when the ExchangeOnlineManagement module is not installed. One tenant per run.

Permissions: Microsoft Graph application permission Organization.Read.All (the shared helper reads the tenant's initial domain, GET /organization); Exchange.ManageAsApp on Office 365 Exchange Online; and an Exchange role that can read the policies (Security Reader or Global Reader is expected to be enough; this script runs only Get-* cmdlets).

Where each fact comes from (Microsoft Learn): the recommended-settings article (Standard and Strict values with the parameter names used above), and the Get-* cmdlet pages (parameters and examples; the Set-* pages for the property names, which the Get-* pages do not list). Not confirmed in the documentation, so read defensively: that the Get-* cmdlets return properties named like the matching Set-* parameters (a property that is missing is skipped, not failed); the names of built-in policies (any policy whose name starts with "Built-in protection" is skipped); that State of a preset rule reads Enabled or Disabled; which Exchange roles an app-only service principal needs to read all six policy types.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `TenantId` | The client's tenant ID (a GUID) or domain such as contoso.onmicrosoft.com. Required. | (empty) | `TenantId` or `TENANT_ID` |
| `ClientId` | The app registration's Application (client) ID, a GUID. Required. | (empty) | `ClientId` or `CLIENT_ID` |
| `CertificateThumbprint` | Thumbprint of the app's certificate, with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. Leave empty to use the ClientSecret environment variable. | (empty) | `CertificateThumbprint` or `CERTIFICATE_THUMBPRINT` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-email-protection-posture.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
Lists every checked setting and whether it meets the Standard recommendation.
```

```powershell
.\get-email-protection-posture.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -OutputFormat Csv
The same, as CSV rows.
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
41 settings checked: 33 meet the Standard recommendation, 8 below (Safe Links 5, anti-spam 3); Standard preset off
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Area`, `Policy`, `Setting`, `Value`, `Recommended`, `Status`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-19 First version (untested).

## More

Full page: https://mspoutpost.com/scripts/get-email-protection-posture

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
