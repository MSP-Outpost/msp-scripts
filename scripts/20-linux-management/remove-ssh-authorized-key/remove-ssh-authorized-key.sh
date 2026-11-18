#!/bin/bash
# ---------------------------------------------------------------------------
# SYNOPSIS:    Removes one SSH public key, by fingerprint or exact comment, from every account's authorized_keys on a Linux server.
# DESCRIPTION:
#   THIS SCRIPT CHANGES THINGS, and a wrong removal can lock people out, so it
#   is High risk: it does nothing but list what it would remove until BOTH
#   DRY_RUN=false AND APPROVE=remove-ssh-authorized-key are set, and it will not
#   remove more keys than MAX_CHANGES (default 25) in one run.
#   It finds keys in the authorized-keys files of every account with a home
#   folder (the locations from the effective sshd AuthorizedKeysFile setting,
#   default .ssh/authorized_keys and .ssh/authorized_keys2). A key matches when
#   it equals KEY_FINGERPRINT (SHA256:...) and/or KEY_COMMENT exactly; when both
#   are given, both must match. There are no wildcards and no partial matches:
#   a comment with * ? [ or fewer than 3 characters is refused. ACCOUNT limits
#   the search to one account; without it the key is removed everywhere.
#   Before any file is edited it is copied to
#   /var/lib/mspoutpost/backups/remove-ssh-authorized-key/<UTC time>/ (the last
#   10 runs are kept). Only the matching key lines are deleted; every other
#   line, the owner and the permissions stay as they were. After the edit each
#   file is read again to prove the key is gone.
#   Protected: when this script runs inside an SSH login (the RMM or you
#   connecting over SSH), it never touches keys in the authorized_keys of the
#   account that SSH login belongs to, because it cannot tell which of that
#   account's keys opened the session and removing it could lock you out. Such
#   matches are skipped with a warning; if they are the only matches the run
#   stops with an error saying so. Run it from your RMM agent (not an SSH
#   session), or from an SSH session of a different account, or remove that key
#   by hand. There is no input to switch this off.
#   Not covered: keys handed out by AuthorizedKeysCommand and SSH certificate
#   authorities; a key that was removed here can still come back from whatever
#   put it there (a provisioning tool, a user).
#   Tested on Ubuntu 24.04 (Arm64). Debian 12 and RHEL/Rocky/Alma 9 use the
#   same files; they are written for but not yet run.
# INPUTS:
#   --key-fingerprint FP     (env KEY_FINGERPRINT)   SHA256 fingerprint of the key to remove (SHA256:abc...). One of KEY_FINGERPRINT or KEY_COMMENT is required.
#   --key-comment TEXT       (env KEY_COMMENT)       Exact comment of the key to remove (the text after the key). At least 3 characters, no wildcards.
#   --account NAME           (env ACCOUNT)           Only look in this account. Default: every account.
#   --dry-run B              (env DRY_RUN)           Default true. Set false, together with APPROVE, to remove.
#   --approve SLUG           (env APPROVE)           Must be remove-ssh-authorized-key to allow changes.
#   --max-changes N          (env MAX_CHANGES)       Most keys one run may remove. Default 25.
#   --output-format F        (env OUTPUT_FORMAT)     Text (default), Answer, Json or Csv.
#   --export-path FILE       (env EXPORT_PATH)       Also write rows to this .csv or .json file.
#   --result-field NAME      (env RESULT_FIELD)      Also write the answer to this RMM custom field.
# EXAMPLE:
#   sudo ./remove-ssh-authorized-key.sh --key-fingerprint SHA256:Qm3xY...
#   sudo ./remove-ssh-authorized-key.sh --key-comment "old-laptop" --dry-run false --approve remove-ssh-authorized-key
# NOTES:
#   Name:        Remove an old SSH key from every account
#   Slug:        remove-ssh-authorized-key
#   Version:     1.0.0
#   Updated:     2026-11-17
#   Type:        Action
#   Category:    20 Linux management
#   Platforms:   Ubuntu 22.04+, Debian 12+, RHEL/Rocky/Alma 9+
#   RunAs:       System
#   Requires:    bash 3.2, root, getent, ssh-keygen (openssh-client)
#   Changes:     Deletes the matching key line from authorized_keys files, after backing each file up
#   Risk:        High
#   Reboot:      Never
#   Runtime:     Under 10 seconds
#   Answer:      "Removed 2 key(s) SHA256:zZH4y0W2... from 2 file(s); backups in /var/lib/mspoutpost/backups/remove-ssh-authorized-key"
#   Fields:      Item, Change, Result
#   Runtime-Lib: 1.0.0
#   Source:      https://mspoutpost.com/scripts/remove-ssh-authorized-key
#   License:     MIT
#   Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
#   Changelog:
#     1.0.0  2026-11-17  First version.
# ---------------------------------------------------------------------------

# Identity: must match NOTES above (the build checks it).
OP_SLUG="remove-ssh-authorized-key"
OP_VERSION="1.0.0"
OP_TYPE="Action"
OP_RISK="High"
OP_FIELDS=(Item Change Result)
OP_INPUTS=(KEY_FINGERPRINT KEY_COMMENT ACCOUNT)

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
DEFAULT_KEY_FINGERPRINT=""
DEFAULT_KEY_COMMENT=""
DEFAULT_ACCOUNT=""

# ---- Constants ------------------------------------------------------------
readonly DEFAULT_KEY_FILES=".ssh/authorized_keys .ssh/authorized_keys2"
readonly BACKUP_ROOT="/var/lib/mspoutpost/backups/remove-ssh-authorized-key"

# ---- Functions ------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

# Prints the AuthorizedKeysFile patterns sshd uses, one per line.
key_file_patterns() {
    local patterns
    patterns=$(sshd -T 2>/dev/null | awk '$1 == "authorizedkeysfile" { for (i = 2; i <= NF; i++) print $i }')
    if [ -z "$patterns" ]; then patterns=$(printf '%s\n' $DEFAULT_KEY_FILES); fi
    printf '%s\n' "$patterns" | grep -v '^none$'
}

# expand_path PATTERN HOME USER UID   Expands %h %u %U %% in an AuthorizedKeysFile pattern.
expand_path() {
    awk -v t="$1" -v h="$2" -v u="$3" -v n="$4" 'BEGIN {
        out = ""; i = 1
        while (i <= length(t)) {
            c = substr(t, i, 1)
            if (c == "%") {
                d = substr(t, i + 1, 1)
                if (d == "h") out = out h
                else if (d == "u") out = out u
                else if (d == "U") out = out n
                else if (d == "%") out = out "%"
                else out = out c d
                i += 2
            } else { out = out c; i++ }
        }
        print out }'
}

# Prints "type<US>blob<US>comment<US>options" for a key line, INVALID for a line that is not a key,
# and nothing for a blank or comment line. US is the ASCII unit separator (octal 037).
parse_key_line() {
    printf '%s\n' "$1" | awk '
        BEGIN { re = "^(ssh-rsa|ssh-dss|ssh-ed25519|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh[.]com|sk-ecdsa-sha2-nistp256@openssh[.]com)$"; us = sprintf("%c", 31) }
        NF == 0 || $1 ~ /^#/ { exit }
        { t = 0
          for (i = 1; i <= NF; i++) if ($i ~ re) { t = i; break }
          if (t == 0 || t == NF) { print "INVALID"; exit }
          opt = ""; for (j = 1; j < t; j++) opt = opt (j > 1 ? " " : "") $j
          cm = ""; for (j = t + 2; j <= NF; j++) cm = cm (j > t + 2 ? " " : "") $j
          print $t us $(t + 1) us cm us opt }'
}

# key_fingerprint TYPE BLOB   Prints "bits<TAB>SHA256:..." (0 and "unknown" when ssh-keygen cannot read it).
key_fingerprint() {
    local tmp out
    tmp=$(mktemp 2>/dev/null) || { printf '0\tunknown'; return; }
    printf '%s %s\n' "$1" "$2" > "$tmp"
    out=$(ssh-keygen -l -E sha256 -f "$tmp" 2>/dev/null | head -1)
    rm -f "$tmp"
    if [ -z "$out" ]; then printf '0\tunknown'; return; fi
    printf '%s\t%s' "$(printf '%s' "$out" | awk '{ print $1 }')" "$(printf '%s' "$out" | awk '{ print $2 }')"
}

# scan_keys HANDLER   Calls HANDLER account file lineno type bits fingerprint comment options for every key found.
scan_keys() {
    local handler="$1" account home uid pattern path file line lineno parsed ktype blob comment options fp_line bits fp
    local seen_files=""
    while IFS=$'\t' read -r account home uid; do
        [ -d "$home" ] || continue
        while IFS= read -r pattern; do
            [ -z "$pattern" ] && continue
            path=$(expand_path "$pattern" "$home" "$account" "$uid")
            case "$path" in /*) file="$path" ;; *) file="$home/$path" ;; esac
            [ -f "$file" ] || continue
            case "$seen_files" in *"|$file|"*) continue ;; esac
            seen_files="${seen_files}|${file}|"
            lineno=0
            while IFS= read -r line || [ -n "$line" ]; do
                lineno=$((lineno + 1))
                parsed=$(parse_key_line "$line")
                if [ -z "$parsed" ] || [ "$parsed" = "INVALID" ]; then continue; fi
                IFS=$'\037' read -r ktype blob comment options <<EOF
$parsed
EOF
                fp_line=$(key_fingerprint "$ktype" "$blob")
                bits="${fp_line%%$'\t'*}"
                fp="${fp_line#*$'\t'}"
                "$handler" "$account" "$file" "$lineno" "$ktype" "$bits" "$fp" "$comment" "$options"
            done < "$file"
        done <<EOF
$(key_file_patterns)
EOF
    done <<EOF
$(getent passwd | awk -F: '$6 != "" { print $1 "\t" $6 "\t" $3 }')
EOF
}

# The account of the SSH login this script runs inside (found by walking up the process tree), or nothing.
session_account() {
    local pid=$$ depth=0 cmd name
    while [ "$pid" -gt 1 ] && [ "$depth" -lt 30 ]; do
        cmd=$(tr '\0' ' ' 2>/dev/null < "/proc/$pid/cmdline" || true)
        case "$cmd" in
            "sshd: "*|"sshd-session: "*)
                name="${cmd#*: }"; name="${name%% *}"; name="${name%%@*}"
                if [ -n "$name" ] && getent passwd "$name" >/dev/null 2>&1; then printf '%s' "$name"; return; fi ;;
        esac
        pid=$(sed 's/^.*) //' "/proc/$pid/stat" 2>/dev/null | awk '{ print $2 }')
        [ -n "$pid" ] || return 0
        depth=$((depth + 1))
    done
}

# Handler: remembers every key that matches the inputs (MATCHES) and every match in the protected account (PROTECTED).
collect_match() {
    if [ -n "$key_account" ] && [ "$1" != "$key_account" ]; then return 0; fi
    if [ -n "$key_fingerprint" ] && [ "$6" != "$key_fingerprint" ]; then return 0; fi
    if [ -n "$key_comment" ] && [ "$7" != "$key_comment" ]; then return 0; fi
    if [ -n "$session_user" ] && [ "$1" = "$session_user" ]; then
        PROTECTED="${PROTECTED}${1}: ${2} line ${3}"$'\n'
        return 0
    fi
    MATCHES="${MATCHES}${1}"$'\t'"${2}"$'\t'"${3}"$'\t'"${6}"$'\t'"${7}"$'\n'
}

# remove_key_line FILE LINENO FINGERPRINT   Deletes that line, after checking it is still the key we found.
remove_key_line() {
    local line parsed ktype blob rest fp new
    line=$(awk -v n="$2" 'NR == n { print; exit }' "$1")
    parsed=$(parse_key_line "$line")
    if [ -z "$parsed" ] || [ "$parsed" = "INVALID" ]; then return 1; fi
    IFS=$'\037' read -r ktype blob rest <<EOF
$parsed
EOF
    fp=$(key_fingerprint "$ktype" "$blob" | cut -f2)
    if [ "$fp" != "$3" ]; then return 1; fi
    new=$(awk -v n="$2" 'NR != n { print }' "$1"; printf x)
    printf '%s' "${new%x}" > "$1"
}

# ---- Main -----------------------------------------------------------------
op_start "$@"
export PATH="${PATH:-/usr/bin:/bin}:/usr/sbin:/sbin:/usr/local/sbin"

# Validate
op_read_text key_fingerprint KEY_FINGERPRINT "$DEFAULT_KEY_FINGERPRINT"
op_read_text key_comment KEY_COMMENT "$DEFAULT_KEY_COMMENT"
op_read_text key_account ACCOUNT "$DEFAULT_ACCOUNT"
key_comment=$(printf '%s' "$key_comment" | awk '{ $1 = $1; print }')
if [ -z "$key_fingerprint" ] && [ -z "$key_comment" ]; then
    op_fail "Neither KEY_FINGERPRINT nor KEY_COMMENT is set. Set --key-fingerprint SHA256:... (from get-ssh-authorized-keys) or --key-comment with the exact comment."
fi
if [ -n "$key_fingerprint" ]; then
    case "$key_fingerprint" in
        SHA256:*) ;;
        *) op_fail "Input KEY_FINGERPRINT is '$key_fingerprint'; expected a SHA256 fingerprint like SHA256:abc... (get-ssh-authorized-keys prints them)." ;;
    esac
    if printf '%s' "$key_fingerprint" | grep -Eqv '^SHA256:[A-Za-z0-9+/]{20,}$'; then
        op_fail "Input KEY_FINGERPRINT is '$key_fingerprint'; expected SHA256: followed by the base64 fingerprint, with no spaces or wildcards."
    fi
fi
if [ -n "$key_comment" ]; then
    case "$key_comment" in
        *[\*\?\[]*) op_fail "Input KEY_COMMENT is '$key_comment'; it must be the exact comment, without the wildcard characters * ? [." ;;
    esac
    if [ "${#key_comment}" -lt 3 ]; then
        op_fail "Input KEY_COMMENT is '$key_comment'; it must be at least 3 characters so it cannot match every key."
    fi
fi
[ "$OP_OS" = "Linux" ] || op_finish SKIPPED "Skipped: this script is for Linux, this is $OP_OS."
op_is_root || op_fail "This script must run as root, to edit every account's authorized_keys. Run it with sudo or as the RMM's system account."
have getent || op_fail "The getent command is missing. Install libc-bin (Debian, Ubuntu) or glibc-common (RHEL) and run again."
have ssh-keygen || op_fail "ssh-keygen is missing. Install openssh-client (Debian, Ubuntu) or openssh-clients (RHEL) and run again."
if [ -n "$key_account" ] && ! getent passwd "$key_account" >/dev/null 2>&1; then
    op_fail "Input ACCOUNT is '$key_account', which is not an account on this machine. Check the name or leave ACCOUNT empty to search every account."
fi

describe="key"
if [ -n "$key_fingerprint" ]; then describe="key $key_fingerprint"; fi
if [ -n "$key_comment" ]; then describe="$describe comment \"$key_comment\""; fi
op_line "Looking for $describe${key_account:+ in account $key_account}."

# Detect
session_user=$(session_account)
MATCHES=""
PROTECTED=""
scan_keys collect_match
match_count=0
if [ -n "$MATCHES" ]; then match_count=$(printf '%s' "$MATCHES" | grep -c '^'); fi
protected_count=0
if [ -n "$PROTECTED" ]; then protected_count=$(printf '%s' "$PROTECTED" | grep -c '^'); fi

if [ "$protected_count" -gt 0 ]; then
    if [ "$match_count" -eq 0 ]; then
        op_fail "Refused: the only match(es) are keys of $session_user, the account this SSH login belongs to ($(printf '%s' "$PROTECTED" | tr '\n' ';')). Removing the key that opened this session could lock you out. Run this from your RMM agent or from a different account's SSH session, or edit that file by hand."
    fi
    op_warn "Skipped $protected_count matching key(s) of $session_user, the account this SSH login belongs to: $(printf '%s' "$PROTECTED" | tr '\n' ';')"
fi
if [ "$match_count" -eq 0 ]; then
    op_finish OK "Already removed: no authorized key matches $describe"
fi

# Act
op_assert_change_limit "$match_count"
if [ "$OP_DRY_RUN" -eq 0 ]; then op_line "$match_count matching key(s) found; backing up each file before editing it."; fi

# Highest line numbers first, so removing one never shifts the next.
sorted_matches=$(printf '%s' "$MATCHES" | sort -t"$(printf '\t')" -k2,2 -k3,3nr)
last_file=""
removed=0
files_changed=""
while IFS=$'\t' read -r account file lineno fingerprint comment; do
    [ -z "$file" ] && continue
    if [ "$file" != "$last_file" ]; then
        op_backup "$file" >/dev/null
        last_file="$file"
        files_changed="${files_changed}${file}"$'\n'
    fi
    if op_change "$account: $file" "Remove key ${fingerprint} (${comment:-no comment}) at line $lineno" remove_key_line "$file" "$lineno" "$fingerprint"; then
        removed=$((removed + 1))
    fi
done <<EOF
$sorted_matches
EOF
file_count=$(printf '%s' "$files_changed" | grep -c '^')

# Verify (a real run only)
if [ "$OP_DRY_RUN" -eq 0 ]; then
    MATCHES=""; PROTECTED=""
    scan_keys collect_match
    if [ -n "$MATCHES" ]; then
        op_fail "The key is still in $(printf '%s' "$MATCHES" | cut -f2 | sort -u | tr '\n' ' ') after removing it. Check the file permissions and attributes (lsattr), then run again."
    fi
fi

# Finish
short_fp="${key_fingerprint:0:16}"
if [ -z "$short_fp" ]; then short_fp="\"$key_comment\""; fi
if [ "$OP_DRY_RUN" -eq 1 ]; then
    op_finish CHANGED "remove $match_count key(s) $short_fp from $file_count file(s)"
fi
op_finish CHANGED "Removed $removed key(s) $short_fp from $file_count file(s); backups in $BACKUP_ROOT"
