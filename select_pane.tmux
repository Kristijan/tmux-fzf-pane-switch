#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
default_bind_key='s'
default_preview_pane='true'
default_footer='false'
default_jump_labels='false'
default_refresh='false'
default_fzf_window_position='center,70%,80%'
default_fzf_preview_window_position='right,,,nowrap'
default_tmux_list_panes_format='pane_id session_name window_name pane_title pane_current_command'
default_layout='one-row'
default_two_row_style='plain'
default_row_1_format='pane_title pane_current_command'
default_row_2_format='session_name window_name'
default_separator='│'
default_row_colours=''

# User overridable options
tmux_bind_key="@fzf_pane_switch_bind-key"
tmux_preview_pane="@fzf_pane_switch_preview-pane"
tmux_footer="@fzf_pane_switch_footer"
tmux_jump_labels="@fzf_pane_switch_jump-labels"
tmux_refresh="@fzf_pane_switch_refresh"
tmux_fzf_window_position="@fzf_pane_switch_window-position"
tmux_fzf_preview_window_position="@fzf_pane_switch_preview-pane-position"
tmux_list_panes_format="@fzf_pane_switch_list-panes-format"
tmux_layout="@fzf_pane_switch_layout"
tmux_two_row_style="@fzf_pane_switch_two-row-style"
tmux_row_1_format="@fzf_pane_switch_row-1-format"
tmux_row_2_format="@fzf_pane_switch_row-2-format"
tmux_separator="@fzf_pane_switch_separator"
tmux_row_1_colours="@fzf_pane_switch_row-1-colours"
tmux_row_2_colours="@fzf_pane_switch_row-2-colours"
tmux_list_panes_colours="@fzf_pane_switch_list-panes-colours"

get_tmux_option() {
    local option="${1}"
    local default_value="${2}"
    local option_override
    option_override="$(tmux show-option -gqv "${option}")"
    if [ -z "${option_override}" ]; then
        echo "${default_value}"
    else
        echo "${option_override}"
    fi
}

tmux_option_is_set() {
    local wanted_option="$1" option
    while read -r option _; do
        if [ "${option}" = "${wanted_option}" ]; then
            return 0
        fi
    done < <(tmux show-options -g)
    return 1
}

get_tmux_option_allow_empty() {
    local option="$1" default_value="$2"
    if tmux_option_is_set "${option}"; then
        tmux show-option -gqv "${option}"
    else
        printf '%s\n' "${default_value}"
    fi
}

shell_quote() {
    local value="${1}"
    value="${value//\'/\'\\\'\'}"
    printf "'%s'" "${value}"
}

set_switch_pane_bindings() {
    local bind_key preview_pane footer jump_labels refresh fzf_window_position fzf_preview_window_position list_panes_format
    local layout two_row_style row_1_format row_2_format separator separator_colour
    local list_panes_colours row_1_colours row_2_colours
    local command argument
    bind_key="$(get_tmux_option "${tmux_bind_key}" "${default_bind_key}")"
    preview_pane="$(get_tmux_option "${tmux_preview_pane}" "${default_preview_pane}")"
    footer="$(get_tmux_option "${tmux_footer}" "${default_footer}")"
    jump_labels="$(get_tmux_option "${tmux_jump_labels}" "${default_jump_labels}")"
    refresh="$(get_tmux_option "${tmux_refresh}" "${default_refresh}")"
    fzf_window_position="$(get_tmux_option "${tmux_fzf_window_position}" "${default_fzf_window_position}")"
    fzf_preview_window_position="$(get_tmux_option "${tmux_fzf_preview_window_position}" "${default_fzf_preview_window_position}")"
    list_panes_format="$(get_tmux_option "${tmux_list_panes_format}" "${default_tmux_list_panes_format}")"
    layout="$(get_tmux_option_allow_empty "${tmux_layout}" "${default_layout}")"
    two_row_style="$(get_tmux_option_allow_empty "${tmux_two_row_style}" "${default_two_row_style}")"
    row_1_format="$(get_tmux_option_allow_empty "${tmux_row_1_format}" "${default_row_1_format}")"
    row_2_format="$(get_tmux_option_allow_empty "${tmux_row_2_format}" "${default_row_2_format}")"
    separator="$(get_tmux_option_allow_empty "${tmux_separator}" "${default_separator}")"
    row_1_colours="$(get_tmux_option_allow_empty "${tmux_row_1_colours}" "${default_row_colours}")"
    row_2_colours="$(get_tmux_option_allow_empty "${tmux_row_2_colours}" "${default_row_colours}")"
    list_panes_colours="$(get_tmux_option_allow_empty "${tmux_list_panes_colours}" "${default_row_colours}")"
    separator_colour="$(tmux show-option -gqv '@fzf_pane_switch_colour-separator')"

    command="$(shell_quote "${CURRENT_DIR}/select_pane.sh")"
    for argument in \
        "${preview_pane}" \
        "${fzf_window_position}" \
        "${fzf_preview_window_position}" \
        "${list_panes_format}" \
        "${layout}" \
        "${two_row_style}" \
        "${row_1_format}" \
        "${row_2_format}" \
        "${separator}" \
        "${list_panes_colours}" \
        "${separator_colour}" \
        "${row_1_colours}" \
        "${row_2_colours}" \
        "${footer}" \
        "${jump_labels}" \
        "${refresh}"; do
        command+=" $(shell_quote "${argument}")"
    done

    tmux bind-key "${bind_key}" run-shell "${command}"
}

set_switch_pane_bindings
