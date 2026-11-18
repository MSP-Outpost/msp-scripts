#!/bin/bash
# ---------------------------------------------------------------------------
# SYNOPSIS:    Creates or rotates a hidden managed admin account on a Mac and stores its new random password in a NinjaOne secure field.
# DESCRIPTION:
#   THIS SCRIPT CHANGES THINGS. Risk is High, so it is a dry run unless you set
#   BOTH DRY_RUN=false AND APPROVE=set-mac-local-admin-password. Every real run
#   sets a NEW random password, so running it twice rotates it twice (the
#   second value replaces the first in the field).
#   What it does for ACCOUNT_NAME (default mspadmin):
#     - If the account does not exist, it creates it as a hidden administrator:
#       a user ID below 500 (so it is not shown at the login window or in
#       System Settings), IsHidden set, a private home folder under /var, and
#       membership of the admin group.
#     - If it exists and is hidden, it makes sure it is an administrator and
#       sets a new password.
#     - It REFUSES (nothing changed) when the account exists but is a visible
#       account (user ID 500 or more, not hidden) or is the person signed in at
#       the console: it will not take over somebody's own login.
#   The password is generated here from /dev/urandom (PASSWORD_LENGTH
#   characters, at least one upper case, lower case, digit and symbol). It is
#   handed to dscl on its standard input, never as a command-line argument, and
#   written to the NinjaOne custom field named by RESULT_FIELD through
#   ninjarmm-cli's standard input. It is NEVER printed, logged, exported or put
#   in the answer. Make RESULT_FIELD a secure (secret) field in NinjaOne.
#   Without RESULT_FIELD, with OUTPUT_FORMAT Answer, or where ninjarmm-cli is
#   not found, it ends in ERROR before changing anything: on macOS a secret can
#   only be stored through NinjaOne for now. If the field write fails after the
#   password was changed, the run ends in ERROR and the password is lost: run
#   it again to rotate to a stored one.
#   Before changing group membership it copies the admin group record to
#   /Library/Application Support/MSPOutpost/Backups/set-mac-local-admin-password/.
#   SECURETOKEN AND FILEVAULT: an account made this way has NO SecureToken.
#   macOS gives one only when an existing SecureToken administrator's
#   credentials are supplied, and a root script has none. Such an account can
#   administer the Mac and sign in over SSH or at a text login, but it cannot
#   unlock FileVault at start-up and, on Apple Silicon, cannot authorise some
#   macOS updates or enable FileVault for other users. Grant it a token by hand
#   if you need that: sysadminctl -secureTokenOn <account> -password - -adminUser
#   <token admin> -adminPassword -. Rotating the password of an account that
#   already has a token is fine, but if FileVault is on and this account is a
#   token holder, its FileVault password changes with it.
#   Old password hashes are not backed up. Services that logged in with the old
#   password stop working.
# INPUTS:
#   --account-name NAME      (env ACCOUNT_NAME)      Short name of the managed admin. Letters, digits, . _ -; starts with a letter or underscore. Default mspadmin.
#   --password-length N      (env PASSWORD_LENGTH)   Length of the generated password. 16-64. Default 24.
#   --result-field NAME      (env RESULT_FIELD)      REQUIRED: the NinjaOne secure custom field that receives the password.
#   --dry-run B              (env DRY_RUN)           Default TRUE for this script: lists the changes. Set false AND --approve set-mac-local-admin-password to act.
#   --output-format F        (env OUTPUT_FORMAT)     Text (default), Json or Csv. Answer is refused (this script produces a secret).
#   --export-path FILE       (env EXPORT_PATH)       Also write rows (never the password) to this .csv or .json file.
# EXAMPLE:
#   sudo ./set-mac-local-admin-password.sh --result-field MacAdminPassword
#   sudo ./set-mac-local-admin-password.sh --result-field MacAdminPassword --dry-run=false --approve=set-mac-local-admin-password
# NOTES:
#   Name:        Mac local admin password - create or rotate a hidden admin
#   Slug:        set-mac-local-admin-password
#   Version:     1.0.0
#   Updated:     2026-11-17
#   Type:        Action
#   Category:    19 macOS management
#   Platforms:   macOS 13+
#   RunAs:       System
#   Requires:    bash 3.2, root, dscl, dseditgroup, NinjaOne agent (ninjarmm-cli) with a secure custom field
#   Changes:     Creates a hidden local administrator account if missing, sets a new random password on it, writes the password to a NinjaOne secure field
#   Risk:        High
#   Reboot:      Never
#   Runtime:     Under 10 seconds
#   Answer:      "Rotated password for hidden admin mspadmin; password written to field MacAdminPassword"
#   Fields:      Item, Change, Result
#   Runtime-Lib: 1.0.0
#   Source:      https://mspoutpost.com/scripts/set-mac-local-admin-password
#   License:     MIT
#   Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
#   Changelog:
#     1.0.0  2026-11-17  First version.
# ---------------------------------------------------------------------------

# Identity: must match NOTES above (the build checks it).
OP_SLUG="set-mac-local-admin-password"
OP_VERSION="1.0.0"
OP_TYPE="Action"
OP_RISK="High"
OP_FIELDS=(Item Change Result)
OP_INPUTS=(ACCOUNT_NAME PASSWORD_LENGTH)

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
DEFAULT_ACCOUNT_NAME="mspadmin"
DEFAULT_PASSWORD_LENGTH=24

# ---- Constants ------------------------------------------------------------
readonly ADMIN_GROUP="admin"
readonly ADMIN_GROUP_RECORD="/var/db/dslocal/nodes/Default/groups/admin.plist"
readonly USER_RECORD_DIR="/var/db/dslocal/nodes/Default/users"

# ---- Functions ------------------------------------------------------------
NEW_PASSWORD=""

# Sets NEW_PASSWORD: random, with at least one upper, lower, digit and symbol.
generate_password() {
    local length="$1" candidate="" tries=0
    while [ "$tries" -lt 50 ]; do
        candidate=$(LC_ALL=C tr -dc 'A-Za-z0-9_+=.@%^-' < /dev/urandom 2>/dev/null | head -c "$length") || true
        if [ "${#candidate}" -eq "$length" ]; then
            case "$candidate" in *[A-Z]*) ;; *) candidate="" ;; esac
            case "$candidate" in *[a-z]*) ;; *) candidate="" ;; esac
            case "$candidate" in *[0-9]*) ;; *) candidate="" ;; esac
            case "$candidate" in *[_+=.@%^-]*) ;; *) candidate="" ;; esac
            if [ -n "$candidate" ]; then NEW_PASSWORD="$candidate"; return 0; fi
        fi
        tries=$((tries + 1))
    done
    return 1
}

user_exists() { dscl . -read "/Users/$1" UniqueID > /dev/null 2>&1; }
user_attr() { dscl . -read "/Users/$1" "$2" 2>/dev/null | tail -n 1 | awk '{ print $NF }'; } # "UniqueID: 401" or "dsAttrTypeNative:IsHidden: 1"
is_admin() { dscl . -read "/Groups/$ADMIN_GROUP" GroupMembership 2>/dev/null | tr ' ' '\n' | grep -Fxq "$1"; }
record_hash() { shasum -a 256 "$USER_RECORD_DIR/$1.plist" 2>/dev/null | awk '{ print $1 }'; }

# First free user ID from 401 up (below 500 keeps the account off the login window).
free_uid() {
    local used n
    used=$(dscl . -list /Users UniqueID 2>/dev/null | awk '{ print $2 }')
    n=401
    while [ "$n" -lt 500 ]; do
        if ! grep -Fxq "$n" <<< "$used"; then printf '%s' "$n"; return 0; fi
        n=$((n + 1))
    done
    return 1
}

create_account() { # ACCOUNT -> hidden admin with a private home under /var
    local name="$1" uid home="/var/$1"
    uid=$(free_uid) || op_fail "No free user ID between 401 and 499 for the new hidden account."
    mkdir -p "$home" && chmod 700 "$home" || return 1
    dscl . -create "/Users/$name" || return 1
    dscl . -create "/Users/$name" UserShell /bin/zsh || return 1
    dscl . -create "/Users/$name" RealName "MSP Administrator" || return 1
    dscl . -create "/Users/$name" UniqueID "$uid" || return 1
    dscl . -create "/Users/$name" PrimaryGroupID 20 || return 1
    dscl . -create "/Users/$name" NFSHomeDirectory "$home" || return 1
    dscl . -create "/Users/$name" IsHidden 1 || return 1
    chown "$uid:20" "$home" || return 1
    dseditgroup -o edit -a "$name" -t user "$ADMIN_GROUP" > /dev/null 2>&1 || return 1
    return 0
}
make_hidden_admin() { # existing hidden account: make sure it is hidden and an admin
    dscl . -create "/Users/$1" IsHidden 1 || return 1
    if ! is_admin "$1"; then dseditgroup -o edit -a "$1" -t user "$ADMIN_GROUP" > /dev/null 2>&1 || return 1; fi
    return 0
}
# The password goes to dscl on its standard input (printf is a shell builtin, so it
# never appears in a process list).
set_password() {
    printf 'passwd /Users/%s %s\n' "$1" "$NEW_PASSWORD" | dscl . > /dev/null 2>&1
    return 0
}

# ---- Main -----------------------------------------------------------------
op_start "$@"

# Validate
op_read_text account_name ACCOUNT_NAME "$DEFAULT_ACCOUNT_NAME" required
op_read_int password_length PASSWORD_LENGTH "$DEFAULT_PASSWORD_LENGTH" 16 64
case "$account_name" in
    [A-Za-z_]*) ;;
    *) op_fail "Input ACCOUNT_NAME is '$account_name'; expected a name that starts with a letter or underscore. Set --account-name or the environment variable ACCOUNT_NAME." ;;
esac
case "$account_name" in
    *[!A-Za-z0-9._-]*) op_fail "Input ACCOUNT_NAME is '$account_name'; expected only letters, digits, . _ - . Set --account-name or the environment variable ACCOUNT_NAME." ;;
esac
if [ "${#account_name}" -gt 31 ]; then op_fail "Input ACCOUNT_NAME is '$account_name'; expected at most 31 characters."; fi
op_assert_secret_field
if [ "$OP_OS" != "macOS" ]; then op_finish SKIPPED "Skipped: this script is for macOS."; fi
op_is_root || op_fail "This script must run as root to create or change accounts. Run it with sudo or from your RMM."
command -v dseditgroup > /dev/null 2>&1 || op_fail "dseditgroup is missing, so group membership cannot be changed."

# Detect
op__raw RESULT_FIELD ""; field_name="$OP_RAW"
if user_exists "$account_name"; then
    uid=$(user_attr "$account_name" UniqueID)
    hidden=$(user_attr "$account_name" IsHidden)
    console_user=$(op_signed_in_user)
    if [ -n "$console_user" ] && [ "$(printf '%s' "$console_user" | tr 'A-Z' 'a-z')" = "$(printf '%s' "$account_name" | tr 'A-Z' 'a-z')" ]; then
        op_fail "$account_name is the account signed in at the console. Choose a different ACCOUNT_NAME for the managed admin. Nothing was changed."
    fi
    if [ "$hidden" != "1" ] && [ "${uid:-0}" -ge 500 ] 2>/dev/null; then
        op_fail "$account_name already exists as a visible account (user ID ${uid:-unknown}). This script will not take over a person's account; choose a different ACCOUNT_NAME. Nothing was changed."
    fi
    exists=1
    op_line "Account $account_name exists (hidden); its password will be rotated."
else
    exists=0
    op_line "Account $account_name does not exist; it will be created as a hidden administrator."
fi

# Act
planned=1
if [ "$exists" -eq 0 ]; then planned=2; elif ! is_admin "$account_name" || [ "$(user_attr "$account_name" IsHidden)" != "1" ]; then planned=2; fi
op_assert_change_limit "$planned"
if [ "$OP_DRY_RUN" -eq 0 ]; then
    op_backup "$ADMIN_GROUP_RECORD" > /dev/null
    op_line "Saved the admin group record to $OP_BACKUP_DIR."
    generate_password "$password_length" || op_fail "Could not generate a password from /dev/urandom. Nothing was changed."
fi
before_hash=""
if [ "$exists" -eq 0 ]; then
    op_change "$account_name" "Create hidden admin account" create_account "$account_name" || true
    verb="Created"
else
    before_hash=$(record_hash "$account_name")
    if [ "$planned" -eq 2 ]; then op_change "$account_name" "Hide and make administrator" make_hidden_admin "$account_name" || true; fi
    verb="Rotated password for"
fi
op_change "$account_name" "Set new random password" set_password "$account_name" || true

# Verify
if [ "$OP_DRY_RUN" -eq 0 ]; then
    user_exists "$account_name" || op_fail "The account $account_name does not exist after the change."
    is_admin "$account_name" || op_fail "$account_name is not in the admin group after the change."
    [ "$(user_attr "$account_name" IsHidden)" = "1" ] || op_fail "$account_name is not hidden after the change."
    case "$(dscl . -read "/Users/$account_name" AuthenticationAuthority 2>/dev/null)" in
        *ShadowHash*) ;;
        *) NEW_PASSWORD=""; op_fail "The password was not set on $account_name (no password hash). The account may be managed by a profile." ;;
    esac
    if [ -n "$before_hash" ] && [ "$(record_hash "$account_name")" = "$before_hash" ]; then
        NEW_PASSWORD=""; op_fail "The password of $account_name did not change (its account record is identical). Nothing was stored."
    fi
    op_write_secret_field "$NEW_PASSWORD"
    NEW_PASSWORD=""
fi

# Finish
op_finish CHANGED "${verb} hidden admin ${account_name}; password written to field ${field_name}"
