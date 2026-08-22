#!/usr/bin/env bash
# This script uses fzf to display a list of panes and allows you to select one.
#
# If you press ENTER, it switches to the selected pane.
# If you press ENTER on an empty line, it creates a new window in the current session.
field_separator=$'\037'
record_separator=$'\036'
ansi_reset=$'\033[0m'
separator_colour=''
list_panes_colours=''
row_1_colours=''
row_2_colours=''
tree_session_colours=''
tree_window_colours=''
tree_pane_colours=''
match_directory=''
match_owner_magic='fzf-pane-switch-v1'

# Converts a supported named or six-digit hexadecimal colour to an ANSI code.
function colour_to_ansi() {
    local colour hex red green blue
    colour=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')

    if [[ "${colour}" =~ ^#[0-9a-f]{6}$ ]]; then
        hex="${colour#\#}"
        red=$((16#${hex:0:2}))
        green=$((16#${hex:2:2}))
        blue=$((16#${hex:4:2}))
        printf '\033[38;2;%d;%d;%dm' "${red}" "${green}" "${blue}"
        return
    fi

    case "${colour}" in
        black) printf '\033[30m' ;;
        red) printf '\033[31m' ;;
        green) printf '\033[32m' ;;
        yellow) printf '\033[33m' ;;
        blue) printf '\033[34m' ;;
        magenta) printf '\033[35m' ;;
        cyan) printf '\033[36m' ;;
        white) printf '\033[37m' ;;
        bright-black | gray | grey) printf '\033[90m' ;;
        bright-red) printf '\033[91m' ;;
        bright-green) printf '\033[92m' ;;
        bright-yellow) printf '\033[93m' ;;
        bright-blue) printf '\033[94m' ;;
        bright-magenta) printf '\033[95m' ;;
        bright-cyan) printf '\033[96m' ;;
        bright-white) printf '\033[97m' ;;
    esac
}

# Converts a supported text attribute to its ANSI code.
function attribute_to_ansi() {
    local attribute
    attribute=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    case "${attribute}" in
        bold) printf '\033[1m' ;;
        dim) printf '\033[2m' ;;
        italic) printf '\033[3m' ;;
        underline) printf '\033[4m' ;;
        reverse) printf '\033[7m' ;;
        strikethrough) printf '\033[9m' ;;
    esac
}

# Converts a positional colour and its optional attributes to ANSI codes.
function positional_style_to_ansi() {
    local specification="$1" attribute
    local -a parts=()
    IFS=':' read -r -a parts <<< "${specification}"
    colour_to_ansi "${parts[0]}"
    for attribute in "${parts[@]:1}"; do
        attribute_to_ansi "${attribute}"
    done
}

# Wraps a tmux format token in its configured positional style.
function format_value() {
    local token="$1" positional_colour="${2:-none}" ansi=''
    case "${positional_colour}" in
        none) ;;
        *) ansi="$(positional_style_to_ansi "${positional_colour}")" ;;
    esac
    if [[ -n "${ansi}" ]]; then
        printf '%s#{%s}%s' "${ansi}" "${token}" "${ansi_reset}"
    else
        printf '#{%s}' "${token}"
    fi
}

# Formats the separator placed between values, including its optional colour.
function format_value_separator() {
    local separator="$1" ansi
    ansi="$(colour_to_ansi "${separator_colour}")"
    if [[ -n "${ansi}" ]]; then
        printf ' %s%s%s ' "${ansi}" "${separator}" "${ansi_reset}"
    else
        printf ' %s ' "${separator}"
    fi
}

# Builds one display row from tmux format tokens and positional colours.
function format_row() {
    local row_format="$1" separator="$2" positional_colours="${3:-}"
    local token result='' formatted_separator positional_colour index
    local -a tokens=() colours=()
    read -r -a tokens <<< "${row_format}"
    read -r -a colours <<< "${positional_colours}"
    formatted_separator="$(format_value_separator "${separator}")"

    for index in "${!tokens[@]}"; do
        token="${tokens[index]}"
        positional_colour="${colours[index]:-none}"
        if [[ -n "${result}" ]]; then
            result+="${formatted_separator}"
        fi
        result+="$(format_value "${token}" "${positional_colour}")"
    done

    printf '%s' "${result}"
}

# Tree field separators are structural presentation, not shared layout config.
function format_tree_row() {
    local saved_separator_colour="${separator_colour}"
    separator_colour=''
    format_row "$1" '│' "${2:-}"
    separator_colour="${saved_separator_colour}"
}

# Builds the one-row tmux format with the pane ID kept as the first field.
function format_one_row() {
    local list_format="$1" positional_colours="${2:-}"
    local token positional_colour index result='#{pane_id} '
    local -a tokens=() colours=()
    read -r -a tokens <<< "${list_format}"
    read -r -a colours <<< "${positional_colours}"

    for index in "${!tokens[@]}"; do
        token="${tokens[index]}"
        positional_colour="${colours[index]:-none}"
        result+="$(format_value "${token}" "${positional_colour}") "
    done

    printf '%s' "${result}"
}

# Builds a two-row tmux format with the selected presentation style and record markers.
function structured_pane_format() {
    local style="$1" row_1_format="$2" row_2_format="$3" separator="$4"
    local row_1 row_2
    row_1="$(format_row "${row_1_format}" "${separator}" "${row_1_colours}")"
    row_2="$(format_row "${row_2_format}" "${separator}" "${row_2_colours}")"

    case "${style}" in
        plain)
            printf '#{pane_id}%s%s\n%s%s' "${field_separator}" "${row_1}" "${row_2}" "${record_separator}"
            ;;
        indented)
            printf '#{pane_id}%s● %s\n  %s%s' "${field_separator}" "${row_1}" "${row_2}" "${record_separator}"
            ;;
        connected)
            printf '#{pane_id}%s╭─ %s\n╰─ %s%s' "${field_separator}" "${row_1}" "${row_2}" "${record_separator}"
            ;;
    esac
}

# Converts tmux's marked two-row output into NUL-delimited records for fzf.
function generate_structured_records() {
    local pane_format="$1" record

    while IFS= read -r -d "${record_separator}" record; do
        record="${record#$'\n'}"
        printf '%s\0' "${record}"
    done < <(tmux list-panes -aF "${pane_format}")
}

# Emits the permanently expanded Session > Window > Pane hierarchy as
# NUL-delimited fzf records. Stable target and node-type fields remain hidden;
# the dim breadcrumb is deliberately visible so it participates in searching.
function generate_tree_records() {
    local session_format="$1" window_format="$2" pane_format="$3"
    local record

    while IFS= read -r -d "${record_separator}" record; do
        printf '%s\0' "${record}"
    done < <(
        {
            tmux list-sessions -F "session${field_separator}#{session_id}${field_separator}#{session_name}${field_separator}${session_format}"
            tmux list-windows -aF "window${field_separator}#{session_id}${field_separator}#{window_id}${field_separator}#{window_name}${field_separator}${window_format}"
            tmux list-panes -aF "pane${field_separator}#{window_id}${field_separator}#{pane_id}${field_separator}${pane_format}"
        } | awk -F "${field_separator}" \
            -v field_separator="${field_separator}" \
            -v record_separator="${record_separator}" \
            -v dim=$'\033[2m' \
            -v reset="${ansi_reset}" '
            $1 == "session" {
                session_id = $2
                session_order[++session_total] = session_id
                session_name[session_id] = $3
                session_label[session_id] = $4
                next
            }
            $1 == "window" {
                session_id = $2
                window_id = $3
                session_window[session_id, ++window_total[session_id]] = window_id
                window_name[window_id] = $4
                window_label[window_id] = $5
                next
            }
            $1 == "pane" {
                window_id = $2
                pane_id = $3
                window_pane[window_id, ++pane_total[window_id]] = pane_id
                pane_label[pane_id] = $4
            }
            END {
                for (session_index = 1; session_index <= session_total; session_index++) {
                    session_id = session_order[session_index]
                    printf "%s%ssession%s%s%s", session_id, field_separator, field_separator, session_label[session_id], record_separator

                    for (window_index = 1; window_index <= window_total[session_id]; window_index++) {
                        window_id = session_window[session_id, window_index]
                        window_branch = window_index < window_total[session_id] ? "├─" : "└─"
                        printf "%s%swindow%s  %s %s  %s%s%s%s", window_id, field_separator, field_separator, \
                            window_branch, window_label[window_id], dim, session_name[session_id], reset, record_separator

                        for (pane_index = 1; pane_index <= pane_total[window_id]; pane_index++) {
                            pane_id = window_pane[window_id, pane_index]
                            window_rail = window_index < window_total[session_id] ? "│ " : "  "
                            pane_branch = pane_index < pane_total[window_id] ? "├─" : "└─"
                            printf "%s%spane%s  %s %s %s  %s%s › %s%s%s", pane_id, field_separator, field_separator, \
                                window_rail, pane_branch, pane_label[pane_id], dim, session_name[session_id], \
                                window_name[window_id], reset, record_separator
                        }
                    }
                }
            }
        '
    )
}

# Generates pane records using the framing required by the selected layout.
function generate_records() {
    local layout="$1" pane_format="$2"
    if [[ "${layout}" == 'two-row' ]]; then
        generate_structured_records "${pane_format}"
    elif [[ "${layout}" == 'tree' ]]; then
        generate_tree_records "${FZF_PANE_SWITCH_TREE_SESSION_FORMAT:?missing session format}" \
            "${FZF_PANE_SWITCH_TREE_WINDOW_FORMAT:?missing window format}" \
            "${FZF_PANE_SWITCH_TREE_PANE_FORMAT:?missing tree pane format}"
    else
        tmux list-panes -aF "${pane_format}"
    fi
}

# Converts every layout to one NUL-delimited record shape for the optional
# content-matching path: target, node type, and visible display text.
function generate_match_records() {
    local layout="$1" pane_format="$2" record target node_type display remainder
    local -a pipeline_status=()

    if [[ "${layout}" == 'one-row' ]]; then
        generate_records "${layout}" "${pane_format}" |
            while IFS= read -r record; do
                target="${record%% *}"
                display="${record#* }"
                printf '%s%s%s%s%s\0' \
                    "${target}" "${field_separator}" pane "${field_separator}" "${display}" || exit 1
            done
        pipeline_status=("${PIPESTATUS[@]}")
        [[ "${pipeline_status[0]}" -eq 0 && "${pipeline_status[1]}" -eq 0 ]]
        return
    fi

    generate_records "${layout}" "${pane_format}" |
        while IFS= read -r -d '' record; do
            target="${record%%"${field_separator}"*}"
            remainder="${record#*"${field_separator}"}"
            if [[ "${layout}" == 'tree' ]]; then
                node_type="${remainder%%"${field_separator}"*}"
                display="${remainder#*"${field_separator}"}"
            else
                node_type='pane'
                display="${remainder}"
            fi
            printf '%s%s%s%s%s\0' \
                "${target}" "${field_separator}" "${node_type}" "${field_separator}" "${display}" || exit 1
        done
    pipeline_status=("${PIPESTATUS[@]}")
    [[ "${pipeline_status[0]}" -eq 0 && "${pipeline_status[1]}" -eq 0 ]]
}

# Writes the visible metadata and its plain search projection in one pass. This
# avoids a second per-pane Bash loop on the first-list and refresh paths.
function generate_match_record_files() {
    local layout="$1" pane_format="$2" metadata_file="$3" search_file="$4"
    local record target remainder node_type display plain_display prefix suffix
    local -a pipeline_status=()
    generate_match_records "${layout}" "${pane_format}" |
        while IFS= read -r -d '' record; do
            printf '%s\0' "${record}" >&3 || exit 1
            target="${record%%"${field_separator}"*}"
            remainder="${record#*"${field_separator}"}"
            node_type="${remainder%%"${field_separator}"*}"
            display="${remainder#*"${field_separator}"}"
            plain_display="${display}"
            while [[ "${plain_display}" == *$'\033['*m* ]]; do
                prefix="${plain_display%%$'\033['*}"
                suffix="${plain_display#*$'\033['}"
                suffix="${suffix#*m}"
                plain_display="${prefix}${suffix}"
            done
            printf '%s%s%s%s%s%s%s\0' \
                "${target}" "${field_separator}" "${node_type}" "${field_separator}" \
                "${plain_display}" "${field_separator}" "${display}" >&4 || exit 1
        done 3> "${metadata_file}" 4> "${search_file}"
    pipeline_status=("${PIPESTATUS[@]}")
    [[ "${pipeline_status[0]}" -eq 0 && "${pipeline_status[1]}" -eq 0 ]]
}

# Confines helper operations to the private directory created by this script.
function is_match_directory() {
    local directory="$1" temporary_root="${TMPDIR:-/tmp}"
    temporary_root="${temporary_root%/}"
    [[ -d "${directory}" && ! -L "${directory}" && "${directory}" == "${temporary_root}"/fzf-pane-switch.* ]]
}

# Returns the owner PID only for directories created by this feature. The
# marker prevents a broad temporary-directory sweep from trusting names alone.
function match_owner_pid() {
    local directory="$1" magic owner_pid
    is_match_directory "${directory}" || return 1
    [[ -O "${directory}" && -f "${directory}/owner" && ! -L "${directory}/owner" ]] || return 1
    {
        IFS= read -r magic
        IFS= read -r owner_pid
    } < "${directory}/owner"
    [[ "${magic}" == "${match_owner_magic}" && "${owner_pid}" =~ ^[1-9][0-9]*$ ]] || return 1
    printf '%s\n' "${owner_pid}"
}

# Reclaims snapshots whose owning switcher is no longer running. Live or
# unrecognised directories are deliberately left untouched.
function cleanup_stale_match_directories() {
    local temporary_root="${TMPDIR:-/tmp}" directory owner_pid
    temporary_root="${temporary_root%/}"
    for directory in "${temporary_root}"/fzf-pane-switch.*; do
        [[ -e "${directory}" || -L "${directory}" ]] || continue
        owner_pid="$(match_owner_pid "${directory}" 2>/dev/null)" || continue
        if ! kill -0 "${owner_pid}" 2>/dev/null; then
            command rm -rf -- "${directory}"
        fi
    done
}

function write_match_state() {
    local directory="$1" state="$2" generation="${3:-}" temporary
    is_match_directory "${directory}" || return 1
    if [[ -z "${generation}" ]]; then
        generation="$(command cat "${directory}/generation" 2>/dev/null)"
    fi
    [[ "${generation}" =~ ^[1-9][0-9]*$ ]] || return 1
    temporary="$(mktemp "${directory}/state.${generation}.XXXXXX")" || return 1
    if ! printf '%s\n' "${state}" > "${temporary}" ||
        ! mv "${temporary}" "${directory}/state.${generation}"; then
        command rm -f -- "${temporary}"
        return 1
    fi
}

function current_match_generation() {
    local directory="$1" generation
    is_match_directory "${directory}" || return 1
    generation="$(command cat "${directory}/generation" 2>/dev/null)"
    [[ "${generation}" =~ ^[1-9][0-9]*$ ]] || return 1
    printf '%s\n' "${generation}"
}

function current_match_state() {
    local directory="$1" generation state
    generation="$(current_match_generation "${directory}")" || return 1
    state="$(command cat "${directory}/state.${generation}" 2>/dev/null)" || {
        printf 'fallback\n'
        return
    }
    if [[ "${state}" == indexing || "${state}" == refreshing ]] &&
        [[ -f "${directory}/index.${generation}" && ! -L "${directory}/index.${generation}" ]]; then
        printf 'ready\n'
    else
        printf '%s\n' "${state}"
    fi
}

# A missing state file is deliberately interpreted as fallback. Removing an
# unpublishable state prevents a stale indexing/refreshing value from keeping
# Enter guarded when capture has already failed.
function mark_match_fallback() {
    local directory="$1" generation="$2"
    if ! write_match_state "${directory}" fallback "${generation}"; then
        command rm -f -- "${directory}/state.${generation}"
    fi
}

# Returns the newest completed index at or before the current generation. This
# keeps the previous content snapshot available while a refresh is capturing.
function current_match_index() {
    local directory="$1" generation="$2" candidate candidate_generation newest=0
    for candidate in "${directory}"/index.*; do
        [[ -f "${candidate}" && ! -L "${candidate}" ]] || continue
        candidate_generation="${candidate##*.}"
        [[ "${candidate_generation}" =~ ^[1-9][0-9]*$ ]] || continue
        if (( candidate_generation <= generation && candidate_generation > newest )); then
            newest="${candidate_generation}"
        fi
    done
    (( newest > 0 )) || return 1
    printf '%s/index.%s\n' "${directory}" "${newest}"
}

# Removes generations older than the newly published snapshot. A future
# generation is never touched, even if it started during cleanup.
function cleanup_older_match_generations() {
    local directory="$1" generation="$2" candidate suffix
    for candidate in "${directory}"/metadata.* "${directory}"/metadata-search.* \
        "${directory}"/index.* "${directory}"/state.*; do
        [[ -e "${candidate}" || -L "${candidate}" ]] || continue
        suffix="${candidate##*.}"
        [[ "${suffix}" =~ ^[1-9][0-9]*$ ]] || continue
        if (( suffix < generation )); then
            command rm -f -- "${candidate}"
        fi
    done
}

function match_list_label() {
    if [[ "${FZF_PANE_SWITCH_LAYOUT:-one-row}" == 'tree' ]]; then
        printf 'Targets'
    else
        printf 'Panes'
    fi
}

# Describes the current content-index state and whether the focused result is
# present only because its hidden pane content matched the query.
function current_match_list_label() {
    local directory="$1" state label
    is_match_directory "${directory}" || return 1
    state="$(current_match_state "${directory}" 2>/dev/null)"
    label="$(match_list_label)"
    case "${state}" in
        indexing | refreshing)
            printf '%s · Indexing content…\n' "${label}"
            ;;
        fallback)
            printf '%s · Content unavailable\n' "${label}"
            ;;
        *)
            if [[ "${FZF_RAW:-1}" == 0 ]] && (( ${FZF_TOTAL_COUNT:-0} > 0 )); then
                printf '%s · Pane content match\n' "${label}"
            else
                printf '%s\n' "${label}"
            fi
            ;;
    esac
}

# A worker captures one quarter of the targets into generation-private files.
# Four workers keep tmux server requests bounded without spawning a normalizer
# for every pane.
function capture_match_index_worker() {
    local directory="$1" generation="$2" worker_index="$3" worker_count="$4" line_count="$5"
    local record target record_index=0

    while IFS= read -r -d '' record; do
        if (( record_index % worker_count != worker_index )); then
            ((record_index += 1))
            continue
        fi
        target="${record%%"${field_separator}"*}"
        printf '%s%s' "${record}" "${field_separator}"
        if ! tmux capture-pane -p -S "-${line_count}" -t "${target}" 2>/dev/null; then
            return 1
        fi
        printf '%s' "${record_separator}"
        ((record_index += 1))
    done < "${directory}/metadata-search.${generation}"
}

# Normalizes every captured pane and assembles the complete index in one awk
# process. Worker streams are framed with reserved control separators that are
# removed from searchable content before publication.
function normalize_match_captures() {
    local line_count="$1"
    shift
    awk \
        -v limit="${line_count}" \
        -v field_separator="${field_separator}" \
        -v record_separator="${record_separator}" '
        BEGIN {
            RS = record_separator
            ORS = ""
        }
        {
            remainder = $0
            separator_at = index(remainder, field_separator)
            target = substr(remainder, 1, separator_at - 1)
            remainder = substr(remainder, separator_at + 1)
            separator_at = index(remainder, field_separator)
            node_type = substr(remainder, 1, separator_at - 1)
            remainder = substr(remainder, separator_at + 1)
            separator_at = index(remainder, field_separator)
            plain_display = substr(remainder, 1, separator_at - 1)
            remainder = substr(remainder, separator_at + 1)
            separator_at = index(remainder, field_separator)
            display = substr(remainder, 1, separator_at - 1)
            content = substr(remainder, separator_at + 1)

            for (line_number in lines) delete lines[line_number]
            line_count = split(content, captured_lines, "\n")
            last_non_empty = 0
            for (line_number = 1; line_number <= line_count; line_number++) {
                line = captured_lines[line_number]
                gsub(field_separator, " ", line)
                gsub(record_separator, " ", line)
                gsub(/[[:cntrl:]]/, " ", line)
                gsub(/[[:space:]]+/, " ", line)
                lines[line_number] = line
                if (line ~ /[^ ]/) last_non_empty = line_number
            }
            start = last_non_empty - limit + 1
            if (start < 1) start = 1
            for (line_number = start; line_number <= last_non_empty; line_number++) {
                if (lines[line_number] == "") continue
                printf "%s%s%s%s%s%s%s%s%s%c", \
                    target, field_separator, node_type, field_separator, \
                    plain_display, field_separator, lines[line_number], field_separator, display, 0
            }
        }
    ' "$@"
}

# Re-runs the current query and derives the label from the published state.
# This is shared by successful indexing and metadata-only fallback.
function match_index_actions() {
    local directory="$1" script_path quoted_script quoted_directory filter_command label_command
    script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    quoted_script="$(shell_quote "${script_path}")"
    quoted_directory="$(shell_quote "${directory}")"
    # This string is emitted as a new fzf action, so its query placeholder is
    # intentionally unescaped and is expanded when reload-sync executes.
    # fzf already starts Bash for actions. Sourcing the helper avoids launching
    # a second Bash process on every query and index completion.
    filter_command="source ${quoted_script} --match-filter ${quoted_directory} {q}"
    label_command="source ${quoted_script} --match-label ${quoted_directory}"
    printf 'reload-sync[%s]+transform-list-label[%s]\n' \
        "${filter_command}" "${label_command}"
}

# Builds an invocation snapshot and returns fzf actions that publish it. The
# generation check prevents an older asynchronous refresh from winning a race.
function build_match_index() {
    local directory="$1" line_count="${2:-30}" generation worker pid status=0
    local next_index
    local -a pids=() worker_files=()

    is_match_directory "${directory}" || return 1
    [[ "${line_count}" =~ ^[1-9][0-9]*$ ]] || line_count=30
    generation="$(command cat "${directory}/generation" 2>/dev/null)"
    if [[ ! "${generation}" =~ ^[0-9]+$ ]]; then
        write_match_state "${directory}" fallback "${generation}"
        printf 'change-list-label(%s · Content unavailable)\n' "$(match_list_label)"
        return 0
    fi
    next_index="${directory}/index.${generation}.next"

    for worker in 0 1 2 3; do
        worker_files+=("${directory}/capture.${generation}.${worker}")
        capture_match_index_worker "${directory}" "${generation}" "${worker}" 4 "${line_count}" \
            > "${worker_files[worker]}" &
        pids+=("$!")
    done
    for pid in "${pids[@]}"; do
        wait "${pid}" || status=1
    done

    if [[ ${status} -ne 0 ]]; then
        command rm -f "${worker_files[@]}" "${next_index}"
        mark_match_fallback "${directory}" "${generation}"
        match_index_actions "${directory}"
        return 0
    fi

    if ! normalize_match_captures "${line_count}" "${worker_files[@]}" > "${next_index}"; then
        command rm -f "${worker_files[@]}" "${next_index}"
        mark_match_fallback "${directory}" "${generation}"
        match_index_actions "${directory}"
        return 0
    fi
    command rm -f "${worker_files[@]}"
    if [[ "$(command cat "${directory}/generation" 2>/dev/null)" != "${generation}" ]]; then
        command rm -f "${next_index}"
        return 0
    fi
    if ! mv "${next_index}" "${directory}/index.${generation}"; then
        command rm -f "${next_index}"
        mark_match_fallback "${directory}" "${generation}"
        match_index_actions "${directory}"
        return 0
    fi
    if [[ "$(command cat "${directory}/generation" 2>/dev/null)" != "${generation}" ]]; then
        command rm -f "${directory}/index.${generation}"
        return 0
    fi
    # The completed index is authoritative if publishing the ready marker
    # fails; current_match_state derives ready from its presence.
    write_match_state "${directory}" ready "${generation}" || true
    cleanup_older_match_generations "${directory}" "${generation}"

    match_index_actions "${directory}"
}

# Rebuilds visible records immediately while retaining the previous content
# snapshot until its replacement has finished capturing.
function refresh_match_records() {
    local directory="$1" generation temporary search_temporary generation_temporary
    is_match_directory "${directory}" || return 1
    generation="$(command cat "${directory}/generation" 2>/dev/null)"
    [[ "${generation}" =~ ^[0-9]+$ ]] || generation=0
    ((generation += 1))
    temporary="$(mktemp "${directory}/metadata.${generation}.XXXXXX")" || return 1
    search_temporary="$(mktemp "${directory}/metadata-search.${generation}.XXXXXX")" || {
        command rm -f "${temporary}"
        return 1
    }
    if ! generate_match_record_files "${FZF_PANE_SWITCH_LAYOUT:-one-row}" \
        "${FZF_PANE_SWITCH_PANE_FORMAT:?missing pane format}" \
        "${temporary}" "${search_temporary}"; then
        command rm -f "${temporary}" "${search_temporary}"
        return 1
    fi
    if ! mv "${temporary}" "${directory}/metadata.${generation}" ||
        ! mv "${search_temporary}" "${directory}/metadata-search.${generation}" ||
        ! write_match_state "${directory}" refreshing "${generation}"; then
        command rm -f "${temporary}" "${search_temporary}" \
            "${directory}/metadata.${generation}" \
            "${directory}/metadata-search.${generation}" \
            "${directory}/state.${generation}"
        return 1
    fi
    generation_temporary="$(mktemp "${directory}/generation.XXXXXX")" || {
        command rm -f "${directory}/metadata.${generation}" \
            "${directory}/metadata-search.${generation}" \
            "${directory}/state.${generation}"
        return 1
    }
    if ! printf '%s\n' "${generation}" > "${generation_temporary}" ||
        ! mv "${generation_temporary}" "${directory}/generation"; then
        command rm -f "${generation_temporary}" \
            "${directory}/metadata.${generation}" \
            "${directory}/metadata-search.${generation}" \
            "${directory}/state.${generation}"
        return 1
    fi
}

# Runs native fzf filtering on visible metadata first and captured content
# second, then strips the content field before records return to the UI.
function filter_match_records() {
    local directory="$1" query="${2-}" record target
    local generation state metadata_file metadata_search_file index_file='' matched_targets=$'\n'
    is_match_directory "${directory}" || return 1
    command -v fzf >/dev/null 2>&1 || return 1
    generation="$(current_match_generation "${directory}")" || return 1
    state="$(current_match_state "${directory}" 2>/dev/null)"
    metadata_file="${directory}/metadata.${generation}"
    metadata_search_file="${directory}/metadata-search.${generation}"

    if [[ -z "${query}" ]]; then
        command cat "${metadata_file}"
        return
    fi

    while IFS= read -r -d '' record; do
        target="${record%%"${field_separator}"*}"
        matched_targets+="${target}"$'\n'
        printf '%s\0' "${record}"
    done < <(
        FZF_DEFAULT_OPTS='' fzf --filter "${query}" --read0 --print0 \
            --delimiter "${field_separator}" --nth=3 \
            "--accept-nth={1}${field_separator}{2}${field_separator}{4}" \
            < "${metadata_search_file}" || true
    )

    if [[ "${state}" != fallback ]] &&
        index_file="$(current_match_index "${directory}" "${generation}")"; then
        while IFS= read -r -d '' record; do
            target="${record%%"${field_separator}"*}"
            case "${matched_targets}" in
                *$'\n'"${target}"$'\n'*) continue ;;
            esac
            printf '%s\0' "${record}"
            matched_targets+="${target}"$'\n'
        done < <(
            FZF_DEFAULT_OPTS='' fzf --filter "${query}" --read0 --print0 \
                --delimiter "${field_separator}" --nth=4 \
                "--accept-nth={1}${field_separator}{2}${field_separator}{5}" \
                < "${index_file}" |
                LC_ALL=C tr '\000' "${record_separator}" |
                awk -v record_separator="${record_separator}" \
                    -v field_separator="${field_separator}" '
                    BEGIN {
                        RS = record_separator
                        ORS = ""
                    }
                    {
                        separator_at = index($0, field_separator)
                        target = substr($0, 1, separator_at - 1)
                        if (!seen[target]++) printf "%s%c", $0, 0
                    }
                ' || true
        )
    fi
}

# Prevents a zero-result Enter from creating a window before deferred content
# matching has had a chance to produce a result.
function match_enter_action() {
    local directory="$1" state label
    is_match_directory "${directory}" || return 1
    state="$(current_match_state "${directory}" 2>/dev/null)"
    label="$(match_list_label)"
    case "${state}" in
        indexing | refreshing)
            if [[ "${FZF_RAW:-0}" != 1 ]]; then
                printf 'bell+change-list-label(%s · Still indexing content…)\n' "${label}"
                return
            fi
            ;;
    esac
    if (( ${FZF_TOTAL_COUNT:-${FZF_MATCH_COUNT:-0}} > 0 )); then
        printf 'accept\n'
    else
        printf 'accept-or-print-query\n'
    fi
}

function create_match_directory() {
    local temporary_root="${TMPDIR:-/tmp}"
    temporary_root="${temporary_root%/}"
    cleanup_stale_match_directories
    match_directory="$(umask 077 && mktemp -d "${temporary_root}/fzf-pane-switch.XXXXXX")" || return 1
    if ! printf '%s\n%s\n' "${match_owner_magic}" "$$" > "${match_directory}/owner" ||
        ! generate_match_record_files "${FZF_PANE_SWITCH_LAYOUT:-one-row}" \
            "${FZF_PANE_SWITCH_PANE_FORMAT:?missing pane format}" \
            "${match_directory}/metadata.1" "${match_directory}/metadata-search.1" ||
        ! printf 'indexing\n' > "${match_directory}/state.1" ||
        ! printf '1\n' > "${match_directory}/generation"; then
        cleanup_match_directory
        return 1
    fi
}

function cleanup_match_directory() {
    if [[ -n "${match_directory}" ]] && is_match_directory "${match_directory}"; then
        command rm -rf -- "${match_directory}"
    fi
    match_directory=''
}

# Quotes a value so it can be passed safely as one argument in a shell command.
function shell_quote() {
    local value="$1"
    value="${value//\'/\'\\\'\'}"
    printf "'%s'" "${value}"
}

# Displays a configuration error in tmux and returns a failure status.
function configuration_error() {
    tmux display-message "$1"
    return 1
}

# Reports whether a value is a supported named or six-digit hexadecimal colour.
function is_valid_colour() {
    local colour
    colour=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    if [[ "${colour}" =~ ^#[0-9a-f]{6}$ ]]; then
        return 0
    fi
    case "${colour}" in
        black | red | green | yellow | blue | magenta | cyan | white | bright-black | bright-red | bright-green | bright-yellow | bright-blue | bright-magenta | bright-cyan | bright-white | gray | grey)
            return 0
            ;;
    esac
    return 1
}

# Validates colour options that are not tied to a row position.
function validate_colours() {
    if [[ -n "${separator_colour}" ]] && ! is_valid_colour "${separator_colour}"; then
        configuration_error "@fzf_pane_switch_colour-separator has an invalid colour value: ${separator_colour}"
        return 1
    fi
}

# Validates that positional colours match their row fields and use supported styles.
function validate_row_colours() {
    local option="$1" row_format="$2" positional_colours="$3" colour
    local -a tokens=() colours=()
    [[ -z "${positional_colours}" ]] && return 0

    read -r -a tokens <<< "${row_format}"
    read -r -a colours <<< "${positional_colours}"
    if [[ ${#tokens[@]} -ne ${#colours[@]} ]]; then
        configuration_error "${option} must contain exactly ${#tokens[@]} entries"
        return 1
    fi

    for colour in "${colours[@]}"; do
        case "${colour}" in
            none) ;;
            *)
                if ! is_valid_positional_style "${colour}"; then
                    configuration_error "${option} has an invalid colour value: ${colour}"
                    return 1
                fi
                ;;
        esac
    done
}

# Reports whether a positional colour and attribute specification is valid.
function is_valid_positional_style() {
    local specification="$1" attribute normalised_attribute
    local -a parts=()
    if [[ "${specification}" == *: ]] || [[ "${specification}" == *::* ]]; then
        return 1
    fi

    IFS=':' read -r -a parts <<< "${specification}"
    if ! is_valid_colour "${parts[0]}"; then
        return 1
    fi

    for attribute in "${parts[@]:1}"; do
        normalised_attribute=$(printf '%s' "${attribute}" | tr '[:upper:]' '[:lower:]')
        case "${normalised_attribute}" in
            bold | dim | italic | underline | reverse | strikethrough) ;;
            *) return 1 ;;
        esac
    done
}

# Configures fzf, handles optional actions, and switches to the selected pane.
function select_pane() {
    local action_index footer_text pane pane_id node_type preview_command preview_window refresh_binding reload_command script_path
    local quoted_script quoted_directory filter_command index_command refresh_command enter_command label_command list_label
    local content_matching="${10}"
    local -a border_styling=(
        --input-border "--input-label= Search " --info=inline-right
        --list-border "--list-label= Panes "
        --preview-border "--preview-label= Preview "
        "--ghost=type to search..."
    ) footer_keys=('Enter') footer_labels=('Switch') fzf_args preview_args=()

    if [[ "${content_matching}" == 'true' ]]; then
        trap cleanup_match_directory EXIT HUP INT TERM
        if ! create_match_directory; then
            cleanup_match_directory
            trap - EXIT HUP INT TERM
            tmux display-message 'Pane-content matching unavailable; using pane details only'
            content_matching='false'
        fi
    fi

    if [[ "${5}" == 'tree' ]]; then
        border_styling[4]='--list-label= Targets '
    fi

    # Check if we're using the fzf preview pane
    if [[ "${1}" = 'true' ]]; then
        preview_window="${3}"
        if [[ "${9}" == 'hidden' ]]; then
            preview_window+=',hidden'
        fi
        preview_command="tmux capture-pane -ep -S -\$(( \${FZF_PREVIEW_LINES:-30} )) -t {1} | "
        # The awk below removes trailing empty/whitespace-only lines by finding the last non-empty line and printing up to that point
        preview_command+="awk '{a[NR]=\$0} END{for(i=NR;i>0;i--) if(a[i]~/[^ \\t]/){for(j=1;j<=i;j++) print a[j]; exit}}' | "
        preview_command+="tail -n \$(( \${FZF_PREVIEW_LINES:-30} ))"
        preview_args=(
            --preview "${preview_command}"
            "--preview-window=${preview_window}"
            --bind=ctrl-/:toggle-preview
        )
        footer_keys+=('Ctrl-/')
        footer_labels+=('Preview')
    fi

    if [[ "${7}" = 'true' ]]; then
        fzf_args+=('--bind=alt-j:jump,jump:accept')
        footer_keys+=('Alt-J')
        footer_labels+=('Jump')
    fi

    if [[ "${8}" = 'true' && "${content_matching}" != 'true' ]]; then
        script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
        reload_command="$(shell_quote "${script_path}") --records"
        refresh_binding="ctrl-r:track-current+reload-sync(${reload_command})"
        if [[ "${1}" = 'true' ]]; then
            refresh_binding+='+refresh-preview'
        fi
        fzf_args+=("--bind=${refresh_binding}" --id-nth=1)
        footer_keys+=('Ctrl-R')
        footer_labels+=('Refresh')
    fi

    # fzf runs the preview command through $SHELL, and the preview uses POSIX
    # syntax that shells like fish can't parse, so point it at a POSIX shell.
    local fzf_shell
    fzf_shell="$(command -v bash || command -v sh)"

    fzf_args+=(
        --reverse
        --tmux "${2}"
        --with-shell "${fzf_shell} -c"
    )
    if [[ "${content_matching}" == 'true' ]]; then
        script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
        quoted_script="$(shell_quote "${script_path}")"
        quoted_directory="$(shell_quote "${match_directory}")"
        filter_command="source ${quoted_script} --match-filter ${quoted_directory} {q}"
        index_command="source ${quoted_script} --match-index ${quoted_directory} \${FZF_PREVIEW_LINES:-30}"
        enter_command="source ${quoted_script} --match-enter ${quoted_directory}"
        label_command="source ${quoted_script} --match-label ${quoted_directory}"
        list_label='Panes'
        [[ "${5}" == 'tree' ]] && list_label='Targets'
        border_styling[4]="--list-label= ${list_label} · Indexing content… "
        fzf_args+=(
            --raw
            --no-sort
            --color=nomatch:-1:regular
            --read0
            --delimiter "${field_separator}"
            --with-nth=3
            "--accept-nth={1}${field_separator}{2}"
            --id-nth=1
            "--bind=change:reload-sync[${filter_command}]"
            "--bind=start:bg-transform[${index_command}]"
            "--bind=enter:transform[${enter_command}]"
            "--bind=focus,result:transform-list-label[${label_command}]"
        )
        if [[ "${5}" == 'tree' ]]; then
            fzf_args+=(--ansi)
        fi
        if [[ "${8}" == 'true' ]]; then
            refresh_command="source ${quoted_script} --match-refresh ${quoted_directory}"
            refresh_binding="ctrl-r:track-current+execute-silent[${refresh_command}]+transform-list-label[${label_command}]+bg-transform[${index_command}]"
            if [[ "${1}" == 'true' ]]; then
                refresh_binding+='+refresh-preview'
            fi
            fzf_args+=("--bind=${refresh_binding}")
            # Refresh rebuilds the pane-content snapshot, so keep it ahead of
            # optional actions that fzf may clip in a narrow list pane.
            footer_keys=('Enter' 'Ctrl-R' "${footer_keys[@]:1}")
            footer_labels=('Switch' 'Refresh' "${footer_labels[@]:1}")
        fi
    else
        fzf_args+=(--bind=enter:accept-or-print-query)
    fi

    if [[ "${6}" = 'true' ]]; then
        footer_text='  '
        for action_index in "${!footer_keys[@]}"; do
            if [[ "${footer_text}" != '  ' ]]; then
                footer_text+=$'  \033[2m·\033[0m  '
            fi
            footer_text+=$'\033[1m['
            footer_text+="${footer_keys[action_index]}"
            footer_text+=$']\033[0m \033[2m'
            footer_text+="${footer_labels[action_index]}"
            footer_text+=$'\033[0m'
        done
        footer_text+='  '
        border_styling+=("--footer=${footer_text}")
    fi

    if [[ "${content_matching}" != 'true' && "${5}" == 'tree' ]]; then
        fzf_args+=(--with-nth=3..)
    elif [[ "${content_matching}" != 'true' ]]; then
        fzf_args+=(--with-nth=2..)
    fi
    fzf_args+=("${border_styling[@]}" "${preview_args[@]}")

    if [[ "${4}" == *$'\033'* ]]; then
        fzf_args+=(--ansi)
    fi

    # Launch switcher
    if [[ "${content_matching}" == 'true' ]]; then
        if [[ "${5}" == 'two-row' ]]; then
            fzf_args+=(--multi-line --highlight-line --gap=1 "--gap-line=─")
        fi
        pane=$(command cat "${match_directory}/metadata.1" | fzf "${fzf_args[@]}")
        cleanup_match_directory
        trap - EXIT HUP INT TERM
    elif [[ "${5}" == 'two-row' ]]; then
        fzf_args+=(
            --read0
            --delimiter "${field_separator}"
            --accept-nth=1
            --multi-line
            --highlight-line
        )
        fzf_args+=(--gap=1 "--gap-line=─")
        pane=$(generate_records "${5}" "${4}" | fzf "${fzf_args[@]}")
    elif [[ "${5}" == 'tree' ]]; then
        fzf_args+=(
            --read0
            --delimiter "${field_separator}"
            "--accept-nth={1}${field_separator}{2}"
            --ansi
        )
        pane=$(generate_records "${5}" "${4}" | fzf "${fzf_args[@]}")
    else
        pane=$(generate_records "${5}" "${4}" | fzf "${fzf_args[@]}")
    fi

    if [[ ( "${5}" == 'tree' || "${content_matching}" == 'true' ) && "${pane}" == *"${field_separator}"* ]]; then
        pane_id="${pane%%"${field_separator}"*}"
        node_type="${pane#*"${field_separator}"}"
        if ! tmux display-message -p -t "${pane_id}" '#{pane_id}' >/dev/null 2>&1; then
            configuration_error "Selected ${node_type} target no longer exists: ${pane_id}"
            return
        fi
        tmux switch-client -t "${pane_id}"
        return
    fi

    # Set pane_id to first part of fzf output
    pane_id=$(echo "${pane}" | awk '{print $1}')

    # If pane_id is empty, exit without changing pane
    if [[ -z "${pane_id}" ]]; then
        return
    # Check if pane exists
    elif tmux has-session -t "${pane_id}" >/dev/null 2>&1; then
        # Found it! Let's switch.
        tmux switch-client -t "${pane_id}"
    else
        # Pane not found, let's create it.
        tmux command-prompt -b -p "Press ENTER to create a new window in the current session [${pane}]" "new-window -n \"${pane}\""
    fi
}

# Compares semantic-style versions: 1 means newer, 2 older, and 0 equal.
function vercomp() {
  local v1="$1"
  local v2="$2"

  # Split each version string into arrays using '.' as the delimiter
  IFS='.' read -r -a ver1 <<< "$v1"
  IFS='.' read -r -a ver2 <<< "$v2"

  # Compare major, minor, and patch components one by one
  for i in 0 1 2; do
    # Default to 0 if a component is missing (e.g., "1.2" becomes "1.2.0")
    local num1="${ver1[i]:-0}"
    local num2="${ver2[i]:-0}"

    # Compare the numeric values of the current component
    if (( num1 > num2 )); then
      return 1  # First version is newer
    elif (( num1 < num2 )); then
      return 2  # First version is older
    fi
  done

  return 0  # Versions are equal
}

# Check for required commands
command -v tmux >/dev/null 2>&1 || { echo "tmux not found"; exit 1; }

if [[ "${1:-}" == '--records' ]]; then
    generate_records "${FZF_PANE_SWITCH_LAYOUT:-one-row}" "${FZF_PANE_SWITCH_PANE_FORMAT:?missing pane format}"
    exit
fi

case "${1:-}" in
    --match-filter)
        filter_match_records "${2:?missing match directory}" "${3-}"
        exit
        ;;
    --match-index)
        build_match_index "${2:?missing match directory}" "${3:-30}"
        exit
        ;;
    --match-refresh)
        refresh_match_records "${2:?missing match directory}"
        exit
        ;;
    --match-enter)
        match_enter_action "${2:?missing match directory}"
        exit
        ;;
    --match-label)
        current_match_list_label "${2:?missing match directory}"
        exit
        ;;
esac

command -v fzf >/dev/null 2>&1 || { echo "fzf not found"; exit 1; }

fzf_version=$(fzf --version | awk '{print $1}')
required_fzf_version='0.71.0'
if [[ "${24-false}" == true ]]; then
    # fzf 0.73 fixed background transforms dropping reload payloads. Pane
    # matching relies on that path to apply a completed asynchronous index.
    required_fzf_version='0.73.0'
fi
vercomp "${required_fzf_version}" "${fzf_version}"
if [[ $? -eq 1 ]]; then
    if [[ "${24-false}" == true ]]; then
        tmux display-message "@fzf_pane_switch_preview-pane-match requires fzf 0.73.0 or later (found ${fzf_version})"
    else
        tmux display-message "fzf 0.71.0 or later is required (found ${fzf_version})"
    fi
    exit 1
fi

# Pane preview
preview_pane="${1}"
# FZF window position
fzf_window_position="${2}"
# fzf preview window position
fzf_preview_window_position="${3}"
list_panes_format="${4}"
layout="${5-one-row}"
two_row_style="${6-plain}"
row_1_format="${7-pane_title pane_current_command}"
row_2_format="${8-session_name window_name}"
value_separator="${9-│}"
list_panes_colours="${10:-}"
separator_colour="${11:-}"
row_1_colours="${12:-}"
row_2_colours="${13:-}"
footer="${14-false}"
jump_labels="${15-false}"
refresh="${16-false}"
preview_pane_start="${17-visible}"
preview_pane_match="${24-false}"

for boolean_option in footer jump_labels refresh preview_pane_match; do
    boolean_value="${!boolean_option}"
    case "${boolean_value}" in
        true | false) ;;
        *)
            option_name="${boolean_option//_/-}"
            configuration_error "@fzf_pane_switch_${option_name} must be true or false (got: ${boolean_value})"
            exit 1
            ;;
    esac
done

case "${preview_pane_start}" in
    visible | hidden) ;;
    *)
        configuration_error "@fzf_pane_switch_preview-pane-start must be visible or hidden (got: ${preview_pane_start})"
        exit 1
        ;;
esac

tree_session_format="${18-session_name}"
tree_window_format="${19-window_index window_name}"
tree_pane_format="${20-pane_index pane_title pane_current_command}"
tree_session_colours="${21:-}"
tree_window_colours="${22:-}"
tree_pane_colours="${23:-}"

case "${layout}" in
    one-row | two-row | tree) ;;
    *)
        configuration_error "@fzf_pane_switch_layout must be one-row, two-row, or tree (got: ${layout})"
        exit 1
        ;;
esac

if [[ "${layout}" == 'two-row' ]]; then
    case "${two_row_style}" in
        plain | indented | connected) ;;
        *)
            configuration_error "@fzf_pane_switch_two-row-style must be plain, indented, or connected (got: ${two_row_style})"
            exit 1
            ;;
    esac

    if [[ -z "${row_1_format//[[:space:]]/}" ]]; then
        configuration_error '@fzf_pane_switch_row-1-format must contain at least one tmux format'
        exit 1
    elif [[ -z "${row_2_format//[[:space:]]/}" ]]; then
        configuration_error '@fzf_pane_switch_row-2-format must contain at least one tmux format'
        exit 1
    elif [[ -z "${value_separator}" ]] ||
        [[ "${value_separator}" == *$'\n'* ]] ||
        [[ "${value_separator}" == *"${field_separator}"* ]] ||
        [[ "${value_separator}" == *"${record_separator}"* ]] ||
        [[ "${value_separator}" == *$'\033'* ]]; then
        configuration_error '@fzf_pane_switch_separator must be non-empty, single-line text without reserved control characters'
        exit 1
    fi

    if ! validate_row_colours '@fzf_pane_switch_row-1-colours' "${row_1_format}" "${row_1_colours}" ||
        ! validate_row_colours '@fzf_pane_switch_row-2-colours' "${row_2_format}" "${row_2_colours}"; then
        exit 1
    fi
fi

if [[ "${layout}" == 'tree' ]]; then
    for tree_level in session window pane; do
        tree_format_variable="tree_${tree_level}_format"
        tree_colour_variable="tree_${tree_level}_colours"
        tree_format="${!tree_format_variable}"
        tree_colours="${!tree_colour_variable}"
        if [[ -z "${tree_format//[[:space:]]/}" ]]; then
            configuration_error "@fzf_pane_switch_tree-${tree_level}-format must contain at least one tmux format"
            exit 1
        fi
        if ! validate_row_colours "@fzf_pane_switch_tree-${tree_level}-colours" "${tree_format}" "${tree_colours}"; then
            exit 1
        fi
    done
fi

if [[ "${layout}" != 'tree' ]] && ! validate_colours; then
    exit 1
fi

if [[ "${layout}" == 'one-row' ]] && ! validate_row_colours '@fzf_pane_switch_list-panes-colours' "${list_panes_format}" "${list_panes_colours}"; then
    exit 1
fi

if [[ "${layout}" == 'two-row' ]]; then
    pane_format="$(structured_pane_format "${two_row_style}" "${row_1_format}" "${row_2_format}" "${value_separator}")"
elif [[ "${layout}" == 'tree' ]]; then
    pane_format='tree'
    tree_session_tmux_format="$(format_tree_row "${tree_session_format}" "${tree_session_colours}")"
    tree_window_tmux_format="$(format_tree_row "${tree_window_format}" "${tree_window_colours}")"
    tree_pane_tmux_format="$(format_tree_row "${tree_pane_format}" "${tree_pane_colours}")"
else
    pane_format="$(format_one_row "${list_panes_format}" "${list_panes_colours}")"
fi

export FZF_PANE_SWITCH_LAYOUT="${layout}"
export FZF_PANE_SWITCH_PANE_FORMAT="${pane_format}"
export FZF_PANE_SWITCH_TREE_SESSION_FORMAT="${tree_session_tmux_format:-}"
export FZF_PANE_SWITCH_TREE_WINDOW_FORMAT="${tree_window_tmux_format:-}"
export FZF_PANE_SWITCH_TREE_PANE_FORMAT="${tree_pane_tmux_format:-}"

select_pane "${preview_pane}" "${fzf_window_position}" "${fzf_preview_window_position}" "${pane_format}" "${layout}" "${footer}" "${jump_labels}" "${refresh}" "${preview_pane_start}" "${preview_pane_match}"
