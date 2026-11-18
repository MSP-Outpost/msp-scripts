#!/bin/bash
# ---------------------------------------------------------------------------
# SYNOPSIS:    Installs or updates a Mac app from a download link you supply, after checking its hash or its developer.
# DESCRIPTION:
#   THIS SCRIPT CHANGES THINGS. It downloads a .dmg, .pkg or .zip from the
#   https link you give (or reads a file already on the Mac), and REFUSES to
#   continue unless you also give a SHA256 of that file or the Developer ID
#   Team ID the app or package must be signed by (or both). The Team ID is
#   checked with codesign and spctl for an app, pkgutil --check-signature and
#   spctl for a package. It then installs: an app is copied into /Applications
#   (an older copy is replaced), a package is run with installer. If the same
#   or a newer version is already installed it changes nothing and says so. A
#   running app is not replaced unless QUIT_APP is true. It ships no list of
#   apps: you supply the link and the proof. Temporary files and the mounted
#   disk image are always cleaned up. It never restarts the Mac and never
#   removes anything except the app it replaces. A DRY_RUN downloads and checks
#   the file, then reports what it would install.
# INPUTS:
#   --download-url URL     (env DOWNLOAD_URL)  https link to a .dmg, .pkg or .zip. Give this or SOURCE_FILE.
#   --source-file PATH     (env SOURCE_FILE)   A .dmg, .pkg or .zip already on this Mac (staged by your RMM).
#   --sha256 HEX           (env SHA256)        SHA256 the file must have. Give this, TEAM_ID, or both.
#   --team-id ID           (env TEAM_ID)       Developer ID Team ID (10 characters) that must have signed it.
#   --bundle-id ID         (env BUNDLE_ID)     Optional. Picks the app inside a disk image or zip with several apps.
#   --quit-app BOOL        (env QUIT_APP)      Quit the app first if it is running and needs replacing. Default false.
#   --dry-run BOOL         (env DRY_RUN)       Download and check, install nothing. Default false.
#   --output-format F      (env OUTPUT_FORMAT) Text (default), Answer, Json or Csv.
#   --export-path FILE     (env EXPORT_PATH)   Also write rows to this .csv or .json file.
#   --result-field NAME    (env RESULT_FIELD)  Also write the answer to this RMM custom field.
# EXAMPLE:
#   sudo ./install-mac-app.sh --download-url https://example.com/Widget.dmg --team-id ABCDE12345
#   sudo ./install-mac-app.sh --download-url https://example.com/widget.pkg --sha256 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08
# NOTES:
#   Name:        Install or update a Mac app from a link, verified by hash or developer
#   Slug:        install-mac-app
#   Version:     1.0.0
#   Updated:     2026-11-17
#   Type:        Action
#   Category:    19 macOS management
#   Platforms:   macOS 13+
#   RunAs:       System
#   Requires:    bash 3.2, root, internet access to the link (unless SOURCE_FILE is used)
#   Changes:     Installs or replaces an app in /Applications, or runs a package installer
#   Risk:        Low
#   Reboot:      Never
#   Runtime:     1 to 10 minutes, mostly the download
#   Answer:      "Installed Widget 2.1 (com.example.widget); Team ID ABCDE12345 verified"
#   Fields:      Item, Change, Result
#   Runtime-Lib: 1.0.0
#   Source:      https://mspoutpost.com/scripts/install-mac-app
#   License:     MIT
#   Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
#   Changelog:
#     1.0.0  2026-11-17  First version.
# ---------------------------------------------------------------------------

# Identity: must match NOTES above (the build checks it).
OP_SLUG="install-mac-app"
OP_VERSION="1.0.0"
OP_TYPE="Action"
OP_RISK="Low"
OP_FIELDS=(Item Change Result)
OP_INPUTS=(DOWNLOAD_URL SOURCE_FILE SHA256 TEAM_ID BUNDLE_ID QUIT_APP)

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
DEFAULT_DOWNLOAD_URL=""
DEFAULT_SOURCE_FILE=""
DEFAULT_SHA256=""
DEFAULT_TEAM_ID=""
DEFAULT_BUNDLE_ID=""
DEFAULT_QUIT_APP="false"

# ---- Constants ------------------------------------------------------------
readonly DOWNLOAD_TIMEOUT_SECONDS=1800

# ---- Functions ------------------------------------------------------------
WORK_DIR=""
MOUNT_POINT=""
trap 'rc=$?; if [ -n "$MOUNT_POINT" ]; then hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1; fi; if [ -n "$WORK_DIR" ]; then rm -rf "$WORK_DIR"; fi; (exit "$rc"); op__on_exit' EXIT

lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
plist_get() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }

# ver_cmp A B prints -1, 0 or 1 comparing dotted version numbers.
ver_cmp() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        n = split(a, x, "."); m = split(b, y, "."); k = (n > m) ? n : m
        for (i = 1; i <= k; i++) { xi = x[i] + 0; yi = y[i] + 0; if (xi < yi) { print -1; exit } if (xi > yi) { print 1; exit } }
        print 0 }'
}
app_version() {
    local v
    v=$(plist_get "$1/Contents/Info.plist" CFBundleShortVersionString)
    if [ -z "$v" ]; then v=$(plist_get "$1/Contents/Info.plist" CFBundleVersion); fi
    printf '%s' "$v"
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

# Download URL to WORK_DIR/download; prints the final URL after redirects.
fetch_file() {
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
        --connect-timeout 30 --max-time "$DOWNLOAD_TIMEOUT_SECONDS" --retry 2 \
        --output "$WORK_DIR/download" --write-out '%{url_effective}' "$1"
}

# Prints dmg, pkg or zip for the file, from its name if it says, else from its first bytes.
detect_kind() {
    local name="$1" file="$2" ext magic
    name="${name%%\?*}"
    ext=$(lower "${name##*.}")
    case "$ext" in dmg|pkg|zip) printf '%s' "$ext"; return ;; esac
    magic=$(head -c 4 "$file" | od -An -tx1 | tr -d ' \n')
    case "$magic" in
        504b0304) printf 'zip' ;;
        78617221) printf 'pkg' ;;
        *) if hdiutil imageinfo "$file" >/dev/null 2>&1; then printf 'dmg'; fi ;;
    esac
}

# verify_app APP TEAM : sets VERIFY_ERR and fails when the signature or Team ID is wrong.
verify_app() {
    local got
    VERIFY_ERR=""
    if ! codesign --verify --deep --strict "$1" >/dev/null 2>&1; then VERIFY_ERR="the app's code signature is invalid or missing"; return 1; fi
    got=$(codesign -dv --verbose=4 "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -n 1)
    if [ "$got" != "$2" ]; then VERIFY_ERR="the app is signed by Team ID '${got:-none}', not $2"; return 1; fi
    if ! spctl --assess --type execute "$1" >/dev/null 2>&1; then VERIFY_ERR="macOS Gatekeeper (spctl) does not accept the app"; return 1; fi
    return 0
}
verify_pkg() {
    local sig
    VERIFY_ERR=""
    sig=$(pkgutil --check-signature "$1" 2>&1)
    case "$sig" in *"Status: signed"*) ;; *) VERIFY_ERR="the package is not signed with a trusted certificate"; return 1 ;; esac
    case "$sig" in *"($2)"*) ;; *) VERIFY_ERR="the package is not signed by Team ID $2"; return 1 ;; esac
    if ! spctl --assess --type install "$1" >/dev/null 2>&1; then VERIFY_ERR="macOS Gatekeeper (spctl) does not accept the package"; return 1; fi
    return 0
}

# Copies the app into /Applications next to a temporary name, swaps it in, checks it, removes the old copy.
replace_app() {
    local src="$1" dest="$2" new_id="$3" new_version="$4" got_id
    rm -rf "$dest.outpost-new" "$dest.outpost-old"
    ditto "$src" "$dest.outpost-new" || { rm -rf "$dest.outpost-new"; return 1; }
    if [ -e "$dest" ]; then mv "$dest" "$dest.outpost-old" || return 1; fi
    if ! mv "$dest.outpost-new" "$dest"; then
        if [ -e "$dest.outpost-old" ]; then mv "$dest.outpost-old" "$dest"; fi
        return 1
    fi
    got_id=$(plist_get "$dest/Contents/Info.plist" CFBundleIdentifier)
    if [ "$got_id" != "$new_id" ] || [ "$(app_version "$dest")" != "$new_version" ] ||
       { [ -n "$team_id" ] && ! verify_app "$dest" "$team_id"; }; then
        rm -rf "$dest"
        if [ -e "$dest.outpost-old" ]; then mv "$dest.outpost-old" "$dest"; fi
        return 1
    fi
    rm -rf "$dest.outpost-old"
    return 0
}

run_installer() {
    installer -pkg "$1" -target / > "$WORK_DIR/installer.txt" 2>&1
}

# Prints "identifier|version" for each package component inside an expanded package.
package_components() {
    local f
    find "$1" -name PackageInfo -type f 2>/dev/null | while IFS= read -r f; do
        tr '\n' ' ' < "$f" | grep -o '<pkg-info[^>]*>' | head -n 1 |
            sed -n 's/.*identifier="\([^"]*\)".* version="\([^"]*\)".*/\1|\2/p; s/.* version="\([^"]*\)".*identifier="\([^"]*\)".*/\2|\1/p' | head -n 1
    done
}

# ---- Main -----------------------------------------------------------------
op_start "$@"

# Validate
op_read_text download_url DOWNLOAD_URL "$DEFAULT_DOWNLOAD_URL"
op_read_text source_file SOURCE_FILE "$DEFAULT_SOURCE_FILE"
op_read_text sha256 SHA256 "$DEFAULT_SHA256"
op_read_text team_id TEAM_ID "$DEFAULT_TEAM_ID"
op_read_text want_bundle_id BUNDLE_ID "$DEFAULT_BUNDLE_ID"
op_read_bool quit_allowed QUIT_APP "$DEFAULT_QUIT_APP"
if [ "$OP_OS" != "macOS" ]; then op_finish SKIPPED "Skipped: this script is for macOS."; fi
op_is_root || op_fail "This script must run as root. Run it with sudo or from your RMM's system context."
if [ -z "$download_url" ] && [ -z "$source_file" ]; then
    op_fail "Neither DOWNLOAD_URL nor SOURCE_FILE is set. Give the https link to a .dmg, .pkg or .zip (or a file already on this Mac)."
fi
if [ -n "$download_url" ] && [ -n "$source_file" ]; then
    op_fail "Both DOWNLOAD_URL and SOURCE_FILE are set. Give only one."
fi
if [ -n "$download_url" ]; then
    case "$download_url" in
        https://?*) ;;
        *) op_fail "Input DOWNLOAD_URL is '$download_url'; expected a link starting with https:// (plain http is refused)." ;;
    esac
fi
if [ -n "$source_file" ]; then
    case "$source_file" in /*) ;; *) op_fail "Input SOURCE_FILE is '$source_file'; expected an absolute path such as /var/tmp/Widget.dmg." ;; esac
    if [ ! -f "$source_file" ]; then op_fail "SOURCE_FILE '$source_file' does not exist or is not a file."; fi
fi
sha256=$(lower "$sha256")
if [ -n "$sha256" ] && ! printf '%s' "$sha256" | grep -Eq '^[0-9a-f]{64}$'; then
    op_fail "Input SHA256 is '$sha256'; expected 64 hexadecimal characters."
fi
if [ -n "$team_id" ] && ! printf '%s' "$team_id" | grep -Eq '^[A-Z0-9]{10}$'; then
    op_fail "Input TEAM_ID is '$team_id'; expected the 10-character Developer ID Team ID, for example ABCDE12345."
fi
if [ -z "$sha256" ] && [ -z "$team_id" ]; then
    op_fail "Refusing to install an unverified download. Set SHA256 (the file's hash) or TEAM_ID (the developer who must have signed it), or both."
fi
if [ -n "$want_bundle_id" ] && ! printf '%s' "$want_bundle_id" | grep -Eq '^[A-Za-z0-9._-]+$'; then
    op_fail "Input BUNDLE_ID is '$want_bundle_id'; expected a bundle identifier such as com.example.widget."
fi
WORK_DIR=$(mktemp -d /private/var/tmp/outpost-install-app.XXXXXX) || op_fail "Could not create a temporary folder."

# Detect: get the file and prove it is the right one before anything runs.
if [ -n "$download_url" ]; then
    op_line "Downloading $download_url"
    final_url=$(fetch_file "$download_url") || op_fail "The download from $download_url failed. Check the link and the Mac's internet access."
    source_name="$final_url"
    source_item="$download_url"
else
    source_name="$source_file"
    source_item="$source_file"
    cp "$source_file" "$WORK_DIR/download" || op_fail "Could not copy $source_file to a temporary folder."
fi
verified_by=""
if [ -n "$sha256" ]; then
    got_sha=$(shasum -a 256 "$WORK_DIR/download" | awk '{ print $1 }')
    if [ "$got_sha" != "$sha256" ]; then
        op_fail "SHA256 mismatch: the file is ${got_sha:0:16}... but you gave ${sha256:0:16}.... Nothing was installed. Check the link or update SHA256."
    fi
    verified_by="SHA256 verified"
fi
kind=$(detect_kind "$source_name" "$WORK_DIR/download")
if [ -z "$kind" ]; then op_fail "The file is not a .dmg, .pkg or .zip. Use a link that serves one of those."; fi

# Stage: find the app or package inside the file.
payload_kind=""
payload=""
case "$kind" in
    pkg)
        cp "$WORK_DIR/download" "$WORK_DIR/payload.pkg"
        payload_kind="pkg"; payload="$WORK_DIR/payload.pkg" ;;
    zip|dmg)
        if [ "$kind" = "zip" ]; then
            stage_root="$WORK_DIR/unzipped"
            mkdir -p "$stage_root"
            ditto -x -k "$WORK_DIR/download" "$stage_root" || op_fail "Could not unzip the download; the file may be damaged."
        else
            stage_root="$WORK_DIR/mount"
            mkdir -p "$stage_root"
            if ! printf 'Y\n' | hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$stage_root" "$WORK_DIR/download" >/dev/null 2>&1; then
                op_fail "Could not mount the disk image; the file may be damaged."
            fi
            MOUNT_POINT="$stage_root"
        fi
        apps=$(find "$stage_root" -maxdepth 3 -name '*.app' -type d -prune -print 2>/dev/null)
        app_total=$(printf '%s\n' "$apps" | sed '/^$/d' | wc -l | tr -d ' ')
        if [ -n "$want_bundle_id" ]; then
            while IFS= read -r candidate; do
                [ -z "$candidate" ] && continue
                if [ "$(plist_get "$candidate/Contents/Info.plist" CFBundleIdentifier)" = "$want_bundle_id" ]; then payload="$candidate"; payload_kind="app"; break; fi
            done <<OPEOF
$apps
OPEOF
            if [ -z "$payload" ]; then op_fail "No app with bundle ID $want_bundle_id is inside the download."; fi
        elif [ "$app_total" -eq 1 ]; then
            payload=$(printf '%s\n' "$apps" | sed '/^$/d'); payload_kind="app"
        elif [ "$app_total" -gt 1 ]; then
            op_fail "The download holds $app_total apps. Set BUNDLE_ID to the one to install."
        else
            pkgs=$(find "$stage_root" -maxdepth 2 \( -name '*.pkg' -o -name '*.mpkg' \) -type f -print 2>/dev/null | sed '/^$/d')
            pkg_total=$(printf '%s\n' "$pkgs" | sed '/^$/d' | wc -l | tr -d ' ')
            if [ "$pkg_total" -eq 1 ]; then payload="$pkgs"; payload_kind="pkg"
            elif [ "$pkg_total" -gt 1 ]; then op_fail "The download holds $pkg_total packages and no app. Use a link to the one package instead."
            else op_fail "The download holds no app and no package."; fi
        fi ;;
esac

# Verify the developer.
if [ -n "$team_id" ]; then
    if [ "$payload_kind" = "app" ]; then
        verify_app "$payload" "$team_id" || op_fail "Refusing to install: $VERIFY_ERR."
    else
        verify_pkg "$payload" "$team_id" || op_fail "Refusing to install: $VERIFY_ERR."
    fi
    if [ -n "$verified_by" ]; then verified_by="$verified_by, Team ID $team_id verified"; else verified_by="Team ID $team_id verified"; fi
fi

# Act: an app.
if [ "$payload_kind" = "app" ]; then
    new_id=$(plist_get "$payload/Contents/Info.plist" CFBundleIdentifier)
    new_version=$(app_version "$payload")
    app_file=$(basename "$payload")
    app_label="${app_file%.app}"
    dest="/Applications/$app_file"
    if [ -z "$new_id" ] || [ -z "$new_version" ]; then op_fail "The app in the download has no bundle ID or version in its Info.plist."; fi
    op_line "App: $app_label $new_version ($new_id). $verified_by."
    if [ -d "$dest" ]; then
        old_id=$(plist_get "$dest/Contents/Info.plist" CFBundleIdentifier)
        old_version=$(app_version "$dest")
        if [ "$old_id" != "$new_id" ]; then
            op_fail "$dest is a different app ($old_id), not $new_id. Remove it first or use another app name."
        fi
        if [ "$(ver_cmp "$old_version" "$new_version")" -ge 0 ]; then
            op_finish OK "Already installed: $app_label $old_version (the download is $new_version)."
        fi
        if [ -n "$(app_pids "$dest")" ]; then
            if [ "$quit_allowed" -eq 1 ]; then
                op_change "$dest" "Quit the running app" quit_running_app "$dest" "$new_id" || true
            else
                op_finish SKIPPED "Skipped: $app_label is running and needs updating. Set QUIT_APP=true or run when it is closed."
            fi
        fi
        change_text="Update $old_version to $new_version"
    else
        change_text="Install $new_version"
    fi
    op_change "$source_item" "$change_text in /Applications" replace_app "$payload" "$dest" "$new_id" "$new_version" || true
    answer="Installed $app_label $new_version ($new_id); $verified_by"
    if [ "$OP_DRY_RUN" -eq 0 ] && { [ ! -d "$dest" ] || [ "$(plist_get "$dest/Contents/Info.plist" CFBundleIdentifier)" != "$new_id" ]; }; then
        op_fail "$dest is not in place after the install. Run again and check /Library/Logs/MSPOutpost/install-mac-app.log."
    fi
    op_finish CHANGED "$answer"
fi

# Act: a package.
expanded="$WORK_DIR/expanded"
components=""
if pkgutil --expand "$payload" "$expanded" >/dev/null 2>&1; then components=$(package_components "$expanded"); fi
if [ -z "$components" ]; then
    op_warn "Could not read the package's identifier and version, so it is installed without an 'already installed' check."
else
    all_present=1
    while IFS='|' read -r pkg_id pkg_version; do
        [ -z "$pkg_id" ] && continue
        have=$(pkgutil --pkg-info "$pkg_id" 2>/dev/null | sed -n 's/^version: //p')
        if [ -z "$have" ] || [ "$(ver_cmp "$have" "$pkg_version")" -lt 0 ]; then all_present=0; fi
    done <<OPEOF
$components
OPEOF
    if [ "$all_present" -eq 1 ]; then
        op_finish OK "Already installed: every package in this download is installed at this version or newer."
    fi
fi
op_line "Package: $(printf '%s' "$components" | head -n 1 | tr '|' ' '). $verified_by."
op_change "$source_item" "Install the package" run_installer "$payload" || true
if [ "$OP_DRY_RUN" -eq 0 ] && [ -n "$components" ]; then
    while IFS='|' read -r pkg_id pkg_version; do
        [ -z "$pkg_id" ] && continue
        if ! pkgutil --pkg-info "$pkg_id" >/dev/null 2>&1; then
            op_fail "The installer finished but package $pkg_id has no receipt. Check /var/log/install.log."
        fi
    done <<OPEOF
$components
OPEOF
fi
first_component=$(printf '%s' "$components" | head -n 1 | tr '|' ' ')
op_finish CHANGED "Installed package ${first_component:-from the download}; $verified_by"
