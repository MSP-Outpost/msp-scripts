#!/bin/bash
# ---------------------------------------------------------------------------
# SYNOPSIS:    Alerts when an account other than the ones you approve has root rights on a Linux server (sudoers, sudo/wheel/admin groups, extra UID 0).
# DESCRIPTION:
#   THIS SCRIPT IS READ-ONLY. It lists every account that can act as root:
#     - members of the groups sudo, wheel and admin (primary and secondary),
#     - users and groups named in /etc/sudoers and in /etc/sudoers.d (files
#       whose names contain a dot or end in ~ are ignored, as sudo does), with
#       User_Alias names expanded and a rule for ALL counted as everyone,
#     - accounts other than root with UID 0.
#   Each row says how the account gets its rights, whether the rule covers
#   every command (Scope all) or only some (Scope limited), and whether it
#   needs no password (NoPassword, the NOPASSWD tag).
#   It alerts (exit 1) when an account with Scope all is not in
#   ALLOWED_ACCOUNTS. root is always allowed. A rule that only lets someone
#   run a few commands (Scope limited) is listed but never alerts.
#   REQUIRE_PASSWORD=true also alerts on an allowed account that can use sudo without a password.
#   With no ALLOWED_ACCOUNTS, every account except root that has root rights
#   alerts: list your own admins there (the account your RMM or you use).
#   Limits: the sudoers files are read line by line, not run through visudo,
#   so unusual syntax (host-specific rules, command aliases that hide ALL,
#   netgroups) is read as written and may be missed. Accounts that exist only
#   in LDAP or SSSD are included only if getent lists them. A rule set by
#   Defaults or by AuthorizedKeysCommand is not an admin rule and is not read.
#   Tested on Ubuntu 24.04 (Arm64). Debian 12 and RHEL/Rocky/Alma 9 use the
#   same files and groups; they are written for but not yet run.
# INPUTS:
#   --allowed-accounts LIST    (env ALLOWED_ACCOUNTS)    Accounts allowed to have root rights, comma-separated. root is always allowed. Default none.
#   --require-password B       (env REQUIRE_PASSWORD)    true to also alert when an allowed account can use sudo without a password. Default false.
#   --output-format F          (env OUTPUT_FORMAT)       Text (default), Answer, Json or Csv.
#   --export-path FILE         (env EXPORT_PATH)         Also write rows to this .csv or .json file.
#   --result-field NAME        (env RESULT_FIELD)        Also write the answer to this RMM custom field.
#   --dry-run B                (env DRY_RUN)             Reserved; ignored by Monitors.
# EXAMPLE:
#   sudo ./test-linux-privileged-users.sh --allowed-accounts "ops,backup-admin"
#   sudo ALLOWED_ACCOUNTS=ops REQUIRE_PASSWORD=true OUTPUT_FORMAT=Json ./test-linux-privileged-users.sh
# NOTES:
#   Name:        Who has root? Unexpected sudo or UID 0 accounts
#   Slug:        test-linux-privileged-users
#   Version:     1.0.0
#   Updated:     2026-11-17
#   Type:        Monitor
#   Category:    20 Linux management
#   Platforms:   Ubuntu 22.04+, Debian 12+, RHEL/Rocky/Alma 9+
#   RunAs:       System
#   Requires:    bash 3.2, root, getent, awk
#   Changes:     None
#   Risk:        Low
#   Reboot:      Never
#   Runtime:     Under 5 seconds
#   Answer:      "2 account(s) with root rights outside the policy: bob (group sudo, NOPASSWD), toor (uid 0)"
#   Fields:      Account, Via, Source, Scope, NoPassword, Allowed
#   Runtime-Lib: 1.0.0
#   Source:      https://mspoutpost.com/scripts/test-linux-privileged-users
#   License:     MIT
#   Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
#   Changelog:
#     1.0.0  2026-11-17  First version.
# ---------------------------------------------------------------------------

# Identity: must match NOTES above (the build checks it).
OP_SLUG="test-linux-privileged-users"
OP_VERSION="1.0.0"
OP_TYPE="Monitor"
OP_RISK="Low"
OP_FIELDS=(Account Via Source Scope NoPassword Allowed)
OP_INPUTS=(ALLOWED_ACCOUNTS REQUIRE_PASSWORD)

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
DEFAULT_ALLOWED_ACCOUNTS=""
DEFAULT_REQUIRE_PASSWORD="false"

# ---- Constants ------------------------------------------------------------
readonly SUDOERS_FILE="/etc/sudoers"
readonly SUDOERS_DIR="/etc/sudoers.d"
readonly ADMIN_GROUPS="sudo wheel admin"

# ---- Functions ------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

# Prints the sudoers files sudo would read: /etc/sudoers, its include files and
# the files of its include directories (names with a dot or ending in ~ skipped).
sudoers_files() {
    local dir file base
    if [ -f "$SUDOERS_FILE" ]; then printf '%s\n' "$SUDOERS_FILE"; fi
    {
        printf '%s\n' "$SUDOERS_DIR"
        if [ -f "$SUDOERS_FILE" ]; then awk '$1 == "@includedir" || $1 == "#includedir" { print $2 }' "$SUDOERS_FILE"; fi
    } | awk '!seen[$0]++' | while IFS= read -r dir; do
        [ -d "$dir" ] || continue
        for file in "$dir"/*; do
            [ -f "$file" ] || continue
            base=$(basename "$file")
            case "$base" in *.*|*~) continue ;; esac
            printf '%s\n' "$file"
        done
    done
    if [ -f "$SUDOERS_FILE" ]; then
        awk '$1 == "@include" || $1 == "#include" { print $2 }' "$SUDOERS_FILE" | while IFS= read -r file; do
            [ -f "$file" ] && printf '%s\n' "$file"
        done
    fi
}

# Prints "principal<TAB>scope<TAB>nopasswd<TAB>file" for every user specification in the sudoers files.
# principal: a user name, a %group, or ALL. scope: all or limited. nopasswd: yes or no.
parse_sudoers() {
    local files
    files=$(sudoers_files)
    printf '%s\n' "$files" | while IFS= read -r file; do
        [ -r "$file" ] || continue
        # Join lines that end in a backslash, tag each logical line with its file.
        awk -v F="$file" '
            { line = $0
              if (cont != "") { line = cont line; cont = "" }
              if (line ~ /\\$/) { sub(/\\$/, "", line); cont = line; next }
              print F "\t" line }
            END { if (cont != "") print F "\t" cont }' "$file"
    done | awk '
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
        function emit(p, depth,   parts, k, m) {
            if (p == "" || substr(p, 1, 1) == "!" || substr(p, 1, 1) == "+" || substr(p, 1, 1) == "#") return
            if ((p in alias) && depth < 5) {
                m = split(alias[p], parts, ",")
                for (k = 1; k <= m; k++) emit(parts[k], depth + 1)
                return
            }
            print p "\t" sc "\t" np "\t" fl
        }
        BEGIN { FS = "\t"; n = 0 }
        {
            fl = $1
            line = substr($0, length($1) + 2)
            line = trim(line)
            if (line == "" || substr(line, 1, 1) == "#") next
            sub(/[ \t]+#.*$/, "", line)
            line = trim(line)
            word = line; sub(/[ \t].*$/, "", word)
            if (word ~ /^Defaults/ || word == "Cmnd_Alias" || word == "Host_Alias" || word == "Runas_Alias" || word == "@include" || word == "@includedir") next
            if (word == "User_Alias") {
                rest = substr(line, length("User_Alias") + 1)
                cnt = split(rest, defs, ":")
                for (k = 1; k <= cnt; k++) {
                    eq = index(defs[k], "=")
                    if (eq == 0) continue
                    nm = trim(substr(defs[k], 1, eq - 1))
                    mem = substr(defs[k], eq + 1)
                    gsub(/[ \t]*,[ \t]*/, ",", mem)
                    alias[nm] = trim(mem)
                }
                next
            }
            eq = index(line, "=")
            if (eq == 0) next
            left = substr(line, 1, eq - 1)
            right = trim(substr(line, eq + 1))
            gsub(/[ \t]*,[ \t]*/, ",", left)
            left = trim(left)
            users = left; sub(/[ \t].*$/, "", users)
            runas_root = 1
            if (substr(right, 1, 1) == "(") {
                close_at = index(right, ")")
                runas = substr(right, 2, close_at - 2)
                right = trim(substr(right, close_at + 1))
                if (runas !~ /ALL/ && runas !~ /root/) runas_root = 0
                if (runas ~ /!root/) runas_root = 0
            }
            nopass = "no"
            if (right ~ /NOPASSWD:/) nopass = "yes"
            while (match(right, /^[A-Z_]+:[ \t]*/)) right = substr(right, RLENGTH + 1)
            scope = "limited"
            if (runas_root && right ~ /(^|[,:) \t])ALL([ \t]*,|[ \t]*$)/) scope = "all"
            n++; su[n] = users; ss[n] = scope; sn[n] = nopass; sf[n] = fl
        }
        END {
            for (i = 1; i <= n; i++) {
                sc = ss[i]; np = sn[i]; fl = sf[i]
                cnt = split(su[i], list, ",")
                for (k = 1; k <= cnt; k++) emit(list[k], 0)
            }
        }'
}

# Prints the members of a group (secondary members and accounts whose primary group it is), one per line.
group_members() {
    local entry gid
    entry=$(getent group "$1" 2>/dev/null) || return 0
    printf '%s\n' "$entry" | awk -F: '{ n = split($4, m, ","); for (i = 1; i <= n; i++) if (m[i] != "") print m[i] }'
    gid=$(printf '%s' "$entry" | awk -F: '{ print $3 }')
    getent passwd 2>/dev/null | awk -F: -v g="$gid" '$4 == g { print $1 }'
}

# add_grants ACCOUNTS VIA SOURCE SCOPE NOPASSWD   Appends one grant line per account.
add_grants() {
    local account
    while IFS= read -r account; do
        [ -z "$account" ] && continue
        [ "$account" = "root" ] && continue
        GRANTS="${GRANTS}${account}"$'\t'"$2"$'\t'"$3"$'\t'"$4"$'\t'"$5"$'\n'
    done <<EOF
$(printf '%s\n' "$1" | sort -u)
EOF
}

# ---- Main -----------------------------------------------------------------
op_start "$@"
export PATH="${PATH:-/usr/bin:/bin}:/usr/sbin:/sbin:/usr/local/sbin"

# Validate
op_read_list allowed_accounts ALLOWED_ACCOUNTS "$DEFAULT_ALLOWED_ACCOUNTS"
op_read_bool require_password REQUIRE_PASSWORD "$DEFAULT_REQUIRE_PASSWORD"
[ "$OP_OS" = "Linux" ] || op_finish SKIPPED "Skipped: this script is for Linux, this is $OP_OS."
op_is_root || op_fail "This script must run as root, because /etc/sudoers is only readable by root. Run it with sudo or as the RMM's system account."
have getent || op_fail "The getent command is missing. Install libc-bin (Debian, Ubuntu) or glibc-common (RHEL) and run again."

op_line "Listing accounts with root rights (allowed: root${allowed_accounts:+, $(printf '%s' "$allowed_accounts" | tr '\n' ',' | sed 's/,$//; s/,/, /g')})."

# Detect
GRANTS=""

# 1. Members of the admin groups. Later lines for the same account and group (from sudoers) replace these.
for group in $ADMIN_GROUPS; do
    add_grants "$(group_members "$group")" "group $group" "/etc/group" "all" "no"
done

# 2. sudoers rules.
while IFS=$'\t' read -r principal scope nopasswd rule_file; do
    [ -z "$principal" ] && continue
    case "$principal" in
        ALL) add_grants "ALL" "sudoers (everyone)" "$rule_file" "$scope" "$nopasswd" ;;
        %:*|%#*) ;;
        %*) group="${principal#%}"; add_grants "$(group_members "$group")" "group $group" "$rule_file" "$scope" "$nopasswd" ;;
        *) add_grants "$principal" "sudoers" "$rule_file" "$scope" "$nopasswd" ;;
    esac
done <<EOF
$(parse_sudoers)
EOF

# 3. Extra UID 0 accounts.
add_grants "$(getent passwd 2>/dev/null | awk -F: '$3 == 0 && $1 != "root" { print $1 }')" "uid 0" "/etc/passwd" "all" "no"

# One row per account and way in; a later line (sudoers) replaces an earlier one (group membership).
unique_grants=$(printf '%s' "$GRANTS" | awk -F'\t' '
    NF >= 5 { key = $1 "\t" $2; if (!(key in row)) order[++n] = key; row[key] = $0 }
    END { for (i = 1; i <= n; i++) print row[order[i]] }')

violations=""
violating_accounts=""
root_rights=0
while IFS=$'\t' read -r account via grant_source scope nopasswd; do
    [ -z "$account" ] && continue
    allowed="false"
    if printf '%s\n' "$allowed_accounts" | grep -Fxq "$account"; then allowed="true"; fi
    problem=""
    if [ "$scope" = "all" ]; then
        root_rights=$((root_rights + 1))
        if [ "$allowed" = "false" ]; then problem="$via"; fi
        if [ "$allowed" = "true" ] && [ "$require_password" -eq 1 ] && [ "$nopasswd" = "yes" ]; then problem="$via, NOPASSWD"; fi
        if [ "$allowed" = "false" ] && [ "$nopasswd" = "yes" ]; then problem="$via, NOPASSWD"; fi
    fi
    nopasswd_value="false"
    if [ "$nopasswd" = "yes" ]; then nopasswd_value="true"; fi
    op_row "$account" "$via" "$grant_source" "$scope" "$nopasswd_value" "$allowed"
    if [ -n "$problem" ]; then
        violations="${violations}${account} (${problem}), "
        if ! printf '%s\n' "$violating_accounts" | grep -Fxq "$account"; then violating_accounts="${violating_accounts}${account}"$'\n'; fi
    fi
done <<EOF
$unique_grants
EOF

# Finish
if [ -n "$violations" ]; then
    violating_count=$(printf '%s' "$violating_accounts" | sed '/^$/d' | wc -l | tr -d ' ')
    op_finish ALERT "$violating_count account(s) with root rights outside the policy: ${violations%, }"
fi
if [ "$root_rights" -eq 0 ]; then op_finish OK "No account other than root has root rights."; fi
op_finish OK "$root_rights way(s) to root, all for allowed accounts."
