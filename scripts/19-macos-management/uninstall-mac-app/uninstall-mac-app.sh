#!/bin/bash
# ---------------------------------------------------------------------------
# SYNOPSIS:    Removes a Mac app by name or bundle ID, plus the files it left behind.
# DESCRIPTION:
#   THIS SCRIPT CHANGES THINGS. It finds the app bundle by exact name or exact
#   bundle ID in /Applications and each user's Applications folder, then
#   removes: the bundle; the app's launchd jobs (LaunchAgents/LaunchDaemons in
#   /Library and in each user's Library) whose Program points into the bundle;
#   per-user and system leftovers in known folders derived from the bundle ID
#   (Application Support, Caches, HTTPStorages, WebKit, Containers,
#   Application Scripts, Saved Application State, Logs, the Preferences plist
#   and its ByHost copies) and the Application Support folder named after the
#   app; and package receipts that list the bundle itself (pkgutil --forget).
#   The list of removed paths and each removed launchd plist are backed up first.
#   It never touches Apple apps (com.apple.* IDs, anything in /System), bundle IDs
#   starting com.ninjarmm., com.jamf., com.jamfsoftware., io.kandji., com.addigy. or
#   com.splashtop. (management and remote-support agents), or any name with a
#   wildcard. A running app is left alone (the run is SKIPPED) unless QUIT_APP is
#   true, which asks it to quit, then ends its processes.
#   High risk: it is a dry run unless DRY_RUN=false AND APPROVE=uninstall-mac-app
#   are both set. By default it makes at most 25 changes per run (MAX_CHANGES).
#   Needs root. If macOS refuses to delete a protected folder, grant the RMM
#   agent Full Disk Access.
# INPUTS:
#   --app NAME_OR_ID        (env APP)          REQUIRED. App name (Zoom for Zoom.app) or bundle ID, exact.
#   --quit-app BOOL         (env QUIT_APP)     Quit the app first if it is running. Default false.
#   --target-user NAME      (env TARGET_USER)  Only this user's leftovers. Default every user.
#   --dry-run BOOL          (env DRY_RUN)      Default true (High risk). Set false AND APPROVE to remove.
#   --approve SLUG          (env APPROVE)      Must be uninstall-mac-app for a real run.
#   --max-changes N         (env MAX_CHANGES)  Most changes one run may make. Default 25.
#   --output-format F       (env OUTPUT_FORMAT) Text (default), Answer, Json or Csv.
#   --export-path FILE      (env EXPORT_PATH)  Also write rows to this .csv or .json file.
#   --result-field NAME     (env RESULT_FIELD) Also write the answer to this RMM custom field.
# EXAMPLE:
#   sudo ./uninstall-mac-app.sh --app com.example.widget
#   sudo ./uninstall-mac-app.sh --app Widget --quit-app true --dry-run false --approve uninstall-mac-app
# NOTES:
#   Name:        Remove a Mac app and everything it left behind
#   Slug:        uninstall-mac-app
#   Version:     1.0.0
#   Updated:     2026-11-17
#   Type:        Action
#   Category:    19 macOS management
#   Platforms:   macOS 13+
#   RunAs:       System
#   Requires:    bash 3.2, root; Full Disk Access for the RMM agent to clear some protected folders
#   Changes:     Deletes the app bundle, its launchd jobs, per-user and system leftover folders and preference files, and package receipts
#   Risk:        High
#   Reboot:      Never
#   Runtime:     Under 1 minute
#   Answer:      "Removed Widget (com.example.widget): the app and 7 related item(s)"
#   Fields:      Item, Change, Result
#   Runtime-Lib: 1.0.0
#   Source:      https://mspoutpost.com/scripts/uninstall-mac-app
#   License:     MIT
#   Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
#   Changelog:
#     1.0.0  2026-11-17  First version.
# ---------------------------------------------------------------------------

# Identity: must match NOTES above (the build checks it).
OP_SLUG="uninstall-mac-app"
OP_VERSION="1.0.0"
OP_TYPE="Action"
OP_RISK="High"
OP_FIELDS=(Item Change Result)
OP_INPUTS=(APP QUIT_APP TARGET_USER)

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
DEFAULT_APP=""
DEFAULT_QUIT_APP="false"
DEFAULT_TARGET_USER=""

# ---- Constants ------------------------------------------------------------
# A bundle ID that STARTS WITH one of these (case-insensitive) is an RMM, MDM or remote-support
# agent of ours or a peer's: never removed. Each prefix is confirmed by vendor documentation or
# the reference scripts (NinjaOne: com.ninjarmm.*; Jamf: com.jamf.*, com.jamfsoftware.*; Kandji: io.kandji.*;
# Addigy: com.addigy.*; Splashtop: com.splashtop.*). Datto, ScreenConnect, N-able, Kaseya and Atera
# are not listed because their bundle ID prefixes could not be confirmed.
readonly PROTECTED_ID_PREFIXES="com.ninjarmm. com.jamf. com.jamfsoftware. io.kandji. com.addigy. com.splashtop."

# ---- Functions ------------------------------------------------------------
WORK_DIR=""
trap 'rc=$?; if [ -n "$WORK_DIR" ]; then rm -rf "$WORK_DIR"; fi; (exit "$rc"); op__on_exit' EXIT

lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
plist_get() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }

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

# Prints "path<TAB>bundle id" for every app whose bundle ID or file name equals the input (case-insensitive).
find_bundles() {
    local dir app id base
    { printf '%s\n' /Applications; list_users | awk -F'\t' '{ print $3 "/Applications" }'; } | while IFS= read -r dir; do
        [ -d "$dir" ] || continue
        find "$dir" -maxdepth 2 -name '*.app' -type d -prune -print 2>/dev/null | while IFS= read -r app; do
            id=$(plist_get "$app/Contents/Info.plist" CFBundleIdentifier)
            base=$(basename "$app" .app)
            if [ "$(lower "$id")" = "$app_key" ] || [ "$(lower "$base")" = "$app_key" ]; then
                printf '%s\t%s\n' "$app" "$id"
            fi
        done
    done | sort -u
}

app_pids() { ps -axo pid=,command= 2>/dev/null | P="$1/Contents/" awk 'index($0, ENVIRON["P"]) > 0 { print $1 }'; }

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

# Asks the app to quit (when macOS knows it as a running app), then ends what is left.
quit_running_app() {
    local app="$1" id="$2" console uid i=0
    [ -n "$(app_pids "$app")" ] || return 0
    console=$(op_signed_in_user)
    if [ -n "$console" ] && printf '%s' "$id" | grep -Eq '^[A-Za-z0-9._-]+$'; then
        uid=$(id -u "$console")
        if [ -n "$(launchctl asuser "$uid" /usr/bin/lsappinfo find "bundleid=$id" 2>/dev/null)" ]; then
            run_limited 12 launchctl asuser "$uid" sudo -u "$console" /usr/bin/osascript -e "tell application id \"$id\" to quit"
        fi
    fi
    while [ "$i" -lt 10 ] && [ -n "$(app_pids "$app")" ]; do sleep 1; i=$((i + 1)); done
    if [ -n "$(app_pids "$app")" ]; then
        # shellcheck disable=SC2046
        kill -TERM $(app_pids "$app") 2>/dev/null
        i=0
        while [ "$i" -lt 10 ] && [ -n "$(app_pids "$app")" ]; do sleep 1; i=$((i + 1)); done
    fi
    [ -z "$(app_pids "$app")" ]
}

# Deletes one path, only under the folders this script ever builds paths in.
safe_rm() {
    case "$1" in
        /Applications/?*|/Users/?*/Applications/?*|/Users/?*/Library/?*|/Library/?*) ;;
        *) return 1 ;;
    esac
    case "$1" in */../*|*/..) return 1 ;; esac
    if ! rm -rf -- "$1" 2>/dev/null; then
        op_warn "macOS refused to delete $1 (grant Full Disk Access to the RMM agent)."
    fi
    return 0
}

remove_launchd() {
    local plist="$1" domain="$2" label
    label=$(plist_get "$plist" Label)
    if [ -n "$label" ] && [ -n "$domain" ]; then launchctl bootout "$domain/$label" >/dev/null 2>&1; fi
    op_backup "$plist" >/dev/null
    safe_rm "$plist"
}

forget_receipt() { pkgutil --forget "$1" >/dev/null 2>&1; }

# Prints the paths that exist among the known leftover places for a bundle ID (and the app's name).
# HOME empty means the system-wide Library.
leftover_paths() {
    local id="$1" name="$2" home="$3" lib p f
    lib="$home/Library"
    if [ -z "$home" ]; then lib="/Library"; fi
    for p in "$lib/Application Support/$id" "$lib/Caches/$id" "$lib/Preferences/$id.plist" "$lib/Logs/$id"; do
        if [ -e "$p" ] || [ -L "$p" ]; then printf '%s\n' "$p"; fi
    done
    if [ -n "$name" ] && [ -e "$lib/Application Support/$name" ]; then printf '%s\n' "$lib/Application Support/$name"; fi
    if [ -n "$home" ]; then
        for p in "$lib/HTTPStorages/$id" "$lib/WebKit/$id" "$lib/Containers/$id" "$lib/Application Scripts/$id" "$lib/Saved Application State/$id.savedState"; do
            if [ -e "$p" ] || [ -L "$p" ]; then printf '%s\n' "$p"; fi
        done
        for f in "$lib/Preferences/ByHost/$id."*.plist; do
            if [ -f "$f" ]; then printf '%s\n' "$f"; fi
        done
    fi
}

# Prints "plist<TAB>domain" for launchd plists in a folder whose Program (or first argument) is inside the bundle.
scan_launchd() {
    local dir="$1" app="$2" domain="$3" plist prog first
    [ -d "$dir" ] || return 0
    for plist in "$dir"/*.plist; do
        [ -f "$plist" ] || continue
        prog=$(plist_get "$plist" Program)
        first=$(plist_get "$plist" ProgramArguments:0)
        case "$prog" in "$app"/*) printf '%s\t%s\n' "$plist" "$domain"; continue ;; esac
        case "$first" in "$app"/*) printf '%s\t%s\n' "$plist" "$domain" ;; esac
    done
}

# Prints the receipt IDs whose file list contains the bundle folder itself.
find_receipts() {
    local app="$1" rel pkg loc sub
    rel="${app#/}"
    pkgutil --pkgs 2>/dev/null | while IFS= read -r pkg; do
        case "$pkg" in com.apple.*) continue ;; esac
        loc=$(pkgutil --pkg-info "$pkg" 2>/dev/null | sed -n 's/^location: //p')
        loc="${loc#/}"; loc="${loc%/}"
        sub="$rel"
        if [ -n "$loc" ]; then
            case "$rel" in "$loc"/*) sub="${rel#"$loc"/}" ;; *) continue ;; esac
        fi
        if pkgutil --files "$pkg" 2>/dev/null | grep -Fx -- "$sub" >/dev/null; then printf '%s\n' "$pkg"; fi
    done
}

# Prints every leftover path for a bundle ID and name: system-wide, then each user.
all_leftovers() {
    leftover_paths "$1" "$2" ""
    list_users | while IFS=$'\t' read -r u_name u_uid u_home; do leftover_paths "$1" "$2" "$u_home"; done
}

# Prints every launchd plist that runs from inside the bundle.
all_launchd() {
    scan_launchd /Library/LaunchDaemons "$1" system
    scan_launchd /Library/LaunchAgents "$1" ""
    list_users | while IFS=$'\t' read -r u_name u_uid u_home; do scan_launchd "$u_home/Library/LaunchAgents" "$1" "gui/$u_uid"; done
}

PLAN=""
add_plan() { PLAN="${PLAN}$1"$'\t'"$2"$'\t'"${3:-}"$'\n'; }

# ---- Main -----------------------------------------------------------------
op_start "$@"

# Validate
op_read_text app_input APP "$DEFAULT_APP" required
op_read_bool quit_allowed QUIT_APP "$DEFAULT_QUIT_APP"
op_read_text target_user TARGET_USER "$DEFAULT_TARGET_USER"
if [ "$OP_OS" != "macOS" ]; then op_finish SKIPPED "Skipped: this script is for macOS."; fi
op_is_root || op_fail "This script must run as root. Run it with sudo or from your RMM's system context."
case "$app_input" in
    *[\*\?\[\]/\\]*|-*) op_fail "Input APP is '$app_input'; expected an exact app name or bundle ID with no wildcards, slashes or leading dash." ;;
esac
if [ "${#app_input}" -lt 3 ]; then op_fail "Input APP is '$app_input'; expected at least 3 characters (an exact app name or bundle ID)."; fi
app_key=$(lower "${app_input%.app}")
case "$app_key" in com.apple.*) op_fail "Input APP is '$app_input'; Apple apps (com.apple.*) are never removed by this script." ;; esac
if [ -n "$target_user" ] && [ -z "$(list_users)" ]; then
    op_fail "Input TARGET_USER is '$target_user'; expected the short name of an existing user account (UID 500 or higher)."
fi

# Detect
op_line "Looking for '$app_input' in /Applications and each user's Applications folder."
bundles=$(find_bundles)
display_name=""
display_id=""
running_name=""
bundle_count=0
while IFS=$'\t' read -r app id; do
    [ -z "$app" ] && continue
    case "$app" in /System/*) op_fail "$app is a system app; this script never removes anything in /System." ;; esac
    case "$(lower "$id")" in com.apple.*) op_fail "$app has the Apple bundle ID $id; Apple apps are never removed by this script." ;; esac
    for prefix in $PROTECTED_ID_PREFIXES; do
        case "$(lower "$id")" in "$prefix"*) op_fail "$app ($id) is an RMM, MDM or remote-support agent (bundle ID starts with $prefix), which this script never removes." ;; esac
    done
    name=$(basename "$app" .app)
    bundle_count=$((bundle_count + 1))
    if [ -z "$display_name" ]; then display_name="$name"; display_id="$id"; fi
    if [ -n "$(app_pids "$app")" ]; then
        if [ "$quit_allowed" -eq 1 ]; then add_plan 1quit "$app" "$id"; else running_name="$name"; fi
    fi
    add_plan 3bundle "$app" "$id"
    while IFS=$'\t' read -r plist domain; do
        [ -z "$plist" ] && continue
        add_plan 2launchd "$plist" "$domain"
    done <<OPEOF
$(all_launchd "$app")
OPEOF
    case "$app" in
        /Applications/*)
            for pkg in $(find_receipts "$app"); do add_plan 5receipt "$pkg" ""; done ;;
    esac
    if [ -n "$id" ]; then
        while IFS= read -r leftover; do
            [ -z "$leftover" ] && continue
            add_plan 4path "$leftover" ""
        done <<OPEOF
$(all_leftovers "$id" "$name")
OPEOF
    fi
done <<OPEOF
$bundles
OPEOF
if [ "$bundle_count" -eq 0 ] && printf '%s' "$app_input" | grep -Eq '^[A-Za-z0-9-]+(\.[A-Za-z0-9_-]+)+$'; then
    op_line "No app bundle found; checking for leftovers of bundle ID $app_input."
    display_name="$app_input"
    display_id="$app_input"
    while IFS= read -r leftover; do
        [ -z "$leftover" ] && continue
        add_plan 4path "$leftover" ""
    done <<OPEOF
$(all_leftovers "$app_input" "")
OPEOF
fi

PLAN=$(printf '%s' "$PLAN" | awk '!seen[$0]++' | sort -s -t "$(printf '\t')" -k1,1)
planned=$(printf '%s\n' "$PLAN" | sed '/^$/d' | wc -l | tr -d ' ')
if [ "$planned" -eq 0 ]; then
    op_finish OK "Nothing to remove: $app_input is not installed and has no leftovers."
fi
if [ -n "$running_name" ]; then
    op_finish SKIPPED "Skipped: $running_name is running. Quit it first or set QUIT_APP=true."
fi
op_assert_change_limit "$planned"

# Act
if [ "$OP_DRY_RUN" -eq 0 ]; then
    WORK_DIR=$(mktemp -d /private/var/tmp/outpost-uninstall.XXXXXX) || op_fail "Could not create a temporary folder."
    printf '%s\n' "$PLAN" | awk -F'\t' 'NF >= 2 { print $2 }' > "$WORK_DIR/removed-paths.txt"
    op_backup "$WORK_DIR/removed-paths.txt" >/dev/null
fi
op_line "Removing $planned item(s) for ${display_name:-$app_input}."
while IFS=$'\t' read -r kind value extra; do
    [ -z "$kind" ] && continue
    case "$kind" in
        1quit)    op_change "$value" "Quit the running app" quit_running_app "$value" "$extra" || true ;;
        2launchd) op_change "$value" "Remove launchd job" remove_launchd "$value" "$extra" || true ;;
        3bundle)  op_change "$value" "Delete app bundle" safe_rm "$value" || true ;;
        4path)    op_change "$value" "Delete leftover" safe_rm "$value" || true ;;
        5receipt) op_change "$value" "Forget package receipt" forget_receipt "$value" || true ;;
    esac
done <<OPEOF
$PLAN
OPEOF

# Verify
if [ "$OP_DRY_RUN" -eq 0 ]; then
    left=0
    while IFS=$'\t' read -r kind value extra; do
        case "$kind" in
            2launchd|3bundle|4path) if [ -e "$value" ] || [ -L "$value" ]; then left=$((left + 1)); op_warn "Still present: $value"; fi ;;
            5receipt) if pkgutil --pkg-info "$value" >/dev/null 2>&1; then left=$((left + 1)); op_warn "Receipt still present: $value"; fi ;;
        esac
    done <<OPEOF
$PLAN
OPEOF
    if [ "$left" -gt 0 ]; then
        op_fail "$left item(s) of ${display_name:-$app_input} could not be removed. Grant the RMM agent Full Disk Access or remove them by hand, then run again."
    fi
fi

# Finish
if [ "$bundle_count" -gt 0 ]; then
    op_finish CHANGED "Removed ${display_name:-$app_input} (${display_id:-no bundle ID}): the app and $((planned - bundle_count)) related item(s)"
fi
op_finish CHANGED "Removed $planned leftover item(s) of ${display_id:-$app_input}; the app itself was already gone"
