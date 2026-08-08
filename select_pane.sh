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

function positional_style_to_ansi() {
    local specification="$1" attribute
    local -a parts=()
    IFS=':' read -r -a parts <<< "${specification}"
    colour_to_ansi "${parts[0]}"
    for attribute in "${parts[@]:1}"; do
        attribute_to_ansi "${attribute}"
    done
}

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

function format_value_separator() {
    local separator="$1" ansi
    ansi="$(colour_to_ansi "${separator_colour}")"
    if [[ -n "${ansi}" ]]; then
        printf ' %s%s%s ' "${ansi}" "${separator}" "${ansi_reset}"
    else
        printf ' %s ' "${separator}"
    fi
}

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

function generate_structured_records() {
    local pane_format="$1" record

    while IFS= read -r -d "${record_separator}" record; do
        record="${record#$'\n'}"
        printf '%s\0' "${record}"
    done < <(tmux list-panes -aF "${pane_format}")
}

function configuration_error() {
    tmux display-message "$1"
    return 1
}

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

function validate_colours() {
    if [[ -n "${separator_colour}" ]] && ! is_valid_colour "${separator_colour}"; then
        configuration_error "@fzf_pane_switch_colour-separator has an invalid colour value: ${separator_colour}"
        return 1
    fi
}

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

function select_pane() {
    local fzf_version fzf_version_comparison
    local action_index footer_text pane pane_id preview_command
    local -a border_styling=() footer_keys=('Enter') footer_labels=('Switch') fzf_args preview_args=()

    # Setup border styling
    # Specific fzf releases have added additional styling options.
    fzf_version=$(fzf --version | awk '{print $1}')
    # - 0.58.0 or later, we can enable border styling
    vercomp '0.58.0' "${fzf_version}"
    fzf_version_comparison=$?
    if [[ ${fzf_version_comparison} -ne 1 ]]; then
        border_styling+=(--input-border "--input-label= Search " --info=inline-right)
        border_styling+=(--list-border "--list-label= Panes ")
        border_styling+=(--preview-border "--preview-label= Preview ")
    fi
    # - 0.61.0 or later, we can enable ghost text
    vercomp '0.61.0' "${fzf_version}"
    fzf_version_comparison=$?
    if [[ ${fzf_version_comparison} -ne 1 ]]; then
        border_styling+=("--ghost=type to search...")
    fi
    # Fallback to old border styling used in tmux-fzf-pane-switch release v1.1.2 if $border_styling is not set
    if [[ ${#border_styling[@]} -eq 0 ]]; then
        border_styling+=("--preview-label=pane preview")
    fi

    # Check if we're using the fzf preview pane
    if [[ "${1}" = 'true' ]]; then
        preview_command="tmux capture-pane -ep -S -\$(( \${FZF_PREVIEW_LINES:-30} )) -t {1} | "
        # The awk below removes trailing empty/whitespace-only lines by finding the last non-empty line and printing up to that point
        preview_command+="awk '{a[NR]=\$0} END{for(i=NR;i>0;i--) if(a[i]~/[^ \\t]/){for(j=1;j<=i;j++) print a[j]; exit}}' | "
        preview_command+="tail -n \$(( \${FZF_PREVIEW_LINES:-30} ))"
        preview_args=(
            --preview "${preview_command}"
            "--preview-window=${3}"
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

    # fzf runs the preview command through $SHELL, and the preview uses POSIX
    # syntax that shells like fish can't parse, so point it at a POSIX shell.
    local fzf_shell
    fzf_shell="$(command -v bash || command -v sh)"

    fzf_args+=(
        --reverse
        --tmux "${2}"
        --with-nth=2..
        --bind=enter:accept-or-print-query
        --with-shell "${fzf_shell} -c"
    )
    fzf_args+=("${border_styling[@]}" "${preview_args[@]}")

    if [[ "${4}" == *$'\033'* ]]; then
        fzf_args+=(--ansi)
    fi

    # Launch switcher
    if [[ "${5}" == 'two-row' ]]; then
        fzf_args+=(
            --read0
            --delimiter "${field_separator}"
            --accept-nth=1
            --multi-line
            --highlight-line
        )
        if fzf --help 2>/dev/null | grep -q -- '--gap-line'; then
            fzf_args+=(--gap=1 "--gap-line=─")
        fi
        pane=$(generate_structured_records "${4}" | fzf "${fzf_args[@]}")
    else
        pane=$(tmux list-panes -aF "${4}" | fzf "${fzf_args[@]}")
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
command -v fzf >/dev/null 2>&1 || { echo "fzf not found"; exit 1; }

fzf_version=$(fzf --version | awk '{print $1}')
vercomp '0.60.0' "${fzf_version}"
if [[ $? -eq 1 ]]; then
    tmux display-message "fzf 0.60.0 or later is required (found ${fzf_version})"
    exit 1
fi

# Pane preview
preview_pane="${1}"
# FZF window position
fzf_window_position="${2}"
# FZF previe window position
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

for boolean_option in footer jump_labels; do
    boolean_value="${!boolean_option}"
    case "${boolean_value}" in
        true | false) ;;
        *)
            if [[ "${boolean_option}" == 'footer' ]]; then
                configuration_error "@fzf_pane_switch_footer must be true or false (got: ${boolean_value})"
            else
                configuration_error "@fzf_pane_switch_jump-labels must be true or false (got: ${boolean_value})"
            fi
            exit 1
            ;;
    esac
done

case "${layout}" in
    one-row | two-row) ;;
    *)
        configuration_error "@fzf_pane_switch_layout must be one-row or two-row (got: ${layout})"
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

if ! validate_colours; then
    exit 1
fi

if ! validate_row_colours '@fzf_pane_switch_list-panes-colours' "${list_panes_format}" "${list_panes_colours}"; then
    exit 1
fi

if [[ "${layout}" == 'two-row' ]]; then
    pane_format="$(structured_pane_format "${two_row_style}" "${row_1_format}" "${row_2_format}" "${value_separator}")"
else
    pane_format="$(format_one_row "${list_panes_format}" "${list_panes_colours}")"
fi

select_pane "${preview_pane}" "${fzf_window_position}" "${fzf_preview_window_position}" "${pane_format}" "${layout}" "${footer}" "${jump_labels}"
