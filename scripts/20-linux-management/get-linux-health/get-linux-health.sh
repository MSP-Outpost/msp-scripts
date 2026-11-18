#!/bin/bash
# ---------------------------------------------------------------------------
# SYNOPSIS:    Reports what a Linux server is and how it is doing: OS, uptime, load, memory, disk, failed services, updates, reboot, firewall, SSH.
# DESCRIPTION:
#   THIS SCRIPT IS READ-ONLY. It collects one table of facts about this Linux
#   machine and always ends OK unless it cannot run at all:
#     System    distribution, kernel, architecture, virtualisation, CPU, uptime, boot time, signed-in sessions
#     Load      1, 5 and 15 minute load averages and the CPU count
#     Memory    RAM and swap, total and available
#     Disk      free space on every local volume (ext*, xfs, btrfs, zfs)
#     Services  failed systemd units (names)
#     Updates   updates waiting in the package manager's last-refreshed list, how many are security updates,
#               how old that list is, and whether a reboot is needed
#     Firewall  ufw, firewalld, nftables or iptables, whichever is in use
#     SSH       the effective sshd settings that matter (root login, password login, port)
#     Time      time zone and whether the clock is synchronised
#     Process   the five busiest processes by CPU and by memory
#   It never refreshes package lists, so the update counts are as fresh as the
#   last "apt update" or "dnf makecache"; the row "Package list age" says how
#   old. Run as root for the SSH and firewall rows; without root those rows say
#   "needs root" and everything else still works.
#   Tested on Ubuntu 24.04 (Arm64). The dnf, firewalld and RHEL paths are
#   written for Rocky/Alma/RHEL 9 and Debian 12 but not yet run.
# INPUTS:
#   --output-format F       (env OUTPUT_FORMAT)   Text (default), Answer, Json or Csv.
#   --export-path FILE      (env EXPORT_PATH)     Also write rows to this .csv or .json file.
#   --result-field NAME     (env RESULT_FIELD)    Also write the answer to this RMM custom field.
#   --dry-run               (env DRY_RUN)         Reserved; ignored by Reports.
# EXAMPLE:
#   sudo ./get-linux-health.sh
#   OUTPUT_FORMAT=Json ./get-linux-health.sh
# NOTES:
#   Name:        What is this Linux box? Health summary
#   Slug:        get-linux-health
#   Version:     1.0.0
#   Updated:     2026-11-17
#   Type:        Report
#   Category:    20 Linux management
#   Platforms:   Ubuntu 22.04+, Debian 12+, RHEL/Rocky/Alma 9+
#   RunAs:       Either
#   Requires:    bash 3.2, awk, /proc; root for the SSH and firewall rows
#   Changes:     None
#   Risk:        Low
#   Reboot:      Never
#   Runtime:     Under 20 seconds
#   Answer:      "Ubuntu 24.04.1 LTS, up 12d 3h; load 0.2; memory 41% used; / 70% free; 5 updates (2 security); no reboot needed; 0 failed units"
#   Fields:      Area, Item, Value
#   Runtime-Lib: 1.0.0
#   Source:      https://mspoutpost.com/scripts/get-linux-health
#   License:     MIT
#   Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
#   Changelog:
#     1.0.0  2026-11-17  First version.
# ---------------------------------------------------------------------------

# Identity: must match NOTES above (the build checks it).
OP_SLUG="get-linux-health"
OP_VERSION="1.0.0"
OP_TYPE="Report"
OP_RISK="Low"
OP_FIELDS=(Area Item Value)
OP_INPUTS=()

#region MSP Outpost runtime 1.0.0 -- do not edit (shared by every MSP Outpost script)
# Reads inputs, prints, collects rows, writes the RMM field, logs changes, exits.
# bash 3.2 compatible (macOS). Standard: https://mspoutpost.com/scripts/standard

set -uo pipefail
export LC_ALL=C

OP_STARTED_EPOCH=$(date -u +%s)
OP_STARTED_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
OP_ROWS=""
OP_WARNINGS=""
OP_ERRORS=""
OP_FIELD_VALUE=""
OP_FIELD_VALUE_SET=0
OP_SECRET_FIELD=0
OP_FORMAT="Text"
OP_DRY_RUN=0
OP_DONE=0
OP_HOST=$(hostname 2>/dev/null || uname -n)
case "$(uname -s)" in Darwin) OP_OS="macOS" ;; Linux) OP_OS="Linux" ;; *) OP_OS="$(uname -s)" ;; esac

# Arguments: --kebab-name value | --kebab-name=value | --flag (true) | --help.
# Each lands in OP_ARG_<UPPER_SNAKE>, read by the op_read_* functions.
OP_POSITIONAL=()
OP_IGNORED=""
op__parse_args() {
    # Jamf Pro always passes mount point, computer name and user name first.
    if [ "${1:-}" = "/" ] && [ "$#" -ge 3 ]; then shift 3; fi
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --help|-h)
                OP_DONE=1
                sed -n '2,/^# -\{20,\}$/p' "$0" | sed -n '2,$p' | sed 's/^# \{0,1\}//'
                exit 0 ;;
            --*=*)
                op__set_arg "${1%%=*}" "${1#*=}"; shift ;;
            --[A-Za-z]*|-[A-Za-z]*)
                if [ "$#" -gt 1 ] && [ "${2#-}" = "$2" ]; then op__set_arg "$1" "$2"; shift 2
                else op__set_arg "$1" "true"; shift; fi ;;
            *)
                OP_POSITIONAL+=("$1"); shift ;;
        esac
    done
    # Positional values fill this script's inputs in OP_INPUTS order (Jamf
    # parameters 4-11, N-sight, Tactical bash). An empty one means "not set".
    local slot=0 input
    for value in ${OP_POSITIONAL[@]+"${OP_POSITIONAL[@]}"}; do
        input=""
        while [ "$slot" -lt "${#OP_INPUTS[@]}" ]; do
            input="${OP_INPUTS[$slot]}"; slot=$((slot + 1))
            eval "[ -z \"\${OP_ARG_${input}+x}\" ]" && break
            input=""
        done
        if [ -z "$input" ]; then OP_IGNORED="${OP_IGNORED} '$value'"
        elif [ -n "$value" ]; then printf -v "OP_ARG_${input}" '%s' "$value"; fi
    done
}
op__set_arg() {
    local name
    name=$(printf '%s' "${1#-}" | sed 's/^-//' | tr 'a-z-' 'A-Z_')
    case " ${OP_INPUTS[*]:-} DRY_RUN OUTPUT_FORMAT EXPORT_PATH RESULT_FIELD APPROVE MAX_CHANGES " in
        *" $name "*) printf -v "OP_ARG_${name}" '%s' "$2" ;;
        *) OP_IGNORED="${OP_IGNORED} $1" ;;
    esac
}

op__pascal() { # MAX_AGE_DAYS -> MaxAgeDays
    printf '%s' "$1" | awk -F_ '{ for (i = 1; i <= NF; i++) printf "%s%s", toupper(substr($i,1,1)), tolower(substr($i,2)) }'
}

# op__raw NAME DEFAULT -> sets OP_RAW. Argument > env NAME/PascalCase/camelCase > default.
op__raw() {
    local name="$1" default="$2" pascal camel value
    eval "value=\${OP_ARG_${name}-__op_unset__}"
    if [ "$value" != "__op_unset__" ]; then OP_RAW="$value"; return; fi
    pascal=$(op__pascal "$name")
    camel="$(printf '%s' "${pascal:0:1}" | tr 'A-Z' 'a-z')${pascal:1}"
    for candidate in "$name" "$pascal" "$camel"; do
        eval "value=\${${candidate}-}"
        value=$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -n "$value" ]; then OP_RAW="$value"; return; fi
    done
    OP_RAW="$default"
}

op__bad_input() { op_fail "Input $1 is '$2'; expected $3. Set --$(printf '%s' "$1" | tr 'A-Z_' 'a-z-') or the environment variable $1."; }

# op_read_text VAR NAME DEFAULT [required]
op_read_text() {
    op__raw "$2" "$3"
    if [ "${4:-}" = "required" ] && [ -z "$OP_RAW" ]; then
        op_fail "Required input $2 is not set. Set --$(printf '%s' "$2" | tr 'A-Z_' 'a-z-') or the environment variable $2."
    fi
    printf -v "$1" '%s' "$OP_RAW"
}
# op_read_int VAR NAME DEFAULT MIN MAX
op_read_int() {
    op__raw "$2" "$3"
    case "$OP_RAW" in ''|*[!0-9-]*|?*-*) op__bad_input "$2" "$OP_RAW" "a whole number from $4 to $5" ;; esac
    if [ "$OP_RAW" -lt "$4" ] || [ "$OP_RAW" -gt "$5" ]; then op__bad_input "$2" "$OP_RAW" "a whole number from $4 to $5"; fi
    printf -v "$1" '%s' "$OP_RAW"
}
# op_read_bool VAR NAME DEFAULT   (sets VAR to 1 or 0)
op_read_bool() {
    op__raw "$2" "$3"
    case "$(printf '%s' "$OP_RAW" | tr 'A-Z' 'a-z')" in
        1|true|yes|y|on) printf -v "$1" '%s' 1 ;;
        ''|0|false|no|n|off) printf -v "$1" '%s' 0 ;;
        *) op__bad_input "$2" "$OP_RAW" "true or false (also yes/no, 1/0, on/off)" ;;
    esac
}
# op_read_choice VAR NAME DEFAULT CHOICE...
op_read_choice() {
    local var="$1" name="$2" lower choice
    op__raw "$2" "$3"; shift 3
    lower=$(printf '%s' "$OP_RAW" | tr 'A-Z' 'a-z')
    for choice in "$@"; do
        if [ "$lower" = "$(printf '%s' "$choice" | tr 'A-Z' 'a-z')" ]; then printf -v "$var" '%s' "$choice"; return; fi
    done
    op__bad_input "$name" "$OP_RAW" "one of: $*"
}
# op_read_list VAR NAME DEFAULT  (sets VAR to newline-separated items)
op_read_list() {
    op__raw "$2" "$3"
    printf -v "$1" '%s' "$(printf '%s' "$OP_RAW" | tr ',;' '\n\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d')"
}
# op_read_secret VAR NAME [required]   (environment variable only; never printed)
op_read_secret() {
    local value
    eval "value=\${$2-}"
    if [ "${3:-}" = "required" ] && [ -z "$value" ]; then
        op_fail "Required secret $2 is not set. Set the environment variable $2 (a secure/hidden field in your RMM)."
    fi
    printf -v "$1" '%s' "$value"
}

op_line() { if [ "$OP_FORMAT" = "Text" ]; then printf '%s\n' "$1"; fi; }
op_warn() { OP_WARNINGS="${OP_WARNINGS}${1}"$'\n'; op_line "WARNING: $1"; }
op_is_root() { [ "$(id -u)" -eq 0 ]; }
op_signed_in_user() { # console user on macOS, first graphical session on Linux; empty if none
    if [ "$OP_OS" = "macOS" ]; then
        stat -f %Su /dev/console 2>/dev/null | grep -v '^root$' || true
    else
        who 2>/dev/null | awk '$2 ~ /^(:|tty[0-9])/ { print $1; exit }'
    fi
}

op__clean() { printf '%s' "$1" | tr '\t\r\n' '   '; }

# op_row VALUE... (one value per field in OP_FIELDS, same order)
op_row() {
    local row="" value
    for value in "$@"; do row="${row}$(op__clean "$value")"$'\t'; done
    OP_ROWS="${OP_ROWS}${row%$'\t'}"$'\n'
}
op_set_field_value() { OP_FIELD_VALUE="$1"; OP_FIELD_VALUE_SET=1; }

op__log_file() {
    case "$OP_OS" in macOS) printf '/Library/Logs/MSPOutpost/%s.log' "$OP_SLUG" ;; *) printf '/var/log/mspoutpost/%s.log' "$OP_SLUG" ;; esac
}
op_log() {
    local file
    file=$(op__log_file)
    { mkdir -p "$(dirname "$file")" &&
      if [ -f "$file" ] && [ "$(wc -c < "$file")" -gt 1048576 ]; then mv -f "$file" "$file.old"; fi &&
      printf '%s  %s %s  %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$OP_SLUG" "$OP_VERSION" "$1" >> "$file"; } 2>/dev/null ||
        op_warn "Could not write the change log $file."
}

# op_change ITEM CHANGE COMMAND...   Every change an Action makes goes through here.
# Returns 0 when done, 1 in a dry run; a failing command fails the run.
op_change() {
    local item="$1" change="$2"; shift 2
    if [ "$OP_DRY_RUN" -eq 1 ]; then op_row "$item" "$change" "Would change"; return 1; fi
    # SAFETY 2, backstop: never more than MAX_CHANGES real changes in one run.
    if [ "$OP_MAX_CHANGES" -gt 0 ] && [ "$OP_CHANGES" -ge "$OP_MAX_CHANGES" ]; then
        op_fail "Stopped after $OP_MAX_CHANGES change(s): MAX_CHANGES is $OP_MAX_CHANGES. Run it again with a higher MAX_CHANGES to finish."
    fi
    if ! "$@"; then op_fail "Could not $(printf '%s' "$change" | tr 'A-Z' 'a-z') for $item."; fi
    OP_CHANGES=$((OP_CHANGES + 1))
    op_row "$item" "$change" "Done"
    op_log "CHANGED  $change  $item"
    return 0
}

# op_assert_change_limit PLANNED   SAFETY 2, planned: call before acting; over
# MAX_CHANGES nothing is changed (a dry run only warns).
op_assert_change_limit() {
    if [ "$OP_MAX_CHANGES" -le 0 ] || [ "$1" -le "$OP_MAX_CHANGES" ]; then return 0; fi
    if [ "$OP_DRY_RUN" -eq 1 ]; then
        op_warn "A real run would stop: $1 changes planned and MAX_CHANGES is $OP_MAX_CHANGES. Set MAX_CHANGES=$1 or more to allow it."
        return 0
    fi
    op_fail "$1 changes planned but MAX_CHANGES is $OP_MAX_CHANGES, so nothing was changed. Check the list with a dry run, then set MAX_CHANGES=$1 or more."
}

# op_backup PATH   SAFETY 3: copy a file or folder aside before changing it, under
# <log folder>/../Backups/<slug>/<time>/ (10 runs kept). Prints the backup path.
# Nothing happens in a dry run; a failed backup fails the run.
op_backup() {
    [ "$OP_DRY_RUN" -eq 1 ] && return 0
    local root target
    case "$OP_OS" in macOS) root="/Library/Application Support/MSPOutpost/Backups/$OP_SLUG" ;; *) root="/var/lib/mspoutpost/backups/$OP_SLUG" ;; esac
    if [ -z "${OP_BACKUP_DIR:-}" ]; then
        OP_BACKUP_DIR="$root/$(date -u +%Y%m%d-%H%M%S)"
        mkdir -p "$OP_BACKUP_DIR" || op_fail "Could not create the backup folder $OP_BACKUP_DIR."
        ls -1d "$root"/*/ 2>/dev/null | sort -r | tail -n +11 | while IFS= read -r old; do rm -rf "$old"; done
    fi
    target="$OP_BACKUP_DIR/$(printf '%s' "$1" | tr '/' '_')"
    cp -Rp "$1" "$target" 2>/dev/null || op_fail "Could not back up $1 before changing it."
    op_log "BACKUP  $1  ->  $target"
    printf '%s\n' "$target"
}

op_start() {
    op__parse_args "$@"
    op_read_choice OP_FORMAT OUTPUT_FORMAT "Text" Text Answer Json Csv
    local dry_default="false"
    if [ "$OP_RISK" = "High" ]; then dry_default="true"; fi
    op_read_bool OP_DRY_RUN DRY_RUN "$dry_default"
    if [ "$OP_TYPE" != "Action" ]; then OP_DRY_RUN=0; fi
    # SAFETY 1: a High-risk Action changes things only when APPROVE names THIS
    # script, so a site-wide DRY_RUN=false variable cannot unlock every script.
    local needs_approval=0
    op__raw APPROVE ""
    if [ "$OP_TYPE" = "Action" ] && [ "$OP_RISK" = "High" ] && [ "$OP_DRY_RUN" -eq 0 ] && [ "$OP_RAW" != "$OP_SLUG" ]; then
        needs_approval=1; OP_DRY_RUN=1
    fi
    # SAFETY 2: a cap on real changes per run (High risk: 25 unless MAX_CHANGES says otherwise).
    OP_CHANGES=0
    op__raw MAX_CHANGES ""
    if [ -n "$OP_RAW" ]; then op_read_int OP_MAX_CHANGES MAX_CHANGES "" 1 1000000
    elif [ "$OP_RISK" = "High" ]; then OP_MAX_CHANGES=25
    else OP_MAX_CHANGES=0; fi
    op_line "MSP Outpost | $OP_SLUG $OP_VERSION | $OP_HOST | $(date '+%Y-%m-%d %H:%M %z')"
    if [ -n "$OP_IGNORED" ]; then op_warn "Ignored unknown argument(s):${OP_IGNORED}. This script's inputs are listed by --help."; fi
    if [ "$needs_approval" -eq 1 ]; then op_warn "High-risk script: running as a dry run because APPROVE is not set to '$OP_SLUG'. To make the changes, set DRY_RUN=false and APPROVE=$OP_SLUG."; fi
    if [ "$OP_DRY_RUN" -eq 1 ]; then op_line "DRY RUN: nothing will be changed."; fi
}

op__json_value() {
    local s="$1"
    case "$s" in
        true|false) printf '%s' "$s"; return ;;
    esac
    if printf '%s' "$s" | grep -Eq '^-?(0|[1-9][0-9]*)(\.[0-9]+)?$'; then printf '%s' "$s"; return; fi
    s=${s//\\/\\\\}; s=${s//\"/\\\"}
    printf '"%s"' "$s"
}
op__json_list() { # newline-separated text -> JSON array of strings
    local first=1 item out="["
    while IFS= read -r item; do
        [ -z "$item" ] && continue
        if [ "$first" -eq 0 ]; then out="$out,"; fi
        item=${item//\\/\\\\}; item=${item//\"/\\\"}
        out="$out\"$item\""; first=0
    done <<EOF
$1
EOF
    printf '%s]' "$out"
}
op__rows_json() {
    local first=1 out="[" line i value fields
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        if [ "$first" -eq 0 ]; then out="$out,"; fi
        out="$out{"; i=0
        while [ "$i" -lt "${#OP_FIELDS[@]}" ]; do
            value=$(printf '%s' "$line" | awk -F'\t' -v n=$((i + 1)) '{ print $n }')
            if [ "$i" -gt 0 ]; then out="$out,"; fi
            out="$out\"${OP_FIELDS[$i]}\":$(op__json_value "$value")"
            i=$((i + 1))
        done
        out="$out}"; first=0
    done <<EOF
$OP_ROWS
EOF
    printf '%s]' "$out"
}
op__csv_cell() {
    case "$1" in *[,\"]*) printf '"%s"' "${1//\"/\"\"}" ;; *) printf '%s' "$1" ;; esac
}
op__rows_csv() {
    local line header="" i value cells
    for value in "${OP_FIELDS[@]}"; do header="$header$(op__csv_cell "$value"),"; done
    printf '%s\n' "${header%,}"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        cells=""; i=1
        while [ "$i" -le "${#OP_FIELDS[@]}" ]; do
            value=$(printf '%s' "$line" | awk -F'\t' -v n="$i" '{ print $n }')
            cells="$cells$(op__csv_cell "$value"),"
            i=$((i + 1))
        done
        printf '%s\n' "${cells%,}"
    done <<EOF
$OP_ROWS
EOF
}

op__write_field() {
    local name="$1" value="$2" cli
    for cli in "${NINJA_DATA_PATH:-/nonexistent}/ninjarmm-cli" /Applications/NinjaRMMAgent/programdata/ninjarmm-cli /opt/NinjaRMMAgent/programdata/ninjarmm-cli; do
        if [ -x "$cli" ]; then
            "$cli" set "$name" "$value" >/dev/null 2>&1 || op_warn "Could not write ResultField '$name' with ninjarmm-cli."
            return
        fi
    done
    op_warn "ResultField is set but no supported RMM was detected; the answer is in the RESULT line."
}

op__ninja_cli() { # prints the path of ninjarmm-cli, or nothing
    local cli
    for cli in "${NINJA_DATA_PATH:-/nonexistent}/ninjarmm-cli" /Applications/NinjaRMMAgent/programdata/ninjarmm-cli /opt/NinjaRMMAgent/programdata/ninjarmm-cli; do
        if [ -x "$cli" ]; then printf '%s' "$cli"; return; fi
    done
}

# op_assert_secret_field   Call in Validate, BEFORE changing anything, in a script that
# produces a secret (a generated password). The secret may only go to an RMM custom
# field: ResultField must be set, OutputFormat Answer is refused, and only NinjaOne is
# supported here, because its CLI takes the value on stdin (never on a command line,
# which every process can read). Other RMMs on macOS/Linux end ERROR, nothing changed.
op_assert_secret_field() {
    if [ "$OP_FORMAT" = "Answer" ]; then
        op_fail "OutputFormat Answer is not allowed here: this script produces a secret. Use Text or Json and a secure ResultField."
    fi
    op__raw RESULT_FIELD ""
    if [ -z "$OP_RAW" ]; then
        op_fail "Set ResultField to a secure/secret custom field first, so the new password is stored and not lost. Nothing was changed."
    fi
    if [ -z "$(op__ninja_cli)" ]; then
        op_fail "ResultField is set but NinjaOne's ninjarmm-cli was not found. On macOS and Linux a secret can only be stored through NinjaOne for now. Nothing was changed."
    fi
    OP_SECRET_FIELD=1
}

# op_write_secret_field VALUE   Writes the secret to ResultField once, through stdin.
# The value is never printed, logged or exported; op_finish will not overwrite the
# field with the answer. A failed write ends the run as ERROR.
op_write_secret_field() {
    local name cli
    if [ "$OP_SECRET_FIELD" -ne 1 ]; then op_fail "Script bug: call op_assert_secret_field in Validate before op_write_secret_field."; fi
    op__raw RESULT_FIELD ""; name="$OP_RAW"; cli=$(op__ninja_cli)
    if ! printf '%s' "$1" | "$cli" set --stdin "$name" >/dev/null 2>&1; then
        op_fail "The secret was created but could NOT be written to ResultField '$name'. Run again to create a new one."
    fi
    OP_SECRET_FIELD=2
    op_log "SECRET  written to ResultField $name (value not logged)"
}

# op_finish STATUS ANSWER   STATUS: OK CHANGED SKIPPED ALERT ERROR
op_finish() {
    local status="$1" answer="$2" exit_code=0 export_path result_field
    if [ "$OP_DONE" -eq 1 ]; then exit "${OP_EXIT_CODE:-2}"; fi
    OP_DONE=1
    case "$status" in OK|CHANGED|SKIPPED|ALERT|ERROR) ;; *) answer="Script bug: unknown status $status. $answer"; status="ERROR" ;; esac
    if [ "$status" = "ALERT" ] && [ "$OP_TYPE" != "Monitor" ]; then status="ERROR"; answer="Script bug: only a Monitor may ALERT. $answer"; fi
    if [ "$status" = "CHANGED" ] && [ "$OP_TYPE" != "Action" ]; then status="ERROR"; answer="Script bug: only an Action may report CHANGED. $answer"; fi
    if [ "$status" = "CHANGED" ] && [ "$OP_DRY_RUN" -eq 1 ]; then status="DRYRUN"; answer="Dry run, nothing changed. Would have: $answer"; fi
    answer=$(printf '%s' "$answer" | tr '\t\r\n' '   ' | sed 's/  */ /g;s/^ //;s/ $//')
    if [ "${#answer}" -gt 200 ]; then answer="${answer:0:197}..."; fi
    case "$status" in ALERT) exit_code=1 ;; ERROR) exit_code=2 ;; esac
    OP_EXIT_CODE=$exit_code

    if [ "$OP_FORMAT" = "Text" ] && [ -n "$OP_ROWS" ]; then
        printf '\n'
        { (IFS=$'\t'; printf '%s\n' "${OP_FIELDS[*]}"); printf '%s' "$OP_ROWS"; } |
            if command -v column >/dev/null 2>&1; then column -t -s $'\t'; else cat; fi
        printf '\n'
    fi

    op__raw EXPORT_PATH ""; export_path="$OP_RAW"
    if [ -n "$export_path" ]; then
        if mkdir -p "$(dirname "$export_path")" 2>/dev/null &&
           case "$export_path" in
               *.json) op__rows_json > "$export_path" ;;
               *) op__rows_csv > "$export_path" ;;
           esac; then
            op_line "Exported rows to $export_path"
        else
            op_warn "Could not export to '$export_path'."
        fi
    fi

    op__raw RESULT_FIELD ""; result_field="$OP_RAW"
    # A secret script's field holds the secret (or nothing): never the answer.
    if [ -n "$result_field" ] && [ "$OP_SECRET_FIELD" -eq 0 ]; then
        if [ "$OP_FIELD_VALUE_SET" -eq 1 ]; then op__write_field "$result_field" "$OP_FIELD_VALUE"
        else op__write_field "$result_field" "$answer"; fi
    fi

    if [ "$status" = "CHANGED" ] || [ "$status" = "DRYRUN" ]; then op_log "$status  $answer"; fi

    # Datto RMM monitors read the result between these markers.
    if [ "$OP_FORMAT" = "Text" ] && [ "$OP_TYPE" = "Monitor" ] && [ -n "${CS_PROFILE_UID:-}${CS_CC_HOST:-}" ]; then
        printf '<-Start Result->\nSTATUS=%s\n<-End Result->\n' "$answer"
    fi

    case "$OP_FORMAT" in
        Answer)
            if [ "$OP_FIELD_VALUE_SET" -eq 1 ]; then printf '%s\n' "$OP_FIELD_VALUE"; else printf '%s\n' "$answer"; fi ;;
        Json)
            printf '{"schema":"mspoutpost.result/1","script":%s,"version":%s,"computer":%s,"startedUtc":%s,"durationSeconds":%s,"status":%s,"exitCode":%s,"answer":%s,"fields":%s,"rows":%s,"warnings":%s,"errors":%s}\n' \
                "$(op__json_value "$OP_SLUG")" "\"$OP_VERSION\"" "$(op__json_value "$OP_HOST")" "\"$OP_STARTED_UTC\"" \
                "$(( $(date -u +%s) - OP_STARTED_EPOCH ))" "\"$status\"" "$exit_code" "$(op__json_value "$answer")" \
                "$(op__json_list "$(printf '%s\n' "${OP_FIELDS[@]}")")" "$(op__rows_json)" \
                "$(op__json_list "$OP_WARNINGS")" "$(op__json_list "$OP_ERRORS")" ;;
        Csv) op__rows_csv ;;
        *) printf 'RESULT: %s | %s\n' "$status" "$answer" ;;
    esac
    exit "$exit_code"
}

# op_fail MESSAGE   The one way a script fails: stderr, RESULT: ERROR, exit 2.
op_fail() {
    OP_ERRORS="${OP_ERRORS}${1}"$'\n'
    printf 'ERROR: %s\n' "$1" >&2
    op_finish ERROR "Error: $1"
}

# Anything that ends the script without op_finish (an unset variable, a bare
# exit) still ends with RESULT: ERROR and exit 2.
op__on_exit() {
    local code=$?
    if [ "$OP_DONE" -eq 0 ]; then
        trap - EXIT
        op_fail "The script stopped unexpectedly (exit code $code) before it finished."
    fi
}
trap op__on_exit EXIT
#endregion MSP Outpost runtime

# ---- Inputs: THIS SCRIPT'S defaults. Edit here if your RMM cannot pass variables.

# ---- Constants ------------------------------------------------------------
readonly LINUX_FS_TYPES="ext2,ext3,ext4,xfs,btrfs,zfs"

# ---- Functions ------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

# Runs a command with a time limit when `timeout` exists.
limited() {
    local seconds="$1"; shift
    if have timeout; then timeout "$seconds" "$@"; else "$@"; fi
}

list_volumes() {
    local mount device size avail fs_type
    df -kP -x tmpfs -x devtmpfs -x overlay -x squashfs 2>/dev/null |
        awk 'NR > 1 && !seen[$1]++ { print $6 "\t" $1 "\t" $2 "\t" $4 }' |
        while IFS=$'\t' read -r mount device size avail; do
            fs_type=$(findmnt -n -o FSTYPE --target "$mount" 2>/dev/null || echo unknown)
            case ",$LINUX_FS_TYPES," in *",$fs_type,"*) printf '%s\t%s\t%s\t%s\n' "$mount" "$device" "$size" "$avail" ;; esac
        done
}

# "12d 3h" from seconds.
human_uptime() {
    awk -v s="$1" 'BEGIN { d = int(s / 86400); h = int((s % 86400) / 3600); m = int((s % 3600) / 60);
        if (d > 0) printf "%dd %dh", d, h; else if (h > 0) printf "%dh %dm", h, m; else printf "%dm", m }'
}

# Sets UPDATES_TOTAL, UPDATES_SECURITY (numbers or "unknown"), LIST_AGE_DAYS and PACKAGE_MANAGER.
read_updates() {
    local counts stamp now
    UPDATES_TOTAL="unknown"; UPDATES_SECURITY="unknown"; LIST_AGE_DAYS="unknown"; PACKAGE_MANAGER="none"
    if have apt-get; then
        PACKAGE_MANAGER="apt"
        counts=$(apt-get -s -o Debug::NoLocking=1 --with-new-pkgs upgrade 2>/dev/null |
            awk '/^Inst / && $3 ~ /^\[.*\]$/ { n++; if ($0 ~ /-security/) s++ } END { print n + 0, s + 0 }')
        if [ -n "$counts" ]; then UPDATES_TOTAL="${counts% *}"; UPDATES_SECURITY="${counts#* }"; fi
        now=$(date +%s)
        for stamp in /var/lib/apt/periodic/update-success-stamp /var/lib/apt/lists; do
            if [ -e "$stamp" ]; then
                LIST_AGE_DAYS=$(( (now - $(stat -c %Y "$stamp" 2>/dev/null || echo "$now")) / 86400 ))
                break
            fi
        done
    elif have dnf; then
        PACKAGE_MANAGER="dnf"
        # -C = the cache only: this report never goes to the network.
        counts=$(limited 120 dnf -C -q check-update 2>/dev/null | awk '/^Obsoleting/ { exit } NF == 3 && $1 ~ /\.[A-Za-z0-9_]+$/ { n++ } END { print n + 0 }')
        if [ -n "$counts" ]; then UPDATES_TOTAL="$counts"; fi
        counts=$(limited 120 dnf -C -q check-update --security 2>/dev/null | awk '/^Obsoleting/ { exit } NF == 3 && $1 ~ /\.[A-Za-z0-9_]+$/ { n++ } END { print n + 0 }')
        if [ -n "$counts" ]; then UPDATES_SECURITY="$counts"; fi
        stamp=$(ls -1d /var/cache/dnf/*-*/ 2>/dev/null | head -1)
        if [ -n "$stamp" ]; then LIST_AGE_DAYS=$(( ($(date +%s) - $(stat -c %Y "$stamp" 2>/dev/null || date +%s)) / 86400 )); fi
    fi
}

# Prints "yes", "no" or "unknown".
reboot_needed() {
    if [ -f /var/run/reboot-required ] || [ -f /run/reboot-required ]; then printf 'yes'; return; fi
    if have needs-restarting; then
        if needs-restarting -r >/dev/null 2>&1; then printf 'no'; else printf 'yes'; fi
        return
    fi
    if have apt-get; then printf 'no'; else printf 'unknown'; fi
}

# Prints one line describing the firewall in use.
firewall_state() {
    local rules
    if ! op_is_root; then printf 'needs root'; return; fi
    if have ufw && ufw status 2>/dev/null | grep -qi '^Status: active'; then printf 'ufw active'; return; fi
    if have firewall-cmd && [ "$(firewall-cmd --state 2>/dev/null)" = "running" ]; then printf 'firewalld running'; return; fi
    if have nft; then
        rules=$(nft list ruleset 2>/dev/null | grep -Ec ' (drop|reject|accept)' || true)
        if [ "${rules:-0}" -gt 0 ] 2>/dev/null; then printf 'nftables, %s rules' "$rules"; return; fi
    fi
    if have iptables; then
        rules=$(iptables -S 2>/dev/null | grep -c '^-A' || true)
        if [ "${rules:-0}" -gt 0 ] 2>/dev/null; then printf 'iptables, %s rules' "$rules"; return; fi
    fi
    printf 'none detected'
}

# ---- Main -----------------------------------------------------------------
op_start "$@"
export PATH="${PATH:-/usr/bin:/bin}:/usr/sbin:/sbin:/usr/local/sbin"

# Validate
[ "$OP_OS" = "Linux" ] || op_finish SKIPPED "Skipped: this script is for Linux, this is $OP_OS."
if [ ! -r /proc/meminfo ] || [ ! -r /proc/loadavg ] || [ ! -r /proc/uptime ]; then
    op_fail "/proc is not readable. Run this on a Linux host, not a restricted container."
fi
op_line "Collecting a health summary of $OP_HOST."

# Detect: System
distro="unknown"
if [ -r /etc/os-release ]; then distro=$( (. /etc/os-release; printf '%s' "${PRETTY_NAME:-${NAME:-unknown}}") ); fi
virt="unknown"
if have systemd-detect-virt; then virt=$(systemd-detect-virt 2>/dev/null || true); fi
[ -n "$virt" ] || virt="unknown"
cpu_model=""
if have lscpu; then cpu_model=$(lscpu 2>/dev/null | awk -F: '/^Model name/ { gsub(/^[ \t]+/, "", $2); print $2; exit }'); fi
[ -n "$cpu_model" ] || cpu_model=$(awk -F: '/^model name/ { gsub(/^[ \t]+/, "", $2); print $2; exit }' /proc/cpuinfo 2>/dev/null)
[ -n "$cpu_model" ] || cpu_model="unknown"
cpus=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
uptime_seconds=$(awk '{ printf "%d", $1 }' /proc/uptime)
uptime_text=$(human_uptime "$uptime_seconds")
boot_utc=$(date -u -d "@$(( $(date +%s) - uptime_seconds ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)
sessions=$(who 2>/dev/null | wc -l | tr -d ' ')

op_row "System" "Distribution" "$distro"
op_row "System" "Kernel" "$(uname -r)"
op_row "System" "Architecture" "$(uname -m)"
op_row "System" "Virtualisation" "$virt"
op_row "System" "CPU" "$cpu_model"
op_row "System" "CPU count" "$cpus"
op_row "System" "Uptime" "$uptime_text"
op_row "System" "Booted (UTC)" "$boot_utc"
op_row "System" "Signed-in sessions" "$sessions"

# Load
load1=$(awk '{ print $1 }' /proc/loadavg)
load5=$(awk '{ print $2 }' /proc/loadavg)
load15=$(awk '{ print $3 }' /proc/loadavg)
op_row "Load" "1 minute" "$load1"
op_row "Load" "5 minutes" "$load5"
op_row "Load" "15 minutes" "$load15"

# Memory (MB)
mem_line=$(awk '
    $1 == "MemTotal:" { t = $2 }
    $1 == "MemAvailable:" { a = $2; have = 1 }
    $1 == "MemFree:" { f = $2 }
    $1 == "Buffers:" { b = $2 }
    $1 == "Cached:" { c = $2 }
    $1 == "SwapTotal:" { st = $2 }
    $1 == "SwapFree:" { sf = $2 }
    END { if (!have) a = f + b + c; printf "%d %d %d %d", t / 1024, a / 1024, st / 1024, (st - sf) / 1024 }' /proc/meminfo)
set -- $mem_line
mem_total_mb="$1"; mem_avail_mb="$2"; swap_total_mb="$3"; swap_used_mb="$4"
mem_used_percent=0
if [ "$mem_total_mb" -gt 0 ]; then mem_used_percent=$(( (mem_total_mb - mem_avail_mb) * 100 / mem_total_mb )); fi
op_row "Memory" "RAM total MB" "$mem_total_mb"
op_row "Memory" "RAM available MB" "$mem_avail_mb"
op_row "Memory" "RAM used percent" "$mem_used_percent"
op_row "Memory" "Swap total MB" "$swap_total_mb"
op_row "Memory" "Swap used MB" "$swap_used_mb"

# Disk
worst_mount=""
worst_percent=101
while IFS=$'\t' read -r mount device size_kb avail_kb; do
    [ -z "$mount" ] && continue
    [ "$size_kb" -gt 0 ] 2>/dev/null || continue
    free_percent=$(( avail_kb * 100 / size_kb ))
    op_row "Disk" "$mount" "${free_percent}% free ($(( avail_kb / 1048576 )) GB of $(( size_kb / 1048576 )) GB, $device)"
    if [ "$free_percent" -lt "$worst_percent" ]; then worst_percent=$free_percent; worst_mount="$mount"; fi
done <<EOF
$(list_volumes)
EOF

# Services
failed_count="unknown"
if have systemctl && [ -d /run/systemd/system ]; then
    failed_units=$(systemctl --failed --no-legend --plain 2>/dev/null | awk 'NF { print $1 }')
    failed_count=$(printf '%s\n' "$failed_units" | sed '/^$/d' | wc -l | tr -d ' ')
    op_row "Services" "Failed units" "$failed_count"
    if [ "$failed_count" -gt 0 ]; then
        op_row "Services" "Failed unit names" "$(printf '%s' "$failed_units" | tr '\n' ' ')"
    fi
else
    op_row "Services" "Failed units" "systemd not running"
fi

# Updates
read_updates
reboot_text=$(reboot_needed)
op_row "Updates" "Package manager" "$PACKAGE_MANAGER"
op_row "Updates" "Updates waiting" "$UPDATES_TOTAL"
op_row "Updates" "Security updates waiting" "$UPDATES_SECURITY"
op_row "Updates" "Package list age days" "$LIST_AGE_DAYS"
op_row "Updates" "Reboot needed" "$reboot_text"

# Firewall
op_row "Firewall" "State" "$(firewall_state)"

# SSH
if have sshd || [ -x /usr/sbin/sshd ]; then
    if op_is_root; then
        sshd_config=$(sshd -T 2>/dev/null || /usr/sbin/sshd -T 2>/dev/null || true)
        if [ -n "$sshd_config" ]; then
            op_row "SSH" "Port" "$(printf '%s\n' "$sshd_config" | awk '$1 == "port" { print $2; exit }')"
            op_row "SSH" "PermitRootLogin" "$(printf '%s\n' "$sshd_config" | awk '$1 == "permitrootlogin" { print $2; exit }')"
            op_row "SSH" "PasswordAuthentication" "$(printf '%s\n' "$sshd_config" | awk '$1 == "passwordauthentication" { print $2; exit }')"
            op_row "SSH" "PubkeyAuthentication" "$(printf '%s\n' "$sshd_config" | awk '$1 == "pubkeyauthentication" { print $2; exit }')"
        else
            op_row "SSH" "Effective settings" "sshd -T failed"
        fi
    else
        op_row "SSH" "Effective settings" "needs root"
    fi
else
    op_row "SSH" "Server" "sshd not installed"
fi

# Time
if have timedatectl; then
    op_row "Time" "Time zone" "$(timedatectl show -p Timezone 2>/dev/null | cut -d= -f2)"
    op_row "Time" "Clock synchronised" "$(timedatectl show -p NTPSynchronized 2>/dev/null | cut -d= -f2)"
else
    op_row "Time" "Time zone" "$(date +%Z)"
fi

# Processes
if have ps; then
    while IFS=$'\t' read -r name cpu mem; do
        [ -z "$name" ] && continue
        op_row "Process" "Top CPU: $name" "cpu ${cpu}%, memory ${mem}%"
    done <<EOF
$(ps -eo pcpu=,pmem=,comm= --sort=-pcpu 2>/dev/null | head -5 | awk '{ n = $3; for (i = 4; i <= NF; i++) n = n " " $i; print n "\t" $1 "\t" $2 }')
EOF
    while IFS=$'\t' read -r name cpu mem; do
        [ -z "$name" ] && continue
        op_row "Process" "Top memory: $name" "cpu ${cpu}%, memory ${mem}%"
    done <<EOF
$(ps -eo pcpu=,pmem=,comm= --sort=-pmem 2>/dev/null | head -5 | awk '{ n = $3; for (i = 4; i <= NF; i++) n = n " " $i; print n "\t" $1 "\t" $2 }')
EOF
fi

# Finish
reboot_answer="reboot status unknown"
case "$reboot_text" in yes) reboot_answer="REBOOT NEEDED" ;; no) reboot_answer="no reboot needed" ;; esac
updates_answer="updates unknown"
if [ "$UPDATES_TOTAL" != "unknown" ]; then updates_answer="$UPDATES_TOTAL updates ($UPDATES_SECURITY security)"; fi
disk_answer="no disk data"
if [ -n "$worst_mount" ]; then disk_answer="$worst_mount ${worst_percent}% free"; fi
op_finish OK "$distro, up $uptime_text; load $load5; memory ${mem_used_percent}% used; $disk_answer; $updates_answer; $reboot_answer; $failed_count failed units"
