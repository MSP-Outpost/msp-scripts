#!/bin/bash
# ---------------------------------------------------------------------------
# SYNOPSIS:    Installs the macOS and app updates Apple offers (all or recommended), without restarting unless you say so.
# DESCRIPTION:
#   THIS SCRIPT CHANGES THINGS. It runs softwareupdate -l to list what Apple
#   offers, picks the updates for UPDATE_SCOPE (Recommended: only those Apple
#   marks recommended; All: everything listed), and installs them by label with
#   softwareupdate -i. A new major macOS version (for example 26 to 27) is
#   never installed unless INCLUDE_MAJOR_UPGRADES is true. It does not restart
#   the Mac unless RESTART is true AND an update needs one AND nobody is signed
#   in at the console (FORCE_RESTART=true restarts even with someone signed in,
#   which loses their unsaved work). Without a restart, an update that needs
#   one is downloaded and staged, and the answer says "restart needed".
#   Apple silicon: installing a macOS update needs a volume owner's
#   credentials unless the Mac has an MDM bootstrap token. Give
#   VOLUME_OWNER_USER and the environment variable VOLUME_OWNER_PASSWORD (a
#   secret field in your RMM; never an argument). If Apple refuses without
#   them the run ends ERROR with that reason.
#   DRY_RUN=true lists what it would install and changes nothing. The list
#   needs internet access to Apple. Parsing relies on softwareupdate's English
#   output. Slow: macOS updates download gigabytes and can take an hour.
# INPUTS:
#   --update-scope S           (env UPDATE_SCOPE)           Recommended (default) or All.
#   --include-major-upgrades B (env INCLUDE_MAJOR_UPGRADES) Also install a new major macOS version. Default false.
#   --restart B                (env RESTART)                Restart after installing if an update needs it. Default false.
#   --force-restart B          (env FORCE_RESTART)          Restart even if someone is signed in. Default false.
#   --timeout-minutes N        (env TIMEOUT_MINUTES)        Give up on the install after N minutes. 5-720, default 90.
#   --volume-owner-user NAME   (env VOLUME_OWNER_USER)      Apple silicon: a volume owner for macOS updates. Default none.
#   (secret)                   (env VOLUME_OWNER_PASSWORD)  That user's password. Environment variable only.
#   --dry-run B                (env DRY_RUN)                List what would be installed, change nothing.
#   --output-format F          (env OUTPUT_FORMAT)          Text (default), Answer, Json or Csv.
#   --export-path FILE         (env EXPORT_PATH)            Also write rows to this .csv or .json file.
#   --result-field NAME        (env RESULT_FIELD)           Also write the answer to this RMM custom field.
# EXAMPLE:
#   sudo ./install-macos-updates.sh --dry-run true
#   sudo ./install-macos-updates.sh --update-scope All --restart true
# NOTES:
#   Name:        Install macOS updates now (all or recommended)
#   Slug:        install-macos-updates
#   Version:     1.0.0
#   Updated:     2026-11-17
#   Type:        Action
#   Category:    19 macOS management
#   Platforms:   macOS 13+
#   RunAs:       System
#   Requires:    bash 3.2, root, internet access to Apple; a volume owner's credentials for macOS updates on Apple silicon without MDM
#   Changes:     Installs Apple software updates; restarts the Mac only when RESTART is true
#   Risk:        Low
#   Reboot:      Restarts
#   Runtime:     5 minutes to over an hour, depending on the updates
#   Answer:      "Installed 2 update(s); restart needed: Safari 18.2; macOS 27.2.1"
#   Fields:      Item, Change, Result
#   Runtime-Lib: 1.0.0
#   Source:      https://mspoutpost.com/scripts/install-macos-updates
#   License:     MIT
#   Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
#   Changelog:
#     1.0.0  2026-11-17  First version.
# ---------------------------------------------------------------------------

# Identity: must match NOTES above (the build checks it).
OP_SLUG="install-macos-updates"
OP_VERSION="1.0.0"
OP_TYPE="Action"
OP_RISK="Low"
OP_FIELDS=(Item Change Result)
OP_INPUTS=(UPDATE_SCOPE INCLUDE_MAJOR_UPGRADES RESTART FORCE_RESTART TIMEOUT_MINUTES VOLUME_OWNER_USER)

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
DEFAULT_UPDATE_SCOPE="Recommended"
DEFAULT_INCLUDE_MAJOR_UPGRADES="false"
DEFAULT_RESTART="false"
DEFAULT_FORCE_RESTART="false"
DEFAULT_TIMEOUT_MINUTES=90
DEFAULT_VOLUME_OWNER_USER=""

# ---- Constants ------------------------------------------------------------
readonly LIST_TIMEOUT_SECONDS=300

# ---- Functions ------------------------------------------------------------
WORK_DIR=""
trap 'rc=$?; if [ -n "$WORK_DIR" ]; then rm -rf "$WORK_DIR"; fi; (exit "$rc"); op__on_exit' EXIT

# run_capture SECONDS OUTFILE COMMAND...  runs the command with its output in OUTFILE; returns its
# exit code, or 124 when the time ran out and it was ended.
run_capture() {
    local secs="$1" out="$2" pid i=0 code
    shift 2
    "$@" > "$out" 2>&1 &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$i" -ge "$secs" ]; then
            pkill -TERM -P "$pid" 2>/dev/null
            kill -TERM "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            return 124
        fi
        sleep 1
        i=$((i + 1))
    done
    wait "$pid"
    code=$?
    return "$code"
}

# Prints "label|title|version|recommended (YES/NO)|restart (yes/no)" for each listed update.
parse_updates() {
    awk '
        function emit() { if (label != "") printf "%s|%s|%s|%s|%s\n", label, title, version, recommended, restart }
        /^\* Label: / { emit(); label = substr($0, 10); sub(/[ \t]+$/, "", label); title = label; version = ""; recommended = "NO"; restart = "no"; next }
        /Title: / {
            line = $0
            if (match(line, /Title: [^,]*/)) title = substr(line, RSTART + 7, RLENGTH - 7)
            if (match(line, /Version: [^,]*/)) version = substr(line, RSTART + 9, RLENGTH - 9)
            if (line ~ /Recommended: YES/) recommended = "YES"
            if (line ~ /Action: restart/) restart = "yes"
        }
        END { emit() }
    ' "$1"
}

# Installs the selected labels (one per line in SELECTED_LABELS). Fails the run with a clear reason.
install_selected() {
    local label out_file code
    out_file="$WORK_DIR/install.txt"
    set --
    while IFS= read -r label; do
        if [ -n "$label" ]; then set -- "$@" "$label"; fi
    done <<OPEOF
$selected_labels
OPEOF
    if [ "$do_restart" -eq 1 ]; then set -- "$@" -R; fi
    if [ -n "$volume_owner_user" ] && [ -n "$volume_owner_password" ]; then
        run_capture $((timeout_minutes * 60)) "$out_file" install_with_owner "$volume_owner_user" "$@"
    else
        run_capture $((timeout_minutes * 60)) "$out_file" softwareupdate -i "$@"
    fi
    code=$?
    if [ "$code" -eq 124 ]; then
        op_fail "softwareupdate did not finish within $timeout_minutes minutes and was stopped. Run it again, or raise TIMEOUT_MINUTES."
    fi
    if [ "$is_arm" -eq 1 ] && [ "$has_os_update" -eq 1 ] &&
       grep -Eiq 'authenticat|credential|volume owner|--user|stdinpass|administrator password|bootstrap token' "$out_file"; then
        op_fail "Apple silicon needs a volume owner's credentials to install macOS updates. Set VOLUME_OWNER_USER and the environment variable VOLUME_OWNER_PASSWORD, or use an MDM with a bootstrap token."
    fi
    if [ "$code" -ne 0 ] || grep -Eiq 'install failed|download failed|^[[:space:]]*error' "$out_file"; then
        op_fail "softwareupdate failed (exit $code): $(grep -Eiv '^[[:space:]]*$' "$out_file" | tail -n 1). Run softwareupdate -l on the Mac to see its state."
    fi
    return 0
}
install_with_owner() {
    local user="$1"
    shift
    printf '%s\n' "$volume_owner_password" | softwareupdate -i "$@" --user "$user" --stdinpass
}

# ---- Main -----------------------------------------------------------------
op_start "$@"

# Validate
op_read_choice update_scope UPDATE_SCOPE "$DEFAULT_UPDATE_SCOPE" Recommended All
op_read_bool include_major INCLUDE_MAJOR_UPGRADES "$DEFAULT_INCLUDE_MAJOR_UPGRADES"
op_read_bool restart_wanted RESTART "$DEFAULT_RESTART"
op_read_bool force_restart FORCE_RESTART "$DEFAULT_FORCE_RESTART"
op_read_int timeout_minutes TIMEOUT_MINUTES "$DEFAULT_TIMEOUT_MINUTES" 5 720
op_read_text volume_owner_user VOLUME_OWNER_USER "$DEFAULT_VOLUME_OWNER_USER"
op_read_secret volume_owner_password VOLUME_OWNER_PASSWORD
if [ "$OP_OS" != "macOS" ]; then op_finish SKIPPED "Skipped: this script is for macOS."; fi
op_is_root || op_fail "This script must run as root. Run it with sudo or from your RMM's system context."
command -v softwareupdate >/dev/null 2>&1 || op_fail "The softwareupdate command is missing. This does not look like macOS."
if [ -n "$volume_owner_user" ] && [ -z "$volume_owner_password" ]; then
    op_fail "VOLUME_OWNER_USER is set but the environment variable VOLUME_OWNER_PASSWORD is not. Set both, or neither."
fi
if [ -n "$volume_owner_user" ] && ! printf '%s' "$volume_owner_user" | grep -Eq '^[A-Za-z0-9._-]+$'; then
    op_fail "Input VOLUME_OWNER_USER is '$volume_owner_user'; expected a short account name (letters, digits, dot, dash, underscore)."
fi
WORK_DIR=$(mktemp -d /private/var/tmp/outpost-updates.XXXXXX) || op_fail "Could not create a temporary folder."
is_arm=0
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]; then is_arm=1; fi
current_major=$(sw_vers -productVersion | cut -d. -f1)

# Detect
op_line "Asking Apple which updates are available (scope: $update_scope). This can take a minute."
run_capture "$LIST_TIMEOUT_SECONDS" "$WORK_DIR/list.txt" softwareupdate -l
list_code=$?
if [ "$list_code" -eq 124 ]; then op_fail "softwareupdate -l did not answer within $LIST_TIMEOUT_SECONDS seconds. Check the Mac's internet access to Apple and run again."; fi
if [ "$list_code" -ne 0 ]; then
    op_fail "softwareupdate -l failed (exit $list_code): $(grep -Eiv '^[[:space:]]*$' "$WORK_DIR/list.txt" | tail -n 1). Check the Mac's internet access to Apple."
fi
parse_updates "$WORK_DIR/list.txt" > "$WORK_DIR/updates.tsv"
selected_labels=""
selected_titles=""
selected_count=0
skipped_major=0
has_os_update=0
needs_restart=0
while IFS='|' read -r label title version recommended restart; do
    [ -z "$label" ] && continue
    if [ "$update_scope" = "Recommended" ] && [ "$recommended" != "YES" ]; then continue; fi
    is_os=0
    case "$title" in macOS*) is_os=1 ;; esac
    if [ "$is_os" -eq 1 ] && [ "$include_major" -eq 0 ]; then
        version_major=$(printf '%s' "$version" | cut -d. -f1)
        case "$version_major" in
            ''|*[!0-9]*) ;;
            *) if [ "$version_major" -gt "$current_major" ]; then skipped_major=$((skipped_major + 1)); continue; fi ;;
        esac
    fi
    selected_labels="${selected_labels}${label}"$'\n'
    selected_titles="${selected_titles}${title}; "
    selected_count=$((selected_count + 1))
    if [ "$is_os" -eq 1 ]; then has_os_update=1; fi
    if [ "$restart" = "yes" ]; then needs_restart=1; fi
done < "$WORK_DIR/updates.tsv"
selected_titles="${selected_titles%; }"

if [ "$selected_count" -eq 0 ]; then
    if [ "$skipped_major" -gt 0 ]; then
        op_finish OK "Already up to date: only a new major macOS version is offered; set INCLUDE_MAJOR_UPGRADES=true to install it."
    fi
    op_finish OK "Already up to date: no $(printf '%s' "$update_scope" | tr 'A-Z' 'a-z') updates are available."
fi
op_line "$selected_count update(s) selected: $selected_titles"
if [ "$skipped_major" -gt 0 ]; then op_warn "$skipped_major new major macOS version(s) left out; set INCLUDE_MAJOR_UPGRADES=true to include."; fi

signed_in=$(op_signed_in_user)
do_restart=0
if [ "$restart_wanted" -eq 1 ] && [ "$needs_restart" -eq 1 ]; then
    if [ -z "$signed_in" ] || [ "$force_restart" -eq 1 ]; then
        do_restart=1
    else
        op_warn "$signed_in is signed in, so the Mac will not restart (set FORCE_RESTART=true to restart anyway)."
    fi
fi
if [ "$is_arm" -eq 1 ] && [ "$has_os_update" -eq 1 ] && [ -z "$volume_owner_user" ]; then
    op_warn "Apple silicon: a macOS update may need a volume owner's credentials (VOLUME_OWNER_USER and VOLUME_OWNER_PASSWORD) unless an MDM bootstrap token is in place."
fi

# Act
item_list=$(printf '%s' "$selected_labels" | sed '/^$/d' | tr '\n' ',' | sed 's/,$//; s/,/, /g')
change_text="Install $selected_count update(s)"
if [ "$do_restart" -eq 1 ]; then change_text="$change_text and restart"; fi
op_change "$item_list" "$change_text" install_selected || true

# Verify
if [ "$OP_DRY_RUN" -eq 0 ] && [ "$do_restart" -eq 0 ]; then
    run_capture "$LIST_TIMEOUT_SECONDS" "$WORK_DIR/after.txt" softwareupdate -l
    parse_updates "$WORK_DIR/after.txt" > "$WORK_DIR/after.tsv"
    still=""
    while IFS= read -r label; do
        [ -z "$label" ] && continue
        restart_flag=$(awk -F'|' -v l="$label" '$1 == l { print $5 }' "$WORK_DIR/updates.tsv")
        if [ "$restart_flag" != "yes" ] && awk -F'|' -v l="$label" '$1 == l { found = 1 } END { exit found ? 0 : 1 }' "$WORK_DIR/after.tsv"; then
            still="${still}${label}, "
        fi
    done <<OPEOF
$selected_labels
OPEOF
    if [ -n "$still" ]; then
        op_fail "Installed, but ${still%, } is still offered by Apple. Run softwareupdate -l on the Mac and check for errors."
    fi
fi

# Finish
answer="Installed $selected_count update(s)"
if [ "$do_restart" -eq 1 ]; then
    answer="$answer; restarting now"
elif [ "$needs_restart" -eq 1 ]; then
    answer="$answer; restart needed"
fi
answer="$answer: $selected_titles"
op_finish CHANGED "$answer"
