# MSP Scripts

> PowerShell and bash scripts for MSPs: monitors, reports and safe fixes for Windows, macOS and Linux, from [MSP Outpost](https://mspoutpost.com/scripts).

This repository holds 195 scripts: 173 PowerShell scripts for Windows and 22 bash scripts for macOS and Linux. Each one has its own folder with the script and a README that explains what it does, what it changes, which inputs it takes and how to run it in your RMM. Each script is one self-contained file: no modules to install, nothing else to copy.

## Safety first

Scripts run as SYSTEM (Windows) or root (macOS and Linux) on client machines, so these are the rules every script follows:

- **Monitors and reports are read-only.** `test-` scripts check one condition and exit 1 when it is not healthy. `get-` scripts collect information. Neither changes anything.
- **Actions are dry-run friendly.** Every action supports `-WhatIf` / `DryRun=true` and lists each change it would make.
- **High-risk actions need approval.** A script that deletes data or removes software is a dry run unless you set both `DryRun=false` and `Approve=<script name>`. Typing the name is deliberate, so one site-wide variable can never unlock every destructive script.
- **Change limits.** `MaxChanges` (default 25 for high-risk scripts) caps how many changes one run can make.
- **Backups.** Before an action edits or deletes configuration, it copies it to `%ProgramData%\MSPOutpost\Backups` on Windows, `/Library/Application Support/MSPOutpost/Backups` on macOS or `/var/lib/mspoutpost/backups` on Linux.
- **A log you can show a client.** Every change an action makes is written to `%ProgramData%\MSPOutpost\Logs\<script>.log` on Windows, `/Library/Logs/MSPOutpost/<script>.log` on macOS or `/var/log/mspoutpost/<script>.log` on Linux.
- **Protected things are never touched:** the RMM agent running the script, system accounts, service profiles and signed-in users.
- **No prompts, no secrets in files, no downloads without verification.**

Read a script before you run it, test it on a non-production machine first, and use the dry run.

## How to run a script in any RMM

1. Open the script folder and read its README.
2. A `.ps1` file: add it to your RMM as a PowerShell script and run it as the System account. A `.sh` file: add it to your RMM as a shell script and run it as root on macOS or Linux.
3. Set its inputs the way your RMM allows: script variables or environment variables with the same name as the input (PowerShell: PascalCase such as `MinAgeDays` or UPPER_SNAKE such as `MIN_AGE_DAYS`; bash: UPPER_SNAKE such as `LOG_AGE_DAYS`), command-line arguments (`-MinAgeDays 180` in PowerShell, `--log-age-days 180` in bash), or by editing the default at the top of the file (the `param()` block, or the `DEFAULT_` lines in bash).
4. Read the result: the exit code (0 fine, 1 alert, 2 error) and the last line of output, which is always `RESULT: <status> | <answer>`. Set `ResultField` to also write the answer to a custom field (NinjaOne, Datto RMM and Syncro), or `OutputFormat=Answer` to print only the answer.

The full rules for inputs, output and safety are in [docs/STANDARD.md](docs/STANDARD.md).

## Scripts

### Onboarding & provisioning

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [Which other RMM agents are on this PC](scripts/01-onboarding-provisioning/get-rmm-agents) | Report | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Autopilot hash not registered - upload this PC's hardware hash](scripts/01-onboarding-provisioning/invoke-autopilot-hash-upload) | Action | Low | Windows 10 1703+ or 11 (the PC being registered) |
| [Join this PC to the AD domain, into the right OU](scripts/01-onboarding-provisioning/invoke-domain-join) | Action | High | Windows 10, 11, Server 2016+ (not a domain controller) |
| [Break-glass local admin - create or reset it](scripts/01-onboarding-provisioning/new-local-admin-account) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Remove remote-access tools that are not approved](scripts/01-onboarding-provisioning/remove-remote-access-tools) | Action | High | Windows 10, Windows 11, Windows Server 2016+ |
| [Remove ScreenConnect instances that are not yours](scripts/01-onboarding-provisioning/remove-screenconnect-instances) | Action | High | Windows 10, Windows 11, Windows Server 2016+ |
| [New PC full of junk apps - Windows 11 debloat (safe MSP profile)](scripts/01-onboarding-provisioning/remove-windows-bloatware) | Action | High | Windows 10, Windows 11 |
| [Rename the computer - fixed name or PREFIX-SERIAL pattern](scripts/01-onboarding-provisioning/set-computer-name) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [New Windows PC needs the standard settings - apply the MSP baseline](scripts/01-onboarding-provisioning/set-windows-pc-baseline) | Action | Low | Windows 10, Windows 11 |
| [Remove the previous provider's RMM agent](scripts/01-onboarding-provisioning/uninstall-rmm-agent) | Action | High | Windows 10, Windows 11, Windows Server 2016+ |

### Software deployment & updates

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [Install an application from a URL, verified](scripts/02-software-deployment-updates/install-application-from-url) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Install Microsoft 365 Apps (Office) with a generated configuration](scripts/02-software-deployment-updates/install-microsoft-365-apps) | Action | Low | Windows 10 1809+, Windows 11, Windows Server 2019+ |
| [Uninstall an application silently by name](scripts/02-software-deployment-updates/uninstall-application) | Action | High | Windows 10, Windows 11, Windows Server 2016+ |
| [Update apps with winget](scripts/02-software-deployment-updates/update-winget-apps) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |

### Patching & Windows Update

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [Install Windows updates](scripts/03-patching-windows-update/install-windows-updates) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Windows Update stuck or failing - reset the update stack](scripts/03-patching-windows-update/reset-windows-update) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Is a vulnerable app version installed](scripts/03-patching-windows-update/test-app-version) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [End-of-life software installed](scripts/03-patching-windows-update/test-end-of-life-software) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Is a specific Windows update installed](scripts/03-patching-windows-update/test-kb-installed) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [How many days since this PC was patched](scripts/03-patching-windows-update/test-patch-age) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Can this PC run Windows 11?](scripts/03-patching-windows-update/test-windows11-readiness) | Monitor | Low | Windows 10, Windows 11 |
| [Windows 10 PC needs Windows 11 - check eligibility and start the in-place upgrade](scripts/03-patching-windows-update/update-windows-10-to-11) | Action | High | Windows 10 |

### Security hardening & compliance

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [SMBv1 still enabled - turn it off (can break old devices)](scripts/04-security-hardening-compliance/disable-smb1) | Action | High | Windows 10, Windows 11, Windows Server 2016+ |
| [Block USB storage with an allow-list](scripts/04-security-hardening-compliance/disable-usb-storage) | Action | High | Windows 10, Windows 11, Windows Server 2016+ |
| [Turn on BitLocker and store the recovery key](scripts/04-security-hardening-compliance/enable-bitlocker) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Windows Firewall is off - turn it on and block inbound](scripts/04-security-hardening-compliance/enable-windows-firewall) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Cyber-insurance questionnaire - device evidence pack](scripts/04-security-hardening-compliance/get-cyber-insurance-evidence) | Report | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Which remote-access tools are installed](scripts/04-security-hardening-compliance/get-remote-access-tools) | Report | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Too many local admins - remove the unapproved ones](scripts/04-security-hardening-compliance/remove-local-admin-members) | Action | High | Windows 10, Windows 11, Windows Server 2016+ |
| [Defender attack surface reduction rules - audit then block](scripts/04-security-hardening-compliance/set-defender-asr-rules) | Action | Low | Windows 10 1709+, Windows 11, Windows Server 2019+ |
| [Local admin password - rotate it and store it in a field](scripts/04-security-hardening-compliance/set-local-admin-password) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [BitLocker off or recovery key not escrowed](scripts/04-security-hardening-compliance/test-bitlocker-status) | Monitor | Low | Windows 10 Pro, Windows 11 Pro, Windows Server 2016+ |
| [FileVault is off or has no recovery key](scripts/04-security-hardening-compliance/test-filevault-status) | Monitor | Low | macOS 13+ |
| [Windows Firewall off or wide open - profile and port monitor](scripts/04-security-hardening-compliance/test-firewall-profiles) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Unapproved local administrators](scripts/04-security-hardening-compliance/test-local-admins) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Risky local accounts on this PC](scripts/04-security-hardening-compliance/test-local-user-hygiene) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [NTLMv1 and LM hashes still allowed](scripts/04-security-hardening-compliance/test-ntlm-settings) | Monitor | Low | Windows 10, 11, Server 2016+ (best on each DC) |
| [Remote Desktop open to the internet or without NLA](scripts/04-security-hardening-compliance/test-rdp-exposure) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Secure Boot 2023 certificate update](scripts/04-security-hardening-compliance/test-secure-boot-certificates) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [SMBv1 still enabled - find where and who uses it](scripts/04-security-hardening-compliance/test-smb1) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Unapproved remote-access tool installed](scripts/04-security-hardening-compliance/test-unapproved-remote-tools) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [USB storage not blocked - check the block policy](scripts/04-security-hardening-compliance/test-usb-storage-blocked) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Windows LAPS not configured or not backing up](scripts/04-security-hardening-compliance/test-windows-laps) | Monitor | Low | Windows 11, Windows 10 April 2023+, Server 2019+ |

### AV / EDR & incident response

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [End network isolation and restore the firewall](scripts/05-av-edr-incident-response/disable-network-isolation) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Isolate a PC from the network but keep the RMM](scripts/05-av-edr-incident-response/enable-network-isolation) | Action | High | Windows 10, Windows 11, Windows Server 2016+ |
| [Ransomware triage: collect the evidence before a reboot](scripts/05-av-edr-incident-response/get-ransomware-triage) | Report | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Defender turned off or broken - switch it back on](scripts/05-av-edr-incident-response/repair-defender) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Is Microsoft Defender actually protecting this PC - end-to-end health](scripts/05-av-edr-incident-response/test-defender-health) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |

### Identity: AD / Entra / M365 users

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [User locked out - unlock the account](scripts/06-identity-ad-entra-m365-users/clear-account-lockout) | Action | Low | Windows Server 2016+ (domain controller or domain member) |
| [Shared mailboxes that can sign in - block them](scripts/06-identity-ad-entra-m365-users/disable-shared-mailbox-sign-in) | Action | High | Windows 10, 11, Server 2016+, with the app certificate |
| [Disable stale AD users and computers and move them to a holding OU](scripts/06-identity-ad-entra-m365-users/disable-stale-ad-objects) | Action | High | Windows Server 2016+ (domain controller or domain member) |
| [Who is in this AD group - list its members](scripts/06-identity-ad-entra-m365-users/get-ad-group-members) | Report | Low | Windows Server 2016+ (domain controller or domain member) |
| [Passwords expiring soon - which AD users to warn](scripts/06-identity-ad-entra-m365-users/get-ad-password-expiry) | Report | Low | Windows Server 2016+ (domain controller or domain member) |
| [Export all Active Directory users with key attributes](scripts/06-identity-ad-entra-m365-users/get-ad-users) | Report | Low | Windows Server 2016+ (domain controller or domain member) |
| [Conditional Access drifted from our baseline](scripts/06-identity-ad-entra-m365-users/get-conditional-access-drift) | Report | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Directory sync errors and duplicate UPN or proxy address](scripts/06-identity-ad-entra-m365-users/get-directory-sync-errors) | Report | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Who holds admin roles in Microsoft 365](scripts/06-identity-ad-entra-m365-users/get-entra-admin-roles) | Report | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Which computers have a managed local admin password](scripts/06-identity-ad-entra-m365-users/get-laps-coverage) | Report | Low | Domain member for AD; any Windows for Entra ID |
| [Who still uses legacy authentication](scripts/06-identity-ad-entra-m365-users/get-legacy-auth-signins) | Report | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Stale AD users and computers - who has not signed in for 90 days](scripts/06-identity-ad-entra-m365-users/get-stale-ad-objects) | Report | Low | Windows Server 2016+ (domain controller or domain member) |
| [Stale guest accounts](scripts/06-identity-ad-entra-m365-users/get-stale-guests) | Report | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Identity posture of every client tenant](scripts/06-identity-ad-entra-m365-users/get-tenant-identity-posture) | Report | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Sign-in history of one user](scripts/06-identity-ad-entra-m365-users/get-user-signin-history) | Report | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Compromised M365 account - contain it in order](scripts/06-identity-ad-entra-m365-users/invoke-compromised-account-containment) | Action | High | Windows 10, 11, Server 2016+, with the app certificate |
| [Change not showing in Microsoft 365 - force an Entra Connect sync](scripts/06-identity-ad-entra-m365-users/invoke-entra-delta-sync) | Action | Low | Windows Server 2016+ (the Microsoft Entra Connect server) |
| [New starter same as Jane - copy group memberships](scripts/06-identity-ad-entra-m365-users/invoke-group-membership-copy) | Action | High | Windows 10, 11, Server 2016+, with the app certificate |
| [New employee - create the AD user like a template user](scripts/06-identity-ad-entra-m365-users/new-ad-user) | Action | Low | Windows Server 2016+ (domain controller or domain member) |
| [Create Microsoft 365 users from a CSV file](scripts/06-identity-ad-entra-m365-users/new-m365-users-from-csv) | Action | High | Windows 10, 11, Server 2016+, with the app certificate |
| [Remove risky app consents](scripts/06-identity-ad-entra-m365-users/remove-risky-app-consents) | Action | High | Windows 10, 11, Server 2016+, with the app certificate |
| [Remove stale guest accounts](scripts/06-identity-ad-entra-m365-users/remove-stale-guests) | Action | High | Windows 10, 11, Server 2016+, with the app certificate |
| [Reset an AD user's password - random, forced change at logon](scripts/06-identity-ad-entra-m365-users/reset-ad-user-password) | Action | Low | Windows Server 2016+ (domain controller or domain member) |
| [User lost their phone - reset MFA methods](scripts/06-identity-ad-entra-m365-users/reset-user-mfa-methods) | Action | High | Windows 10, 11, Server 2016+, with the app certificate |
| [AD security group - create it, add or remove members](scripts/06-identity-ad-entra-m365-users/set-ad-group-members) | Action | Low | Windows Server 2016+ (domain controller or domain member) |
| [Deploy the Conditional Access baseline](scripts/06-identity-ad-entra-m365-users/set-conditional-access-baseline) | Action | High | Windows 10, 11, Server 2016+, with the app certificate |
| [User keeps getting locked out - find the source](scripts/06-identity-ad-entra-m365-users/test-account-lockout-source) | Monitor | Low | Windows Server 2016+ (domain controller or domain member) |
| [AD accounts with weak password settings](scripts/06-identity-ad-entra-m365-users/test-ad-weak-account-settings) | Monitor | Low | Windows Server 2016+ (domain controller or domain member) |
| [Break-glass accounts present, excluded, unused](scripts/06-identity-ad-entra-m365-users/test-break-glass-accounts) | Monitor | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Is anything forcing MFA in Microsoft 365](scripts/06-identity-ad-entra-m365-users/test-conditional-access-state) | Monitor | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Entra Connect server health](scripts/06-identity-ad-entra-m365-users/test-entra-connect-health) | Monitor | Low | Windows Server 2016+ (the Microsoft Entra Connect server) |
| [Entra Connect stopped syncing](scripts/06-identity-ad-entra-m365-users/test-entra-connect-sync) | Monitor | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [SSO and Teams sign-in broken - Entra join and PRT health](scripts/06-identity-ad-entra-m365-users/test-entra-join-health) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Users without MFA or with SMS-only MFA](scripts/06-identity-ad-entra-m365-users/test-mfa-registration) | Monitor | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Someone was just made an admin](scripts/06-identity-ad-entra-m365-users/test-new-admin-assignments) | Monitor | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [New MFA method registered](scripts/06-identity-ad-entra-m365-users/test-new-mfa-methods) | Monitor | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Privileged AD groups - nested membership and change alerts](scripts/06-identity-ad-entra-m365-users/test-privileged-ad-groups) | Monitor | Low | Windows Server 2016+ (domain controller or domain member) |
| [Apps with risky Microsoft 365 permissions](scripts/06-identity-ad-entra-m365-users/test-risky-app-consents) | Monitor | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Shared mailboxes that can sign in](scripts/06-identity-ad-entra-m365-users/test-shared-mailbox-sign-in) | Monitor | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Users can consent to any app](scripts/06-identity-ad-entra-m365-users/test-user-consent-settings) | Monitor | Low | Windows 10, 11, Server 2016+, with the app certificate |

### Exchange & email

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [Audit logging off - turn on unified and mailbox auditing](scripts/07-exchange-email/enable-audit-logging) | Action | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [DKIM signing not on - create the config and turn it on](scripts/07-exchange-email/enable-dkim-signing) | Action | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Tag external email in Outlook](scripts/07-exchange-email/enable-external-email-tag) | Action | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Turn on the archive and auto-expanding archive](scripts/07-exchange-email/enable-mailbox-archive) | Action | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Is this domain protected from email spoofing - SPF, DKIM and DMARC check](scripts/07-exchange-email/get-email-authentication-posture) | Report | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Email protection below standard](scripts/07-exchange-email/get-email-protection-posture) | Report | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Who can access which mailbox](scripts/07-exchange-email/get-mailbox-permissions) | Report | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Mailbox nearly full - size and quota report](scripts/07-exchange-email/get-mailbox-sizes) | Report | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Where did this email go - message trace](scripts/07-exchange-email/get-message-trace) | Report | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Mail forwarding to outside addresses - turn it off](scripts/07-exchange-email/remove-external-mail-forwarding) | Action | High | Windows 10, 11, Server 2016+, with the app certificate |
| [Block automatic external forwarding for the tenant](scripts/07-exchange-email/set-external-forwarding-block) | Action | High | Windows 10, 11, Server 2016+, with the app certificate |
| [Give or remove mailbox access](scripts/07-exchange-email/set-mailbox-permission) | Action | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [DKIM signing not on for a domain](scripts/07-exchange-email/test-dkim-signing) | Monitor | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Mail forwarding to outside addresses](scripts/07-exchange-email/test-external-mail-forwarding) | Monitor | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Microsoft 365 app access check (permissions and certificate expiry)](scripts/07-exchange-email/test-m365-app-access) | Monitor | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [New inbox rules that hide mail](scripts/07-exchange-email/test-suspicious-inbox-rules) | Monitor | Low | Windows 10, 11, Server 2016+, with the app certificate |

### Backup & DR

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [Did last night's backup succeed?](scripts/08-backup-dr/test-backup-status) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [SQL Server backups too old](scripts/08-backup-dr/test-sql-backup-age) | Monitor | Low | Windows Server 2016+ with SQL Server 2012+ installed locally |

### Monitoring & health checks

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [Laptop battery worn out - capacity and cycle count](scripts/09-monitoring-health-checks/test-battery-health) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Certificate about to expire on this PC](scripts/09-monitoring-health-checks/test-certificate-expiry) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Drive about to fail - SMART health and SSD wear](scripts/09-monitoring-health-checks/test-disk-health) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Disk space below threshold](scripts/09-monitoring-health-checks/test-disk-space) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Something is logging errors - event ID and text match monitor](scripts/09-monitoring-health-checks/test-event-log-match) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [PC never rebooted - uptime and pending-reboot monitor](scripts/09-monitoring-health-checks/test-pending-reboot) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Service stopped - monitor](scripts/09-monitoring-health-checks/test-service-running) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Clock out of sync](scripts/09-monitoring-health-checks/test-time-sync) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [PC crashed or blue-screened - unexpected shutdown monitor](scripts/09-monitoring-health-checks/test-unexpected-shutdown) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |

### Disk, performance & cleanup

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [Disk full first aid - silent cleanup](scripts/10-disk-performance-cleanup/clear-disk-space) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [PC is slow - slow-PC first aid diagnostic](scripts/10-disk-performance-cleanup/get-slow-pc-diagnostics) | Report | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Shared PC full of ex-staff profiles - remove stale profiles](scripts/10-disk-performance-cleanup/remove-stale-user-profiles) | Action | High | Windows 10, Windows 11, Windows Server 2016+ |
| [PC is slow - sustained CPU and memory pressure with top processes](scripts/10-disk-performance-cleanup/test-cpu-memory-pressure) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |

### Networking, DNS, VPN, firewall

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [Website not resolving - flush the DNS cache](scripts/11-networking-dns-vpn-firewall/clear-dns-cache) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [What is on this network - list the devices on the local subnet](scripts/11-networking-dns-vpn-firewall/get-network-discovery) | Report | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Internet works but nothing loads - reset the network stack](scripts/11-networking-dns-vpn-firewall/reset-network-stack) | Action | High | Windows 10, Windows 11, Windows Server 2016+ |
| [Client domain about to expire (RDAP expiry check)](scripts/11-networking-dns-vpn-firewall/test-domain-expiry) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Is this PC exposing RDP, SMB or other risky ports through the firewall](scripts/11-networking-dns-vpn-firewall/test-exposed-ports) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Public SSL certificate about to expire (TLS check of your sites)](scripts/11-networking-dns-vpn-firewall/test-public-certificate-expiry) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |

### Printers & peripherals

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [Print queue stuck - clear the spooler](scripts/12-printers-peripherals/clear-print-queue) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |

### Inventory, reporting & audit

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [Which AI tools do staff use? - shadow AI apps](scripts/13-inventory-reporting-audit/get-ai-tools) | Report | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Is this PC ready for Microsoft 365 Copilot?](scripts/13-inventory-reporting-audit/get-copilot-readiness) | Report | Low | Windows 10, Windows 11 |
| [Who can open this folder - NTFS and share permissions](scripts/13-inventory-reporting-audit/get-folder-permissions) | Report | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Hardware and OS inventory](scripts/13-inventory-reporting-audit/get-hardware-inventory) | Report | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Installed software inventory and app finder](scripts/13-inventory-reporting-audit/get-installed-software) | Report | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Local user accounts on this PC](scripts/13-inventory-reporting-audit/get-local-users) | Report | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [PC facts for the quarterly review](scripts/13-inventory-reporting-audit/get-qbr-data-pack) | Report | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [New client tenant - Microsoft 365 onboarding audit](scripts/13-inventory-reporting-audit/get-tenant-onboarding-audit) | Report | Low | Windows 10, 11, Server 2016+, with the app certificate |

### Remediation & self-healing

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [Teams won't load - clear the Teams cache](scripts/14-remediation-self-healing/clear-teams-cache) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [RMM agent stopped, disabled or missing - start it again](scripts/14-remediation-self-healing/repair-rmm-agent) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [VPN won't connect - VPN first aid](scripts/14-remediation-self-healing/repair-vpn-client) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Windows corrupted or SFC fails - DISM then SFC repair](scripts/14-remediation-self-healing/repair-windows-image) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [OneDrive not syncing - reset it](scripts/14-remediation-self-healing/reset-onedrive) | Action | Low | Windows 10, Windows 11 |
| [Service stopped or hung - restart it](scripts/14-remediation-self-healing/restart-service) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [VPN client ready](scripts/14-remediation-self-healing/test-vpn-client) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |

### User profile & desktop config

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [Drives missing - map network drives](scripts/15-user-profile-desktop-config/set-mapped-drives) | Action | Low | Windows 10, Windows 11 |
| [OneDrive not syncing - health and Known Folder Move monitor](scripts/15-user-profile-desktop-config/test-onedrive-sync) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |

### Browser & application config

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [Which browser extensions are installed?](scripts/16-browser-application-config/get-browser-extensions) | Report | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Outlook slow or crashing - first-aid report](scripts/16-browser-application-config/get-outlook-diagnostics) | Report | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Outlook won't open or keeps asking for a password - rebuild the profile](scripts/16-browser-application-config/repair-outlook-profile) | Action | Low | Windows 10, Windows 11 |

### Offboarding & decommission

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [Employee left - disable in AD, strip groups, move, log off](scripts/17-offboarding-decommission/invoke-ad-offboarding) | Action | High | Windows Server 2016+ (domain controller or domain member) |
| [Lost or returned laptop - remote wipe or retire in Intune](scripts/17-offboarding-decommission/invoke-device-wipe) | Action | High | Windows 10, 11, Server 2016+, with the app certificate |
| [Employee left - Microsoft 365 offboarding](scripts/17-offboarding-decommission/invoke-m365-offboarding) | Action | High | Windows 10, 11, Server 2016+, with the app certificate |
| [Retire a PC - leave domain and Entra ID, remove MDM, write the record](scripts/17-offboarding-decommission/invoke-pc-retirement) | Action | High | Windows 10, Windows 11 |

### Server roles (AD DS, Hyper-V, SQL, IIS, file, RDS)

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [Windows DNS server - forwarders, aging and scavenging](scripts/18-server-roles-ad-ds-hyper-v-sql-iis-file-rds/get-dns-server-config) | Report | Low | Windows Server 2016+ (DNS Server role) |
| [Back up all GPOs with HTML reports](scripts/18-server-roles-ad-ds-hyper-v-sql-iis-file-rds/invoke-gpo-backup) | Action | Low | Windows Server 2016+ (DC, or a member with GPMC) |
| [Is Active Directory healthy - services, replication, FSMO, dcdiag](scripts/18-server-roles-ad-ds-hyper-v-sql-iis-file-rds/test-ad-health) | Monitor | Low | Windows Server 2016+ (domain controller) |
| [Domain controller backup too old](scripts/18-server-roles-ad-ds-hyper-v-sql-iis-file-rds/test-dc-backup-age) | Monitor | Low | Windows Server 2016+ (domain controller) |
| [Someone changed a GPO - alert on any GPO change](scripts/18-server-roles-ad-ds-hyper-v-sql-iis-file-rds/test-gpo-changes) | Monitor | Low | Windows Server 2016+ (DC, or a member with GPMC) |
| [Is the RDS session host healthy](scripts/18-server-roles-ad-ds-hyper-v-sql-iis-file-rds/test-rds-host-health) | Monitor | Low | Windows Server 2016+ with the Remote Desktop Session Host role |
| [Is SQL Server healthy](scripts/18-server-roles-ad-ds-hyper-v-sql-iis-file-rds/test-sql-server-health) | Monitor | Low | Windows Server 2016+ with SQL Server 2012+ installed locally |

### macOS management

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [Teams won't load on a Mac - clear the Teams cache](scripts/19-macos-management/clear-mac-teams-cache) | Action | Low | macOS 13+ |
| [Turn off Remote Login and Screen Sharing on a Mac](scripts/19-macos-management/disable-mac-remote-access) | Action | High | macOS 13+ |
| [Turn on the Mac firewall and stealth mode](scripts/19-macos-management/enable-mac-firewall) | Action | Low | macOS 13+ |
| [Mac health and security summary](scripts/19-macos-management/get-mac-health-summary) | Report | Low | macOS 13+ |
| [Install or update a Mac app from a link, verified by hash or developer](scripts/19-macos-management/install-mac-app) | Action | Low | macOS 13+ |
| [Install macOS updates now (all or recommended)](scripts/19-macos-management/install-macos-updates) | Action | Low | macOS 13+ |
| [Unapproved administrators on this Mac - demote them](scripts/19-macos-management/remove-mac-local-admin-members) | Action | High | macOS 13+ |
| [Mac network trouble - flush DNS, renew DHCP](scripts/19-macos-management/reset-mac-network) | Action | Low | macOS 13+ |
| [Mac local admin password - create or rotate a hidden admin](scripts/19-macos-management/set-mac-local-admin-password) | Action | High | macOS 13+ |
| [Mac firewall is off](scripts/19-macos-management/test-mac-firewall) | Monitor | Low | macOS 13+ |
| [Unapproved administrators on this Mac](scripts/19-macos-management/test-mac-local-admins) | Monitor | Low | macOS 13+ |
| [Remote Login or Screen Sharing is on](scripts/19-macos-management/test-mac-remote-access) | Monitor | Low | macOS 13+ |
| [Remove a Mac app and everything it left behind](scripts/19-macos-management/uninstall-mac-app) | Action | High | macOS 13+ |

### Linux management

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [Linux disk full: clear logs, journal and caches](scripts/20-linux-management/clear-linux-disk-space) | Action | Low | Ubuntu 22.04+, Debian 12+, RHEL/Rocky/Alma 9+ |
| [What is this Linux box? Health summary](scripts/20-linux-management/get-linux-health) | Report | Low | Ubuntu 22.04+, Debian 12+, RHEL/Rocky/Alma 9+ |
| [Who can SSH in? List authorized keys](scripts/20-linux-management/get-ssh-authorized-keys) | Report | Low | Ubuntu 22.04+, Debian 12+, RHEL/Rocky/Alma 9+ |
| [Patch this Linux server now](scripts/20-linux-management/install-linux-updates) | Action | Low | Ubuntu 22.04+, Debian 12+, RHEL/Rocky/Alma 9+ |
| [Remove an old SSH key from every account](scripts/20-linux-management/remove-ssh-authorized-key) | Action | High | Ubuntu 22.04+, Debian 12+, RHEL/Rocky/Alma 9+ |
| [Who has root? Unexpected sudo or UID 0 accounts](scripts/20-linux-management/test-linux-privileged-users) | Monitor | Low | Ubuntu 22.04+, Debian 12+, RHEL/Rocky/Alma 9+ |
| [Linux disk, memory or CPU over limit](scripts/20-linux-management/test-linux-resources) | Monitor | Low | Ubuntu 22.04+, Debian 12+, RHEL/Rocky/Alma 9+ |

### Cloud & Intune

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [Back up the whole Intune configuration to JSON](scripts/21-cloud-intune/invoke-intune-config-backup) | Action | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Package an app for Intune - build the .intunewin file](scripts/21-cloud-intune/new-intune-app-package) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Intune remediation - create the detection and remediation pair](scripts/21-cloud-intune/new-intune-remediation) | Action | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Stale and duplicate Intune devices - delete the old records](scripts/21-cloud-intune/remove-stale-intune-devices) | Action | High | Windows 10, 11, Server 2016+, with the app certificate |
| [App secret or certificate expiring in Microsoft 365](scripts/21-cloud-intune/test-app-credential-expiry) | Monitor | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Stale or duplicate devices in Intune](scripts/21-cloud-intune/test-stale-intune-devices) | Monitor | Low | Windows 10, 11, Server 2016+, with the app certificate |

### Licensing & asset lifecycle

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [Paying for unused Microsoft 365 licences](scripts/22-licensing-asset-lifecycle/get-unused-m365-licenses) | Report | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Reclaim Microsoft 365 licences from disabled users](scripts/22-licensing-asset-lifecycle/remove-unused-m365-licenses) | Action | High | Windows 10, 11, Server 2016+, with the app certificate |
| [Windows not activated - activation status and edition](scripts/22-licensing-asset-lifecycle/test-windows-activation) | Monitor | Low | Windows 10, Windows 11, Windows Server 2016+ |

### End-user communication & self-service

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [Tell the user something on a Mac - dialog or notification](scripts/23-end-user-communication-self-service/new-mac-user-notification) | Action | Low | macOS 13+ |
| [Report a problem - diagnostics and description in a zip](scripts/23-end-user-communication-self-service/new-problem-report) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Tell the user something - show a notification](scripts/23-end-user-communication-self-service/new-user-notification) | Action | Low | Windows 10, Windows 11 |
| [Restart a PC - now, at a set time or if pending](scripts/23-end-user-communication-self-service/restart-computer) | Action | High | Windows 10, Windows 11, Windows Server 2016+ |

### Utility / misc

| Script | Type | Risk | Platforms |
|---|---|---|---|
| [Run a command as the logged-in user (from SYSTEM)](scripts/24-utility-misc/invoke-as-logged-in-user) | Action | High | Windows 10, Windows 11, Windows Server 2016+ |
| [Download a file safely - https, SHA-256 check, size limit](scripts/24-utility-misc/invoke-file-download) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Send an email through Microsoft Graph from a script](scripts/24-utility-misc/invoke-graph-mail-send) | Action | Low | Windows 10, 11, Server 2016+, with the app certificate |
| [Wake a powered-off PC - Wake-on-LAN](scripts/24-utility-misc/invoke-wake-on-lan) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |
| [Create or update a scheduled task](scripts/24-utility-misc/new-scheduled-task) | Action | Low | Windows 10, Windows 11, Windows Server 2016+ |

## Contributing

Issues are welcome: a bug, a script that did not behave on your RMM, or a script you would like to see. Please say which Windows version and RMM you ran it on, and include the `RESULT:` line.

These scripts are maintained in MSP Outpost's own pipeline and tested on Windows before each release, so this repository is published from there. We cannot merge pull requests directly, but we read every suggestion and credit it when we use it.

## License

MIT, see [LICENSE](LICENSE).

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
