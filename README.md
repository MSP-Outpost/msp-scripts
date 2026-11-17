# MSP Scripts

> PowerShell scripts for MSPs: monitors, reports and safe fixes for Windows, from [MSP Outpost](https://mspoutpost.com/scripts).

This repository holds 26 Windows scripts. Each one has its own folder with the script and a README that explains what it does, what it changes, which inputs it takes and how to run it in your RMM. Each script is one self-contained file: no modules to install, nothing else to copy.

## Safety first

Scripts run as SYSTEM on client machines, so these are the rules every script follows:

- **Monitors and reports are read-only.** `test-` scripts check one condition and exit 1 when it is not healthy. `get-` scripts collect information. Neither changes anything.
- **Actions are dry-run friendly.** Every action supports `-WhatIf` / `DryRun=true` and lists each change it would make.
- **High-risk actions need approval.** A script that deletes data or removes software is a dry run unless you set both `DryRun=false` and `Approve=<script name>`. Typing the name is deliberate, so one site-wide variable can never unlock every destructive script.
- **Change limits.** `MaxChanges` (default 25 for high-risk scripts) caps how many changes one run can make.
- **Backups.** Before an action edits or deletes configuration, it copies it to `%ProgramData%\MSPOutpost\Backups`.
- **A log you can show a client.** Every change an action makes is written to `%ProgramData%\MSPOutpost\Logs\<script>.log`.
- **Protected things are never touched:** the RMM agent running the script, system accounts, service profiles and signed-in users.
- **No prompts, no secrets in files, no downloads without verification.**

Read a script before you run it, test it on a non-production machine first, and use the dry run.

## How to run a script in any RMM

1. Open the script folder and read its README.
2. Add the `.ps1` file to your RMM as a PowerShell script and run it as the System account.
3. Set its inputs the way your RMM allows: script variables or environment variables with the same name as the input (PascalCase such as `MinAgeDays`, or UPPER_SNAKE such as `MIN_AGE_DAYS`), command-line arguments (`-MinAgeDays 180`), or by editing the default in the `param()` block at the top of the file.
4. Read the result: the exit code (0 fine, 1 alert, 2 error) and the last line of output, which is always `RESULT: <status> | <answer>`. Set `ResultField` to also write the answer to a custom field (NinjaOne, Datto RMM and Syncro), or `OutputFormat=Answer` to print only the answer.

The full rules for inputs, output and safety are in [docs/STANDARD.md](docs/STANDARD.md).

## Scripts

### Onboarding & provisioning

| Script | Type | Risk |
|---|---|---|
| [Which other RMM agents are on this PC](scripts/01-onboarding-provisioning/get-rmm-agents) | Report | Low |

### Software deployment & updates

| Script | Type | Risk |
|---|---|---|
| [Uninstall an application silently by name](scripts/02-software-deployment-updates/uninstall-application) | Action | High |

### Patching & Windows Update

| Script | Type | Risk |
|---|---|---|
| [Windows Update stuck or failing - reset the update stack](scripts/03-patching-windows-update/reset-windows-update) | Action | Low |
| [How many days since this PC was patched](scripts/03-patching-windows-update/test-patch-age) | Monitor | Low |
| [Can this PC run Windows 11?](scripts/03-patching-windows-update/test-windows11-readiness) | Monitor | Low |

### Security hardening & compliance

| Script | Type | Risk |
|---|---|---|
| [Which remote-access tools are installed](scripts/04-security-hardening-compliance/get-remote-access-tools) | Report | Low |
| [BitLocker off or recovery key not escrowed](scripts/04-security-hardening-compliance/test-bitlocker-status) | Monitor | Low |
| [Windows Firewall off or wide open - profile and port monitor](scripts/04-security-hardening-compliance/test-firewall-profiles) | Monitor | Low |
| [Unapproved local administrators](scripts/04-security-hardening-compliance/test-local-admins) | Monitor | Low |
| [Unapproved remote-access tool installed](scripts/04-security-hardening-compliance/test-unapproved-remote-tools) | Monitor | Low |

### AV / EDR & incident response

| Script | Type | Risk |
|---|---|---|
| [Is Microsoft Defender actually protecting this PC - end-to-end health](scripts/05-av-edr-incident-response/test-defender-health) | Monitor | Low |

### Monitoring & health checks

| Script | Type | Risk |
|---|---|---|
| [Disk space below threshold](scripts/09-monitoring-health-checks/test-disk-space) | Monitor | Low |
| [Something is logging errors - event ID and text match monitor](scripts/09-monitoring-health-checks/test-event-log-match) | Monitor | Low |
| [PC never rebooted - uptime and pending-reboot monitor](scripts/09-monitoring-health-checks/test-pending-reboot) | Monitor | Low |
| [Service stopped - monitor](scripts/09-monitoring-health-checks/test-service-running) | Monitor | Low |
| [PC crashed or blue-screened - unexpected shutdown monitor](scripts/09-monitoring-health-checks/test-unexpected-shutdown) | Monitor | Low |

### Disk, performance & cleanup

| Script | Type | Risk |
|---|---|---|
| [Disk full first aid - silent cleanup](scripts/10-disk-performance-cleanup/clear-disk-space) | Action | Low |
| [Shared PC full of ex-staff profiles - remove stale profiles](scripts/10-disk-performance-cleanup/remove-stale-user-profiles) | Action | High |

### Networking, DNS, VPN, firewall

| Script | Type | Risk |
|---|---|---|
| [Website not resolving - flush the DNS cache](scripts/11-networking-dns-vpn-firewall/clear-dns-cache) | Action | Low |
| [Internet works but nothing loads - reset the network stack](scripts/11-networking-dns-vpn-firewall/reset-network-stack) | Action | High |

### Printers & peripherals

| Script | Type | Risk |
|---|---|---|
| [Print queue stuck - clear the spooler](scripts/12-printers-peripherals/clear-print-queue) | Action | Low |

### Inventory, reporting & audit

| Script | Type | Risk |
|---|---|---|
| [Hardware and OS inventory](scripts/13-inventory-reporting-audit/get-hardware-inventory) | Report | Low |
| [Installed software inventory and app finder](scripts/13-inventory-reporting-audit/get-installed-software) | Report | Low |

### Remediation & self-healing

| Script | Type | Risk |
|---|---|---|
| [Teams won't load - clear the Teams cache](scripts/14-remediation-self-healing/clear-teams-cache) | Action | Low |
| [Windows corrupted or SFC fails - DISM then SFC repair](scripts/14-remediation-self-healing/repair-windows-image) | Action | Low |
| [Service stopped or hung - restart it](scripts/14-remediation-self-healing/restart-service) | Action | Low |

## Contributing

Issues are welcome: a bug, a script that did not behave on your RMM, or a script you would like to see. Please say which Windows version and RMM you ran it on, and include the `RESULT:` line.

These scripts are maintained in MSP Outpost's own pipeline and tested on Windows before each release, so this repository is published from there. We cannot merge pull requests directly, but we read every suggestion and credit it when we use it.

## License

MIT, see [LICENSE](LICENSE).

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
