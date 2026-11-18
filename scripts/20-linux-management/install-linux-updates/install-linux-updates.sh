#!/bin/bash
# ---------------------------------------------------------------------------
# SYNOPSIS:    Installs the waiting package updates on a Linux server (all, or security only) and says whether a reboot is needed.
# DESCRIPTION:
#   THIS SCRIPT CHANGES THINGS. It refreshes the package list, works out which
#   installed packages have an update waiting, installs them, and checks the
#   list again. apt (Ubuntu, Debian) and dnf (RHEL, Rocky, Alma, Fedora) are
#   supported; SUSE and Arch are not.
#   UPDATE_SCOPE=Security (default) installs only updates published as
#   security updates; All installs every update. Held packages (apt-mark hold,
#   dnf versionlock) are left alone. New packages that an update needs (a new
#   kernel image, for example) are installed with it; nothing is ever removed.
#   EXCLUDE_PACKAGES names packages never to update.
#   Refreshing the package list is not counted as a change, so it also happens
#   in a dry run: otherwise the dry run would list yesterday's updates.
#   Services are not restarted behind your back: needrestart is set to list
#   mode, so a service that still runs old libraries keeps running until you
#   restart it or reboot.
#   Reboots: it NEVER reboots unless REBOOT_IF_REQUIRED is true AND nobody is
#   signed in at the console or a desktop session (SSH sessions, which include
#   the RMM, do not count); then it schedules a reboot in one minute
#   ("shutdown -c" cancels it). In every other case the answer says "reboot
#   required" when the machine needs one. A reboot already pending from
#   earlier updates is also done when REBOOT_IF_REQUIRED is true.
#   The package manager's own output goes to
#   /var/log/mspoutpost/install-linux-updates.pm.log (the last run only);
#   every installed package is also written to the change log.
#   Tested on Ubuntu 24.04 (Arm64), apt only. The dnf path, Debian 12 and
#   RHEL/Rocky/Alma 9 are written for but not yet run.
# INPUTS:
#   --update-scope S           (env UPDATE_SCOPE)         Security (default) or All.
#   --exclude-packages LIST    (env EXCLUDE_PACKAGES)     Package names never to update, comma-separated. Default none.
#   --reboot-if-required B     (env REBOOT_IF_REQUIRED)   true to reboot (in one minute) when needed and nobody is signed in. Default false.
#   --dry-run B                (env DRY_RUN)              true lists the updates it would install and installs none. Default false.
#   --output-format F          (env OUTPUT_FORMAT)        Text (default), Answer, Json or Csv.
#   --export-path FILE         (env EXPORT_PATH)          Also write rows to this .csv or .json file.
#   --result-field NAME        (env RESULT_FIELD)         Also write the answer to this RMM custom field.
# EXAMPLE:
#   sudo ./install-linux-updates.sh --dry-run true
#   sudo UPDATE_SCOPE=All REBOOT_IF_REQUIRED=true ./install-linux-updates.sh
# NOTES:
#   Name:        Patch this Linux server now
#   Slug:        install-linux-updates
#   Version:     1.0.0
#   Updated:     2026-11-17
#   Type:        Action
#   Category:    20 Linux management
#   Platforms:   Ubuntu 22.04+, Debian 12+, RHEL/Rocky/Alma 9+
#   RunAs:       System
#   Requires:    bash 3.2, root, apt-get or dnf, network access to the package repositories
#   Changes:     Installs package updates (and any new packages they need); optionally schedules a reboot
#   Risk:        Low
#   Reboot:      Restarts
#   Runtime:     1 to 30 minutes
#   Answer:      "Installed 7 security updates; reboot required"
#   Fields:      Item, Change, Result
#   Runtime-Lib: 1.0.0
#   Source:      https://mspoutpost.com/scripts/install-linux-updates
#   License:     MIT
#   Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
#   Changelog:
#     1.0.0  2026-11-17  First version.
# ---------------------------------------------------------------------------

# Identity: must match NOTES above (the build checks it).
OP_SLUG="install-linux-updates"
OP_VERSION="1.0.0"
OP_TYPE="Action"
OP_RISK="Low"
OP_FIELDS=(Item Change Result)
OP_INPUTS=(UPDATE_SCOPE EXCLUDE_PACKAGES REBOOT_IF_REQUIRED)

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
DEFAULT_UPDATE_SCOPE="Security"
DEFAULT_EXCLUDE_PACKAGES=""
DEFAULT_REBOOT_IF_REQUIRED="false"

# ---- Constants ------------------------------------------------------------
readonly PM_LOG="/var/log/mspoutpost/install-linux-updates.pm.log"
readonly MAX_ROWS=200

# ---- Functions ------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

# apt_run ARGS...  Runs apt-get without questions; waits out a package lock held by another process.
apt_run() {
    local attempt=1 rc
    while :; do
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
            apt-get -y -o DPkg::Lock::Timeout=300 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@" >> "$PM_LOG" 2>&1
        rc=$?
        if [ "$rc" -eq 0 ]; then return 0; fi
        if [ "$attempt" -lt 10 ] && tail -n 8 "$PM_LOG" | grep -Eqi 'could not get lock|unable to acquire the|is held by process'; then
            attempt=$((attempt + 1))
            sleep 20
            continue
        fi
        return "$rc"
    done
}

# Fails the run with the end of the package manager's log.
fail_with_log() {
    op_fail "$1 The last lines of $PM_LOG: $(tail -n 4 "$PM_LOG" 2>/dev/null | tr '\n' ' ')"
}

# Prints "package<TAB>installed version<TAB>new version" for every update in scope, one per line.
list_pending() {
    case "$PACKAGE_MANAGER" in
        apt)
            apt-get -s -o Debug::NoLocking=1 --with-new-pkgs upgrade 2>/dev/null |
                SCOPE="$update_scope" EXCLUDED="$exclude_packages" awk '
                    BEGIN { n = split(ENVIRON["EXCLUDED"], list, "\n"); for (i = 1; i <= n; i++) if (list[i] != "") skip[list[i]] = 1 }
                    /^Inst / && $3 ~ /^\[.*\]$/ {
                        if (ENVIRON["SCOPE"] == "Security" && $0 !~ /-security/) next
                        if ($2 in skip) next
                        old = $3; sub(/^\[/, "", old); sub(/\]$/, "", old)
                        new = $0; sub(/^[^(]*\(/, "", new); sub(/ .*$/, "", new)
                        print $2 "\t" old "\t" new
                    }' ;;
        dnf)
            local security_flag="" exclude_flag=""
            if [ "$update_scope" = "Security" ]; then security_flag="--security"; fi
            if [ -n "$exclude_packages" ]; then exclude_flag="--exclude=$(printf '%s' "$exclude_packages" | tr '\n' ',')"; fi
            # shellcheck disable=SC2086
            dnf -q check-update $security_flag $exclude_flag 2>/dev/null |
                awk '/^Obsoleting/ { exit } NF == 3 && $1 ~ /\.[A-Za-z0-9_]+$/ { print $1 "\t" "-" "\t" $2 }' ;;
    esac
}

# Installs the packages in $pending (apt) or everything in scope (dnf).
apply_updates() {
    local names security_flag="" exclude_flag=""
    case "$PACKAGE_MANAGER" in
        apt)
            names=$(printf '%s\n' "$pending" | awk -F'\t' '{ print $1 }' | tr '\n' ' ')
            # shellcheck disable=SC2086
            apt_run install --only-upgrade $names || fail_with_log "apt-get could not install the updates."
            ;;
        dnf)
            if [ "$update_scope" = "Security" ]; then security_flag="--security"; fi
            if [ -n "$exclude_packages" ]; then exclude_flag="--exclude=$(printf '%s' "$exclude_packages" | tr '\n' ',')"; fi
            # shellcheck disable=SC2086
            dnf -y upgrade $security_flag $exclude_flag >> "$PM_LOG" 2>&1 || fail_with_log "dnf could not install the updates."
            ;;
    esac
}

# Prints "yes", "no" or "unknown".
reboot_required() {
    local latest
    if [ -f /var/run/reboot-required ] || [ -f /run/reboot-required ]; then printf 'yes'; return; fi
    if [ "$PACKAGE_MANAGER" = "apt" ]; then printf 'no'; return; fi
    if have needs-restarting; then
        if needs-restarting -r >/dev/null 2>&1; then printf 'no'; else printf 'yes'; fi
        return
    fi
    latest=$(rpm -q --last kernel-core 2>/dev/null | head -1 | awk '{ print $1 }' | sed 's/^kernel-core-//')
    if [ -n "$latest" ]; then
        if [ "$latest" = "$(uname -r)" ]; then printf 'no'; else printf 'yes'; fi
        return
    fi
    printf 'unknown'
}

schedule_reboot() {
    shutdown -r +1 "MSP Outpost: restarting to finish installing updates" >/dev/null 2>&1
}

# ---- Main -----------------------------------------------------------------
op_start "$@"
export PATH="${PATH:-/usr/bin:/bin}:/usr/sbin:/sbin:/usr/local/sbin"

# Validate
op_read_choice update_scope UPDATE_SCOPE "$DEFAULT_UPDATE_SCOPE" Security All
op_read_list exclude_packages EXCLUDE_PACKAGES "$DEFAULT_EXCLUDE_PACKAGES"
op_read_bool reboot_if_required REBOOT_IF_REQUIRED "$DEFAULT_REBOOT_IF_REQUIRED"
[ "$OP_OS" = "Linux" ] || op_finish SKIPPED "Skipped: this script is for Linux, this is $OP_OS."
op_is_root || op_fail "This script must run as root. Run it with sudo or as the RMM's system account."
PACKAGE_MANAGER=""
if have apt-get; then PACKAGE_MANAGER="apt"; elif have dnf; then PACKAGE_MANAGER="dnf"; fi
[ -n "$PACKAGE_MANAGER" ] || op_fail "Neither apt-get nor dnf was found. This script supports Ubuntu, Debian, RHEL, Rocky, Alma and Fedora."
if [ -n "$exclude_packages" ]; then
    if printf '%s\n' "$exclude_packages" | grep -Eqv '^[A-Za-z0-9][A-Za-z0-9.+:_-]*$'; then
        op_fail "EXCLUDE_PACKAGES has a value that is not a plain package name (letters, digits and . + : _ - only): $(printf '%s' "$exclude_packages" | tr '\n' ' ')"
    fi
fi
mkdir -p "$(dirname "$PM_LOG")" 2>/dev/null && : > "$PM_LOG" || op_fail "Could not write $PM_LOG. Check that /var/log is writable and not full."

op_line "Installing $(printf '%s' "$update_scope" | tr 'A-Z' 'a-z') updates with $PACKAGE_MANAGER."

# Detect
if [ "$PACKAGE_MANAGER" = "apt" ]; then
    op_line "Refreshing the package list (not counted as a change)."
    apt_run update --allow-releaseinfo-change || fail_with_log "apt-get update failed, so the update list cannot be trusted."
fi
pending=$(list_pending)
pending_count=0
if [ -n "$pending" ]; then pending_count=$(printf '%s\n' "$pending" | wc -l | tr -d ' '); fi
if [ "$pending_count" -gt 0 ]; then
    op_line "$pending_count update(s) waiting in scope $update_scope."
fi

# Act
noun="updates"
if [ "$update_scope" = "Security" ]; then noun="security updates"; fi
if [ "$pending_count" -eq 1 ]; then noun="${noun%s}"; fi
installed_text=""
if [ "$pending_count" -gt 0 ]; then
    if [ "$OP_DRY_RUN" -eq 1 ]; then
        while IFS=$'\t' read -r package old_version new_version; do
            op_change "$package" "Update $old_version -> $new_version" true || true
        done <<EOF
$pending
EOF
        installed_text="install $pending_count $noun"
    else
        op_change "$PACKAGE_MANAGER" "Install $pending_count $noun" apply_updates || true
        # One row per package, for the report and the change log.
        shown=0
        while IFS=$'\t' read -r package old_version new_version; do
            op_log "UPDATED  $package  $old_version -> $new_version"
            if [ "$shown" -lt "$MAX_ROWS" ]; then op_row "$package" "Update $old_version -> $new_version" "Done"; fi
            shown=$((shown + 1))
        done <<EOF
$pending
EOF
        if [ "$shown" -gt "$MAX_ROWS" ]; then op_warn "Only the first $MAX_ROWS of $shown packages are listed; the change log has all of them."; fi
        installed_text="Installed $pending_count $noun"

        # Verify: ask the package manager again.
        remaining=$(list_pending)
        remaining_count=0
        if [ -n "$remaining" ]; then remaining_count=$(printf '%s\n' "$remaining" | wc -l | tr -d ' '); fi
        if [ "$remaining_count" -ge "$pending_count" ]; then
            fail_with_log "The package manager reported success but $remaining_count of $pending_count updates are still waiting."
        fi
        if [ "$remaining_count" -gt 0 ]; then
            op_warn "$remaining_count update(s) are still waiting (held back, phased or blocked by a dependency): $(printf '%s\n' "$remaining" | awk -F'\t' '{ print $1 }' | head -10 | tr '\n' ' ')"
        fi
    fi
fi

# Reboot
reboot_text=$(reboot_required)
reboot_answer=""
did_reboot=0
case "$reboot_text" in
    yes)
        reboot_answer="reboot required"
        if [ "$reboot_if_required" -eq 1 ]; then
            signed_in=$(op_signed_in_user)
            if [ -n "$signed_in" ]; then
                op_warn "Not rebooting: $signed_in is signed in at the console. Reboot later or when they are done."
                reboot_answer="reboot required (not done, $signed_in is signed in)"
            elif ! have shutdown; then
                op_warn "Not rebooting: the shutdown command is missing."
            else
                op_change "System" "Reboot in 1 minute" schedule_reboot || true
                did_reboot=1
                reboot_answer="rebooting in 1 minute"
                if [ "$OP_DRY_RUN" -eq 1 ]; then reboot_answer="reboot in 1 minute"; fi
            fi
        fi ;;
    unknown) reboot_answer="reboot status unknown" ;;
esac

# Finish
if [ -z "$installed_text" ] && [ "$did_reboot" -eq 0 ]; then
    answer="Already up to date: no $(if [ "$update_scope" = "Security" ]; then printf "security "; fi)updates waiting"
    if [ -n "$reboot_answer" ]; then answer="$answer; $reboot_answer"; fi
    op_finish OK "$answer"
fi
if [ -n "$installed_text" ]; then answer="$installed_text"; else answer="No updates waiting"; fi
if [ -n "$reboot_answer" ]; then answer="$answer; $reboot_answer"; fi
op_finish CHANGED "$answer"
