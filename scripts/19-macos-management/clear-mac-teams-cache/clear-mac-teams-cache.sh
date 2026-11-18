#!/bin/bash
# ---------------------------------------------------------------------------
# SYNOPSIS:    Clears the Microsoft Teams cache (new and classic) for every Mac user, or one.
# DESCRIPTION:
#   THIS SCRIPT CHANGES THINGS. For each user (UID 500 or higher with a home
#   under /Users; or only TARGET_USER) it empties the Teams cache folders:
#   new Teams (com.microsoft.teams2): Containers/.../Library/Caches, the group
#   container's Caches, Library/Caches/com.microsoft.teams2*, and the Cache,
#   Code Cache and GPUCache folders of its web profile; classic Teams:
#   Library/Caches/com.microsoft.teams*, and under Application Support/
#   Microsoft/Teams the Cache, Code Cache, GPUCache, blob_storage, tmp, Application
#   Cache and Service Worker cache folders. It empties the folders but keeps
#   the folders themselves, and never touches settings, sign-in data, local
#   storage or chats. Teams must not be running for that user: if it is, that
#   user is skipped (SKIPPED when nobody could be cleared) unless QUIT_TEAMS is
#   true, which asks Teams to quit and then ends its processes. Cache is rebuilt
#   by Teams, so its next start is slower.
# INPUTS:
#   --target-user NAME     (env TARGET_USER)   Only this user. Default every user.
#   --quit-teams BOOL      (env QUIT_TEAMS)    Quit Teams first if it is running. Default false.
#   --dry-run BOOL         (env DRY_RUN)       List the folders it would empty, change nothing. Default false.
#   --output-format F      (env OUTPUT_FORMAT) Text (default), Answer, Json or Csv.
#   --export-path FILE     (env EXPORT_PATH)   Also write rows to this .csv or .json file.
#   --result-field NAME    (env RESULT_FIELD)  Also write the answer to this RMM custom field.
# EXAMPLE:
#   sudo ./clear-mac-teams-cache.sh
#   sudo ./clear-mac-teams-cache.sh --target-user jsmith --quit-teams true
# NOTES:
#   Name:        Teams won't load on a Mac - clear the Teams cache
#   Slug:        clear-mac-teams-cache
#   Version:     1.0.0
#   Updated:     2026-11-17
#   Type:        Action
#   Category:    19 macOS management
#   Platforms:   macOS 13+
#   RunAs:       System
#   Requires:    bash 3.2, root; Full Disk Access for the RMM agent to clear app container folders
#   Changes:     Deletes the contents of the Microsoft Teams cache folders in each user's Library
#   Risk:        Low
#   Reboot:      Never
#   Runtime:     Under 30 seconds
#   Answer:      "Cleared the Teams cache for 2 user(s): 5 folder(s), 612 MB freed"
#   Fields:      Item, Change, Result
#   Runtime-Lib: 1.0.0
#   Source:      https://mspoutpost.com/scripts/clear-mac-teams-cache
#   License:     MIT
#   Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
#   Changelog:
#     1.0.0  2026-11-17  First version.
# ---------------------------------------------------------------------------

# Identity: must match NOTES above (the build checks it).
OP_SLUG="clear-mac-teams-cache"
OP_VERSION="1.0.0"
OP_TYPE="Action"
OP_RISK="Low"
OP_FIELDS=(Item Change Result)
OP_INPUTS=(TARGET_USER QUIT_TEAMS)

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
DEFAULT_TARGET_USER=""
DEFAULT_QUIT_TEAMS="false"

# ---- Constants ------------------------------------------------------------
readonly TEAMS_BUNDLE_IDS="com.microsoft.teams2 com.microsoft.teams"

# ---- Functions ------------------------------------------------------------
# Prints "name<TAB>uid<TAB>home" for each person account (UID 500+, home under /Users).
list_users() {
    local name uid home
    dscl . -list /Users UniqueID 2>/dev/null | while read -r name uid; do
        case "$uid" in ''|*[!0-9]*) continue ;; esac
        [ "$uid" -ge 500 ] || continue
        home=$(dscl . -read "/Users/$name" NFSHomeDirectory 2>/dev/null | sed -n 's/^NFSHomeDirectory: //p')
        case "$home" in /Users/?*) ;; *) continue ;; esac
        [ -d "$home" ] || continue
        if [ -n "$target_user" ] && [ "$name" != "$target_user" ]; then continue; fi
        printf '%s\t%s\t%s\n' "$name" "$uid" "$home"
    done
}

# Prints the process IDs of Teams (new or classic, any helper) owned by a user ID.
teams_pids() {
    ps -axo pid=,uid=,command= 2>/dev/null | U="$1" awk '
        $2 == ENVIRON["U"] && $0 ~ /(Microsoft Teams[^\/]*\.app|MSTeams\.app)\/Contents\// { print $1 }'
}

# run_limited SECONDS COMMAND...  runs a command, ends it after the time, never fails.
run_limited() {
    local secs="$1" pid i=0
    shift
    "$@" >/dev/null 2>&1 &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$i" -ge "$secs" ]; then kill "$pid" 2>/dev/null; break; fi
        sleep 1
        i=$((i + 1))
    done
    wait "$pid" 2>/dev/null
    return 0
}

# Asks Teams to quit (when macOS knows it as a running app), then ends what is left.
quit_teams() {
    local name="$1" uid="$2" id i=0 console
    [ -n "$(teams_pids "$uid")" ] || return 0
    console=$(op_signed_in_user)
    if [ "$console" = "$name" ]; then
        for id in $TEAMS_BUNDLE_IDS; do
            if [ -n "$(launchctl asuser "$uid" /usr/bin/lsappinfo find "bundleid=$id" 2>/dev/null)" ]; then
                run_limited 12 launchctl asuser "$uid" sudo -u "$name" /usr/bin/osascript -e "tell application id \"$id\" to quit"
            fi
        done
    fi
    while [ "$i" -lt 10 ] && [ -n "$(teams_pids "$uid")" ]; do sleep 1; i=$((i + 1)); done
    if [ -n "$(teams_pids "$uid")" ]; then
        # shellcheck disable=SC2046
        kill -TERM $(teams_pids "$uid") 2>/dev/null
        i=0
        while [ "$i" -lt 10 ] && [ -n "$(teams_pids "$uid")" ]; do sleep 1; i=$((i + 1)); done
    fi
    [ -z "$(teams_pids "$uid")" ]
}

# Prints each Teams cache folder that exists under a home folder.
cache_folders() {
    local home="$1" lib sub web profile
    lib="$home/Library"
    for sub in \
        "Containers/com.microsoft.teams2/Data/Library/Caches" \
        "Group Containers/UBF8T346G9.com.microsoft.teams/Library/Caches" \
        "Caches/com.microsoft.teams2" "Caches/com.microsoft.teams2.helper" \
        "Caches/com.microsoft.teams" "Caches/com.microsoft.teams.helper" \
        "Application Support/Microsoft/Teams/Cache" "Application Support/Microsoft/Teams/Code Cache" \
        "Application Support/Microsoft/Teams/GPUCache" "Application Support/Microsoft/Teams/blob_storage" \
        "Application Support/Microsoft/Teams/tmp" "Application Support/Microsoft/Teams/Application Cache" \
        "Application Support/Microsoft/Teams/Service Worker/CacheStorage" \
        "Application Support/Microsoft/Teams/Service Worker/ScriptCache"; do
        if [ -d "$lib/$sub" ]; then printf '%s\n' "$lib/$sub"; fi
    done
    web="$lib/Containers/com.microsoft.teams2/Data/Library/Application Support/Microsoft/MSTeams/EBWebView"
    if [ -d "$web" ]; then
        for profile in "$web"/*/; do
            [ -d "$profile" ] || continue
            for sub in "Cache" "Code Cache" "GPUCache"; do
                if [ -d "${profile%/}/$sub" ]; then printf '%s\n' "${profile%/}/$sub"; fi
            done
        done
    fi
}

# Empties a folder (keeps the folder). Only paths inside a user's Library that name Teams.
empty_folder() {
    case "$1" in /Users/?*/Library/*[Tt]eams*) ;; *) return 1 ;; esac
    case "$1" in */../*|*/..) return 1 ;; esac
    [ -d "$1" ] || return 0
    if ! find "$1" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null; then
        op_warn "macOS refused to empty $1 (grant Full Disk Access to the RMM agent)."
    fi
    return 0
}

# ---- Main -----------------------------------------------------------------
op_start "$@"

# Validate
op_read_text target_user TARGET_USER "$DEFAULT_TARGET_USER"
op_read_bool quit_allowed QUIT_TEAMS "$DEFAULT_QUIT_TEAMS"
if [ "$OP_OS" != "macOS" ]; then op_finish SKIPPED "Skipped: this script is for macOS."; fi
op_is_root || op_fail "This script must run as root. Run it with sudo or from your RMM's system context."
users=$(list_users)
if [ -z "$users" ]; then
    if [ -n "$target_user" ]; then
        op_fail "Input TARGET_USER is '$target_user'; expected the short name of an existing user account (UID 500 or higher)."
    fi
    op_finish SKIPPED "Skipped: no user accounts with a home folder under /Users."
fi

# Detect
op_line "Looking for Teams cache folders for $(printf '%s\n' "$users" | wc -l | tr -d ' ') user(s)."
plan=""
skipped_users=""
user_total=0
cleared_users=0
total_kb=0
folder_total=0
while IFS=$'\t' read -r name uid home; do
    [ -z "$name" ] && continue
    user_total=$((user_total + 1))
    running=0
    if [ -n "$(teams_pids "$uid")" ]; then running=1; fi
    user_plan=""
    user_kb=0
    while IFS= read -r folder; do
        [ -z "$folder" ] && continue
        if [ -n "$(ls -A "$folder" 2>/dev/null | head -n 1)" ]; then
            kb=$(du -sk "$folder" 2>/dev/null | awk '{ print $1 }')
            user_plan="${user_plan}2folder"$'\t'"$folder"$'\t'"$name"$'\t'"$uid"$'\n'
            user_kb=$((user_kb + ${kb:-0}))
            folder_total=$((folder_total + 1))
        fi
    done <<OPEOF
$(cache_folders "$home")
OPEOF
    [ -z "$user_plan" ] && continue
    if [ "$running" -eq 1 ] && [ "$quit_allowed" -eq 0 ]; then
        skipped_users="${skipped_users}${name}, "
        folder_total=$((folder_total - $(printf '%s' "$user_plan" | wc -l | tr -d ' ')))
        continue
    fi
    if [ "$running" -eq 1 ]; then plan="${plan}1quit"$'\t'"Teams for $name"$'\t'"$name"$'\t'"$uid"$'\n'; fi
    plan="${plan}${user_plan}"
    total_kb=$((total_kb + user_kb))
    cleared_users=$((cleared_users + 1))
done <<OPEOF
$users
OPEOF
skipped_users="${skipped_users%, }"
if [ -n "$skipped_users" ]; then op_warn "Teams is running for: $skipped_users. Their cache was not touched (set QUIT_TEAMS=true to quit Teams first)."; fi

if [ -z "$plan" ]; then
    if [ -n "$skipped_users" ]; then op_finish SKIPPED "Skipped: Teams is running for $skipped_users; set QUIT_TEAMS=true to quit it first."; fi
    op_finish OK "Already clear: no Teams cache found for $user_total user(s)."
fi

# Act
while IFS=$'\t' read -r kind item name uid; do
    [ -z "$kind" ] && continue
    case "$kind" in
        1quit)   op_change "$item" "Quit Teams" quit_teams "$name" "$uid" || true ;;
        2folder) op_change "$item" "Empty the cache folder" empty_folder "$item" || true ;;
    esac
done <<OPEOF
$plan
OPEOF

# Verify
if [ "$OP_DRY_RUN" -eq 0 ]; then
    left=0
    while IFS=$'\t' read -r kind item name uid; do
        [ "$kind" = "2folder" ] || continue
        if [ -n "$(ls -A "$item" 2>/dev/null | head -n 1)" ]; then left=$((left + 1)); op_warn "Not empty: $item"; fi
    done <<OPEOF
$plan
OPEOF
    if [ "$left" -gt 0 ]; then
        op_fail "$left Teams cache folder(s) could not be emptied. Grant the RMM agent Full Disk Access, then run again."
    fi
fi

# Finish
answer="Cleared the Teams cache for $cleared_users user(s): $folder_total folder(s), $((total_kb / 1024)) MB freed"
if [ -n "$skipped_users" ]; then answer="$answer; skipped $skipped_users (Teams running)"; fi
op_finish CHANGED "$answer"
