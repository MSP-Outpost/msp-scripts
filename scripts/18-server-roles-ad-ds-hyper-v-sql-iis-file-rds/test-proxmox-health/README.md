# Proxmox node, quorum, guests and storage unhealthy

> Alerts when a Proxmox VE node has lost quorum, a node is offline, a guest that should run is stopped, or storage is nearly full.

| | |
|---|---|
| Script | `test-proxmox-health.sh` |
| Type | Monitor |
| Category | Server roles (AD DS, Hyper-V, SQL, IIS, file, RDS) |
| Platforms | Proxmox VE 7+ (Debian Linux) |
| Runs as | root |
| Requires | bash 3.2; root on a Proxmox VE node; pvesh, pvecm and perl with JSON::PP (all shipped with Proxmox VE) |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-18 |

## What it does

THIS SCRIPT IS READ-ONLY. Run it as root on a Proxmox VE node (the RMM agent on the node, or a scheduled task). It checks, in this order: cluster quorum (pvecm status, the "Quorate" line; a node with no cluster configured is reported as standalone and does not alert), every cluster node online, every VM and container with "onboot: 1" in its configuration that is not running (templates are ignored), and every storage whose used space is over STORAGE_USED_PERCENT. Guests in EXCLUDE_GUESTS (VMIDs) are skipped. It is SKIPPED when this is not a Proxmox VE node (no pvesh command or no /etc/pve).

Where each fact comes from: pvecm status prints a "Quorum information" section with a "Quorate" line (pvecm manual page). "pvesh get <path> --output-format json" calls the REST API on the node itself (pvesh manual page; the path /cluster/resources and its fields come from Proxmox forum examples and the API viewer, not from the manual page). Guest configuration files are /etc/pve/nodes/<node>/qemu-server/<VMID>.conf and /etc/pve/nodes/<node>/lxc/<VMID>.conf, and corosync.conf marks a cluster (pmxcfs chapter). JSON is read with perl -MJSON::PP: JSON::PP has been a core perl module since perl 5.14 (perldoc), and Proxmox VE is itself written in perl; no jq is needed. Not confirmed in the documentation, so read defensively: the field names type, status, node, vmid, name, storage, disk, maxdisk and template of /cluster/resources (a missing field is treated as unknown, never as healthy), the exact "onboot: 1" line in the guest configuration files, and that a storage's disk and maxdisk are used and total bytes. A storage with no size is listed as "no size reported". NOT INCLUDED: last vzdump backup age per guest. The vzdump chapter documents backup file names and notes but no task-log query we could confirm, so a backup-age check is left for a version run against a real node. Use Proxmox's own backup job notifications meanwhile. A guest created in the last few seconds may not be in /cluster/resources yet and shows as "unknown" (an alert, never healthy) until Proxmox lists it; run again a minute later. To try it: on a node run "sudo ./test-proxmox-health.sh"; stop a guest that has onboot=1 (qm stop ID) and run again: it must alert and name the guest; run with --storage-used-percent 1 to force the storage alert.

## Inputs

| Input | Meaning | Default | Environment variable | Argument |
|---|---|---|---|---|
| `STORAGE_USED_PERCENT` | Alert when a storage is more than N% used. 1-99. Default 85. | `85` | `STORAGE_USED_PERCENT` | `--storage-used-percent` |
| `EXCLUDE_GUESTS` | VMIDs to skip, comma-separated. Default none. | (empty) | `EXCLUDE_GUESTS` | `--exclude-guests` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OUTPUT_FORMAT`, `EXPORT_PATH` and `RESULT_FIELD` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From a root shell (`sudo`) on the Mac or Linux machine, or from your RMM as a shell script:

```bash
sudo ./test-proxmox-health.sh
```

```bash
STORAGE_USED_PERCENT=90 EXCLUDE_GUESTS=100,101 OUTPUT_FORMAT=Json ./test-proxmox-health.sh
```

### In an RMM

Add the script to your RMM as a shell script (`#!/bin/bash`) and run it as root on macOS or Linux. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `STORAGE_USED_PERCENT`).
- **Command-line arguments:** `--storage-used-percent value`.
- **No variables at all:** edit the `DEFAULT_` line for that input near the top of the script body.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Proxmox: node pve2 is offline; onboot guest 104 (mail) is stopped; storage local-lvm on pve1 91% used (limit 85%)
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | Healthy, or it does not apply to this machine. |
| 1 | `ALERT` | The problem this monitor checks for was found. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Check`, `Item`, `Detail`, `Status`.

`OUTPUT_FORMAT` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `EXPORT_PATH` also writes the rows to a `.csv` or `.json` file.

`RESULT_FIELD` also writes the one-line answer to a custom field, on NinjaOne (field name) when its command-line tool is on the machine. On other RMMs, point their script output or collector at the script with `OUTPUT_FORMAT=Answer`.

## Changelog

- 1.0.0 2026-11-18 First version.

## More

Full page: https://mspoutpost.com/scripts/test-proxmox-health

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
