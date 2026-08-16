#!/usr/bin/env bash

# Checks the effective fzf-pane-switch options in the running tmux server.

default_list_panes_format='pane_id session_name window_name pane_title pane_current_command'
default_row_1_format='pane_title pane_current_command'
default_row_2_format='session_name window_name'
default_tree_session_format='session_name'
default_tree_window_format='window_index window_name'
default_tree_pane_format='pane_index pane_title pane_current_command'

option_names=()
option_values=()
errors=()

pass_label='PASS'
fail_label='FAIL'
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    pass_label=$'\033[32mPASS\033[0m'
    fail_label=$'\033[31mFAIL\033[0m'
fi

configuration="$(tmux show-options -g 2>&1)"
tmux_status=$?
if [[ ${tmux_status} -ne 0 ]]; then
    printf '%s Unable to read the running tmux configuration.\n\n' "${fail_label}"
    printf 'Summary\n'
    printf -- '- tmux show-options -g failed: %s\n' "${configuration}"
    printf -- '  Fix: run this script while a tmux server is running and accessible.\n'
    exit 1
fi

while IFS=' ' read -r option_name option_value; do
    if [[ "${option_name}" == @fzf_pane_switch* ]]; then
        option_names+=("${option_name}")
        option_values+=("${option_value}")
        case "${option_name}" in
            @fzf_pane_switch_list-panes-format) list_panes_format="${option_value}" ;;
            @fzf_pane_switch_row-1-format) row_1_format="${option_value}" ;;
            @fzf_pane_switch_row-2-format) row_2_format="${option_value}" ;;
            @fzf_pane_switch_tree-session-format) tree_session_format="${option_value}" ;;
            @fzf_pane_switch_tree-window-format) tree_window_format="${option_value}" ;;
            @fzf_pane_switch_tree-pane-format) tree_pane_format="${option_value}" ;;
        esac
    fi
done <<< "${configuration}"

if [[ ${#option_names[@]} -eq 0 ]]; then
    printf '%s No options beginning with @fzf_pane_switch were found.\n\n' "${fail_label}"
    printf 'Summary\n'
    printf -- '- No plugin configuration was available to check.\n'
    printf -- '  Fix: configure or load fzf-pane-switch in the running tmux server, then rerun this script.\n'
    exit 1
fi

list_panes_format="${list_panes_format-${default_list_panes_format}}"
row_1_format="${row_1_format-${default_row_1_format}}"
row_2_format="${row_2_format-${default_row_2_format}}"
tree_session_format="${tree_session_format-${default_tree_session_format}}"
tree_window_format="${tree_window_format-${default_tree_window_format}}"
tree_pane_format="${tree_pane_format-${default_tree_pane_format}}"

append_error() {
    errors+=("$1")
}

validate_allowed_value() {
    local option_name="$1" option_value="$2" allowed_values="$3" allowed_value
    for allowed_value in ${allowed_values}; do
        [[ "${option_value}" == "${allowed_value}" ]] && return 0
    done
    append_error "${option_name}: invalid value '${option_value}'. Fix: set it to one of: ${allowed_values}."
    return 1
}

validate_positional_count() {
    local option_name="$1" option_value="$2" format_name="$3" format_value="$4"
    local -a colours=() fields=()
    [[ -z "${option_value}" ]] && return 0
    read -r -a colours <<< "${option_value}"
    read -r -a fields <<< "${format_value}"
    if [[ ${#colours[@]} -ne ${#fields[@]} ]]; then
        append_error "${option_name}: found ${#colours[@]} positional colours, but ${format_name} has ${#fields[@]} fields. Fix: set exactly ${#fields[@]} colour entries, using 'none' for any uncoloured position."
        return 1
    fi
    return 0
}

for ((index = 0; index < ${#option_names[@]}; index++)); do
    option_name="${option_names[index]}"
    option_value="${option_values[index]}"
    option_valid=true

    case "${option_name}" in
        @fzf_pane_switch_bind-key-mode)
            validate_allowed_value "${option_name}" "${option_value}" 'prefix root' || option_valid=false
            ;;
        @fzf_pane_switch_layout)
            validate_allowed_value "${option_name}" "${option_value}" 'one-row two-row tree' || option_valid=false
            ;;
        @fzf_pane_switch_two-row-style)
            validate_allowed_value "${option_name}" "${option_value}" 'plain indented connected' || option_valid=false
            ;;
        @fzf_pane_switch_preview-pane-start)
            validate_allowed_value "${option_name}" "${option_value}" 'visible hidden' || option_valid=false
            ;;
        @fzf_pane_switch_preview-pane | @fzf_pane_switch_footer | @fzf_pane_switch_jump-labels | @fzf_pane_switch_refresh)
            validate_allowed_value "${option_name}" "${option_value}" 'true false' || option_valid=false
            ;;
        @fzf_pane_switch_list-panes-colours)
            validate_positional_count "${option_name}" "${option_value}" '@fzf_pane_switch_list-panes-format' "${list_panes_format}" || option_valid=false
            ;;
        @fzf_pane_switch_row-1-colours)
            validate_positional_count "${option_name}" "${option_value}" '@fzf_pane_switch_row-1-format' "${row_1_format}" || option_valid=false
            ;;
        @fzf_pane_switch_row-2-colours)
            validate_positional_count "${option_name}" "${option_value}" '@fzf_pane_switch_row-2-format' "${row_2_format}" || option_valid=false
            ;;
        @fzf_pane_switch_tree-session-colours)
            validate_positional_count "${option_name}" "${option_value}" '@fzf_pane_switch_tree-session-format' "${tree_session_format}" || option_valid=false
            ;;
        @fzf_pane_switch_tree-window-colours)
            validate_positional_count "${option_name}" "${option_value}" '@fzf_pane_switch_tree-window-format' "${tree_window_format}" || option_valid=false
            ;;
        @fzf_pane_switch_tree-pane-colours)
            validate_positional_count "${option_name}" "${option_value}" '@fzf_pane_switch_tree-pane-format' "${tree_pane_format}" || option_valid=false
            ;;
        @fzf_pane_switch_bind-key | \
            @fzf_pane_switch_window-position | \
            @fzf_pane_switch_preview-pane-position | \
            @fzf_pane_switch_list-panes-format | \
            @fzf_pane_switch_row-1-format | \
            @fzf_pane_switch_row-2-format | \
            @fzf_pane_switch_separator | \
            @fzf_pane_switch_colour-separator | \
            @fzf_pane_switch_tree-session-format | \
            @fzf_pane_switch_tree-window-format | \
            @fzf_pane_switch_tree-pane-format)
            ;;
        *)
            append_error "${option_name}: unknown option. Fix: remove it with 'tmux set-option -gu ${option_name}' or replace it with a documented option name."
            option_valid=false
            ;;
    esac

    if [[ "${option_valid}" == true ]]; then
        printf '%s %s = %s\n' "${pass_label}" "${option_name}" "${option_value}"
    else
        printf '%s %s = %s\n' "${fail_label}" "${option_name}" "${option_value}"
    fi
done

if [[ ${#errors[@]} -eq 0 ]]; then
    printf '\nAll %s fzf-pane-switch options passed.\n' "${#option_names[@]}"
    exit 0
fi

printf '\nSummary: %s configuration error(s)\n' "${#errors[@]}"
for error in "${errors[@]}"; do
    printf -- '- %s\n' "${error}"
done
exit 1
