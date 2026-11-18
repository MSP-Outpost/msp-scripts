#!/bin/bash
# ---------------------------------------------------------------------------
# SYNOPSIS:    Frees disk space on a Linux server: journal, package cache, unused packages and old rotated logs, with before and after numbers.
# DESCRIPTION:
#   THIS SCRIPT CHANGES THINGS. It frees space in five places and measures the
#   free space on / and /var before and after:
#     1. The systemd journal: rotated and vacuumed down to JOURNAL_MAX_MB
#        (journalctl --vacuum-size). Only when it is bigger than that.
#     2. The package download cache (apt-get clean, dnf clean packages).
#     3. Packages nothing needs any more, INCLUDING old kernels, through the
#        package manager's own autoremove (apt-get autoremove --purge,
#        dnf autoremove). The running kernel and the newest ones are kept by
#        the package manager. Packages you installed by hand are never
#        candidates. Switch it off with REMOVE_UNUSED_PACKAGES=false.
#     4. Rotated logs under /var/log: files that logrotate already finished
#        with (names ending .gz .xz .bz2 .zst .old .1 .2 ... or a date such
#        as -20260301) and that have not been modified for LOG_AGE_DAYS days.
#     5. Docker, only when DOCKER_PRUNE is true: dangling images and the build
#        cache. Containers, volumes and images in use are never touched.
#   It NEVER deletes a live log (the file a program is writing to), anything
#   in /var/log/journal or /var/log/mspoutpost, home folders, or user data.
#   A live log over 1 GB is reported as a WARNING (fix its logrotate rule);
#   this script leaves it alone.
#   Each of the five is skipped, and says so, when there is nothing to do.
#   Tested on Ubuntu 24.04 (Arm64), apt only. The dnf path, Debian 12 and
#   RHEL/Rocky/Alma 9 are written for but not yet run; the Docker path is not
#   yet run.
# INPUTS:
#   --log-age-days N            (env LOG_AGE_DAYS)             Delete rotated logs not modified for this many days. 1-3650. Default 30.
#   --journal-max-mb N          (env JOURNAL_MAX_MB)           Vacuum the journal down to this size. 10-1000000, or 0 to leave it alone. Default 500.
#   --clean-package-cache B     (env CLEAN_PACKAGE_CACHE)      true to clear the downloaded package files. Default true.
#   --remove-unused-packages B  (env REMOVE_UNUSED_PACKAGES)   true to autoremove unused packages and old kernels. Default true.
#   --docker-prune B            (env DOCKER_PRUNE)             true to prune dangling Docker images and build cache. Default false.
#   --dry-run B                 (env DRY_RUN)                  true lists what it would clear and clears nothing. Default false.
#   --output-format F           (env OUTPUT_FORMAT)            Text (default), Answer, Json or Csv.
#   --export-path FILE          (env EXPORT_PATH)              Also write rows to this .csv or .json file.
#   --result-field NAME         (env RESULT_FIELD)             Also write the answer to this RMM custom field.
# EXAMPLE:
#   sudo ./clear-linux-disk-space.sh --dry-run true
#   sudo LOG_AGE_DAYS=14 JOURNAL_MAX_MB=200 DOCKER_PRUNE=true ./clear-linux-disk-space.sh
# NOTES:
#   Name:        Linux disk full: clear logs, journal and caches
#   Slug:        clear-linux-disk-space
#   Version:     1.0.0
#   Updated:     2026-11-17
#   Type:        Action
#   Category:    20 Linux management
#   Platforms:   Ubuntu 22.04+, Debian 12+, RHEL/Rocky/Alma 9+
#   RunAs:       System
#   Requires:    bash 3.2, root, GNU find, df; journalctl, apt-get or dnf, docker when used
#   Changes:     Vacuums the journal, clears the package cache, autoremoves unused packages and old kernels, deletes old rotated logs, optionally prunes dangling Docker images and build cache
#   Risk:        Low
#   Reboot:      Never
#   Runtime:     Under 2 minutes
#   Answer:      "Freed 410 MB (journal 120 MB, package cache 80 MB, 4 unused packages, 14 old logs 210 MB); / 61% free"
#   Fields:      Item, Change, Result
#   Runtime-Lib: 1.0.0
#   Source:      https://mspoutpost.com/scripts/clear-linux-disk-space
#   License:     MIT
#   Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
#   Changelog:
#     1.0.0  2026-11-17  First version.
# ---------------------------------------------------------------------------

# Identity: must match NOTES above (the build checks it).
OP_SLUG="clear-linux-disk-space"
OP_VERSION="1.0.0"
OP_TYPE="Action"
OP_RISK="Low"
OP_FIELDS=(Item Change Result)
OP_INPUTS=(LOG_AGE_DAYS JOURNAL_MAX_MB CLEAN_PACKAGE_CACHE REMOVE_UNUSED_PACKAGES DOCKER_PRUNE)

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
DEFAULT_LOG_AGE_DAYS=30
DEFAULT_JOURNAL_MAX_MB=500
DEFAULT_CLEAN_PACKAGE_CACHE="true"
DEFAULT_REMOVE_UNUSED_PACKAGES="true"
DEFAULT_DOCKER_PRUNE="false"

# ---- Constants ------------------------------------------------------------
readonly PM_LOG="/var/log/mspoutpost/clear-linux-disk-space.pm.log"
readonly APT_CACHE="/var/cache/apt/archives"
readonly LARGE_LOG_KB=1048576

# ---- Functions ------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

# Free KB on / and /var, each device counted once.
free_kb() {
    df -kP / /var 2>/dev/null | awk 'NR > 1 && !seen[$1]++ { total += $4 } END { print total + 0 }'
}

# "410 MB" from a number of KB.
human_kb() {
    awk -v k="$1" 'BEGIN { if (k >= 1048576) printf "%.1f GB", k / 1048576; else if (k >= 1024) printf "%d MB", k / 1024; else printf "%d KB", k }'
}

# Journal size in bytes (0 when unknown).
journal_bytes() {
    journalctl --disk-usage 2>/dev/null | awk '{
        for (i = 2; i <= NF; i++) if ($(i - 1) == "up" && $i ~ /^[0-9.]+[BKMGT]?$/) {
            n = $i; u = "B"
            if (n ~ /[BKMGT]$/) { u = substr(n, length(n)); n = substr(n, 1, length(n) - 1) }
            m = 1
            if (u == "K") m = 1024; if (u == "M") m = 1048576; if (u == "G") m = 1073741824; if (u == "T") m = 1099511627776
            printf "%d", n * m; found = 1; exit
        }
    } END { if (!found) printf "0" }'
}

# Rotated logs: prints with -printf, or deletes with -delete (pass the action as arguments).
find_rotated_logs() {
    find /var/log -xdev -type f -mtime "+$log_age_days" \
        -not -path '/var/log/journal/*' -not -path '/var/log/mspoutpost/*' \
        \( -name '*.gz' -o -name '*.xz' -o -name '*.bz2' -o -name '*.zst' -o -name '*.old' \
           -o -name '*.[0-9]' -o -name '*.[0-9][0-9]' -o -name '*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' \) \
        "$@"
}

# apt_run ARGS...  Runs apt-get without questions; waits out a package lock held by another process.
apt_run() {
    local attempt=1 rc
    while :; do
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
            apt-get -y -o DPkg::Lock::Timeout=300 "$@" >> "$PM_LOG" 2>&1
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

# Prints the names of packages the package manager would autoremove, one per line.
list_unused_packages() {
    case "$PACKAGE_MANAGER" in
        apt) apt-get -s -o Debug::NoLocking=1 autoremove --purge 2>/dev/null | awk '/^(Remv|Purg) / && !seen[$2]++ { print $2 }' ;;
        dnf) dnf -q repoquery --unneeded --qf '%{name}' 2>/dev/null | sed '/^$/d' | sort -u ;;
    esac
}

# Prints "count<TAB>bytes" of downloaded package files.
package_cache_size() {
    case "$PACKAGE_MANAGER" in
        apt) find "$APT_CACHE" -maxdepth 1 -type f -name '*.deb' -printf '%s\n' 2>/dev/null | awk '{ n++; b += $1 } END { printf "%d\t%d", n + 0, b + 0 }' ;;
        dnf) find /var/cache/dnf /var/cache/yum -type f -name '*.rpm' -printf '%s\n' 2>/dev/null | awk '{ n++; b += $1 } END { printf "%d\t%d", n + 0, b + 0 }' ;;
        *) printf '0\t0' ;;
    esac
}

do_journal() { journalctl --rotate --vacuum-size="${journal_max_mb}M" >> "$PM_LOG" 2>&1; }
do_package_cache() {
    case "$PACKAGE_MANAGER" in
        apt) apt_run clean ;;
        dnf) dnf -y clean packages >> "$PM_LOG" 2>&1 ;;
    esac
}
do_autoremove() {
    case "$PACKAGE_MANAGER" in
        apt) apt_run autoremove --purge ;;
        dnf) dnf -y autoremove >> "$PM_LOG" 2>&1 ;;
    esac
}
do_rotated_logs() { find_rotated_logs -delete; }
do_docker() { docker image prune -f >> "$PM_LOG" 2>&1 && docker builder prune -f >> "$PM_LOG" 2>&1; }

# ---- Main -----------------------------------------------------------------
op_start "$@"
export PATH="${PATH:-/usr/bin:/bin}:/usr/sbin:/sbin:/usr/local/sbin"

# Validate
op_read_int log_age_days LOG_AGE_DAYS "$DEFAULT_LOG_AGE_DAYS" 1 3650
op_read_int journal_max_mb JOURNAL_MAX_MB "$DEFAULT_JOURNAL_MAX_MB" 0 1000000
if [ "$journal_max_mb" -gt 0 ] && [ "$journal_max_mb" -lt 10 ]; then
    op_fail "Input JOURNAL_MAX_MB is '$journal_max_mb'; expected 0 (leave the journal alone) or 10 to 1000000. Set --journal-max-mb or the environment variable JOURNAL_MAX_MB."
fi
op_read_bool clean_package_cache CLEAN_PACKAGE_CACHE "$DEFAULT_CLEAN_PACKAGE_CACHE"
op_read_bool remove_unused_packages REMOVE_UNUSED_PACKAGES "$DEFAULT_REMOVE_UNUSED_PACKAGES"
op_read_bool docker_prune DOCKER_PRUNE "$DEFAULT_DOCKER_PRUNE"
[ "$OP_OS" = "Linux" ] || op_finish SKIPPED "Skipped: this script is for Linux, this is $OP_OS."
op_is_root || op_fail "This script must run as root. Run it with sudo or as the RMM's system account."
have find || op_fail "The find command is missing. Install findutils and run again."
PACKAGE_MANAGER="none"
if have apt-get; then PACKAGE_MANAGER="apt"; elif have dnf; then PACKAGE_MANAGER="dnf"; fi
mkdir -p "$(dirname "$PM_LOG")" 2>/dev/null && : > "$PM_LOG" || op_fail "Could not write $PM_LOG. Check that /var/log is writable."

op_line "Clearing rotated logs older than $log_age_days days, the journal above ${journal_max_mb} MB, package cache and unused packages."

# Detect
free_before_kb=$(free_kb)
plan_journal=0; plan_cache=0; plan_packages=0; plan_logs=0; plan_docker=0
estimate_kb=0

if [ "$journal_max_mb" -gt 0 ] && have journalctl && [ -d /run/systemd/system ]; then
    journal_before_bytes=$(journal_bytes)
    journal_limit_bytes=$(( journal_max_mb * 1048576 ))
    if [ "$journal_before_bytes" -gt "$journal_limit_bytes" ]; then
        plan_journal=1
        estimate_kb=$(( estimate_kb + (journal_before_bytes - journal_limit_bytes) / 1024 ))
    fi
fi

if [ "$clean_package_cache" -eq 1 ] && [ "$PACKAGE_MANAGER" != "none" ]; then
    IFS=$'\t' read -r cache_files cache_bytes <<EOF
$(package_cache_size)
EOF
    if [ "${cache_files:-0}" -gt 0 ]; then
        plan_cache=1
        estimate_kb=$(( estimate_kb + cache_bytes / 1024 ))
    fi
fi

unused=""
unused_count=0
if [ "$remove_unused_packages" -eq 1 ] && [ "$PACKAGE_MANAGER" != "none" ]; then
    unused=$(list_unused_packages)
    if [ -n "$unused" ]; then unused_count=$(printf '%s\n' "$unused" | wc -l | tr -d ' '); plan_packages=1; fi
fi

IFS=' ' read -r log_files log_bytes <<EOF
$(find_rotated_logs -printf '%s\n' 2>/dev/null | awk '{ n++; b += $1 } END { print n + 0, b + 0 }')
EOF
if [ "${log_files:-0}" -gt 0 ]; then
    plan_logs=1
    estimate_kb=$(( estimate_kb + log_bytes / 1024 ))
fi

if [ "$docker_prune" -eq 1 ]; then
    if have docker && docker info >/dev/null 2>&1; then
        dangling=$(docker images -f dangling=true -q 2>/dev/null | wc -l | tr -d ' ')
        build_cache=$(docker system df --format '{{.Type}}|{{.Reclaimable}}' 2>/dev/null | awk -F'|' '$1 == "Build Cache" { print $2 }')
        case "$build_cache" in ''|0B*) build_cache_present=0 ;; *) build_cache_present=1 ;; esac
        if [ "${dangling:-0}" -gt 0 ] || [ "$build_cache_present" -eq 1 ]; then plan_docker=1; fi
    else
        op_warn "DOCKER_PRUNE is true but Docker is not installed or not running; skipped."
    fi
fi

# Live logs that are huge: report, never touch.
while IFS=' ' read -r large_kb large_path; do
    [ -z "$large_path" ] && continue
    op_warn "Large live log left alone: $large_path is $(human_kb "$large_kb"). Check its logrotate rule."
done <<EOF
$(find /var/log -xdev -type f -size "+${LARGE_LOG_KB}k" -not -path '/var/log/journal/*' -printf '%k %p\n' 2>/dev/null | head -5)
EOF

plan_total=$(( plan_journal + plan_cache + plan_packages + plan_logs + plan_docker ))
if [ "$plan_total" -eq 0 ]; then
    free_percent=$(df -kP / | awk 'NR == 2 { gsub(/%/, "", $5); print 100 - $5 }')
    op_finish OK "Already clean: nothing to clear (journal within ${journal_max_mb} MB, no old rotated logs, no package cache or unused packages); / ${free_percent}% free"
fi

# Act
summary=""
if [ "$plan_cache" -eq 1 ]; then
    op_change "Package cache" "Delete $cache_files downloaded package file(s) ($(human_kb $(( cache_bytes / 1024 ))))" do_package_cache || true
    summary="${summary}package cache $(human_kb $(( cache_bytes / 1024 ))), "
fi
if [ "$plan_logs" -eq 1 ]; then
    op_change "/var/log" "Delete $log_files rotated log file(s) older than $log_age_days days ($(human_kb $(( log_bytes / 1024 ))))" do_rotated_logs || true
    summary="${summary}${log_files} old log(s) $(human_kb $(( log_bytes / 1024 ))), "
fi
if [ "$plan_journal" -eq 1 ]; then
    op_change "systemd journal" "Vacuum from $(human_kb $(( journal_before_bytes / 1024 ))) to ${journal_max_mb} MB" do_journal || true
    summary="${summary}journal, "
fi
if [ "$plan_packages" -eq 1 ]; then
    op_change "Unused packages" "Autoremove $unused_count package(s): $(printf '%s' "$unused" | head -8 | tr '\n' ' ')" do_autoremove || true
    summary="${summary}${unused_count} unused package(s), "
fi
if [ "$plan_docker" -eq 1 ]; then
    op_change "Docker" "Prune dangling images and build cache" do_docker || true
    summary="${summary}docker, "
fi
summary="${summary%, }"

# Verify (a real run only)
if [ "$OP_DRY_RUN" -eq 0 ]; then
    if [ "$plan_logs" -eq 1 ]; then
        left=$(find_rotated_logs -printf '.' 2>/dev/null | wc -c | tr -d ' ')
        if [ "$left" -gt 0 ]; then op_fail "$left rotated log file(s) are still there after deleting them. Check the permissions or an immutable flag under /var/log."; fi
    fi
    if [ "$plan_cache" -eq 1 ]; then
        IFS=$'\t' read -r cache_left _ <<EOF
$(package_cache_size)
EOF
        if [ "${cache_left:-0}" -gt 0 ]; then op_fail "$cache_left package file(s) are still in the cache after cleaning it. See $PM_LOG."; fi
    fi
    if [ "$plan_packages" -eq 1 ]; then
        unused_left=$(list_unused_packages | wc -l | tr -d ' ')
        if [ "$unused_left" -gt 0 ]; then op_warn "$unused_left package(s) are still marked unused after autoremove (the package manager kept them, for example the running kernel)."; fi
    fi
    if [ "$plan_journal" -eq 1 ]; then
        journal_after_bytes=$(journal_bytes)
        if [ "$journal_after_bytes" -gt "$journal_limit_bytes" ]; then
            op_warn "The journal is still $(human_kb $(( journal_after_bytes / 1024 ))): the active file cannot be vacuumed. Lower the journal's own SystemMaxUse in /etc/systemd/journald.conf."
        fi
    fi
fi

# Finish
free_after_kb=$(free_kb)
free_percent=$(df -kP / | awk 'NR == 2 { gsub(/%/, "", $5); print 100 - $5 }')
if [ "$OP_DRY_RUN" -eq 1 ]; then
    op_finish CHANGED "clear about $(human_kb "$estimate_kb") ($summary); / ${free_percent}% free now"
fi
freed_kb=$(( free_after_kb - free_before_kb ))
if [ "$freed_kb" -lt 0 ]; then freed_kb=0; fi
op_finish CHANGED "Freed $(human_kb "$freed_kb") ($summary); / ${free_percent}% free"
