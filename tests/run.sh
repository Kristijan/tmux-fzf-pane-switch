#!/usr/bin/env bash

set -u

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_bin="${repo_dir}/tests/fixtures/bin"
test_tmp="$(mktemp -d)"
trap 'rm -r "${test_tmp}"' EXIT

failures=0

fail() {
    printf 'not ok - %s\n' "$1"
    failures=$((failures + 1))
}

pass() {
    printf 'ok - %s\n' "$1"
}

test_rejects_old_fzf() {
    local name='rejects fzf older than 0.71 before opening the pane list'
    local case_dir="${test_tmp}/old-fzf"
    local status
    mkdir -p "${case_dir}"

    PATH="${fixture_bin}:${PATH}" \
        FZF_STUB_VERSION='0.70.0' \
        FZF_STUB_ARGS="${case_dir}/fzf-args" \
        FZF_STUB_INPUT="${case_dir}/fzf-input" \
        TMUX_STUB_LOG="${case_dir}/tmux-log" \
        bash "${repo_dir}/select_pane.sh" \
            true 'center,70%,80%' 'right,,,nowrap' \
            'pane_id session_name window_name pane_title pane_current_command' \
            >"${case_dir}/stdout" 2>"${case_dir}/stderr"
    status=$?

    if [[ ${status} -eq 0 ]]; then
        fail "${name}: command succeeded"
    elif [[ -e "${case_dir}/fzf-input" ]]; then
        fail "${name}: fzf pane list was launched"
    elif ! command grep -q 'fzf 0.71.0 or later is required' "${case_dir}/tmux-log"; then
        fail "${name}: clear tmux error was not shown"
    else
        pass "${name}"
    fi
}

test_preserves_uncoloured_legacy_one_row() {
    local name='preserves the uncoloured legacy one-row representation'
    local case_dir="${test_tmp}/legacy-one-row"
    mkdir -p "${case_dir}"
    printf '%%1 %%1 work editor Title nvim \n' > "${case_dir}/expected-input"

    PATH="${fixture_bin}:${PATH}" \
        FZF_STUB_VERSION='0.71.0' \
        FZF_STUB_ARGS="${case_dir}/fzf-args" \
        FZF_STUB_INPUT="${case_dir}/fzf-input" \
        FZF_STUB_OUTPUT='%1' \
        TMUX_STUB_LOG="${case_dir}/tmux-log" \
        TMUX_STUB_EXPAND_FORMAT='true' \
        bash "${repo_dir}/select_pane.sh" \
            true 'center,70%,80%' 'right,,,nowrap' \
            'pane_id session_name window_name pane_title pane_current_command' \
            >"${case_dir}/stdout" 2>"${case_dir}/stderr"

    if ! command cmp -s "${case_dir}/expected-input" "${case_dir}/fzf-input"; then
        fail "${name}: pane-list bytes changed"
    elif command grep -Eq -- '^--(ansi|read0)$' "${case_dir}/fzf-args"; then
        fail "${name}: structured rendering flags leaked into legacy mode"
    else
        pass "${name}"
    fi
}

test_renders_plain_two_row_records() {
    local name='renders a plain two-row pane as one NUL-delimited fzf item'
    local case_dir="${test_tmp}/plain-two-row"
    local field_separator=$'\037'
    local record_separator=$'\036'
    local expected_input="${case_dir}/expected-input"
    mkdir -p "${case_dir}"

    printf '%%1%sTitle │ nvim\nwork │ editor\0' "${field_separator}" > "${expected_input}"

    PATH="${fixture_bin}:${PATH}" \
        FZF_STUB_VERSION='0.71.0' \
        FZF_STUB_ARGS="${case_dir}/fzf-args" \
        FZF_STUB_INPUT="${case_dir}/fzf-input" \
        FZF_STUB_OUTPUT='%1' \
        TMUX_STUB_LOG="${case_dir}/tmux-log" \
        TMUX_STUB_LIST_OUTPUT="%1${field_separator}Title │ nvim
work │ editor${record_separator}
" \
        bash "${repo_dir}/select_pane.sh" \
            true 'center,70%,80%' 'right,,,nowrap' \
            'pane_id session_name window_name pane_title pane_current_command' \
            'two-row' 'plain' \
            'pane_title pane_current_command' \
            'session_name window_name' '│' '' '' \
            >"${case_dir}/stdout" 2>"${case_dir}/stderr"

    if ! command cmp -s "${expected_input}" "${case_dir}/fzf-input"; then
        fail "${name}: rendered record differs"
    elif ! command grep -Fxq -- '--read0' "${case_dir}/fzf-args"; then
        fail "${name}: --read0 was not supplied"
    elif ! command grep -Fxq -- '--accept-nth=1' "${case_dir}/fzf-args"; then
        fail "${name}: --accept-nth=1 was not supplied"
    else
        pass "${name}"
    fi
}

test_rejects_unknown_layout() {
    local name='rejects an unknown layout without opening the pane list'
    local case_dir="${test_tmp}/unknown-layout"
    local status
    mkdir -p "${case_dir}"

    PATH="${fixture_bin}:${PATH}" \
        FZF_STUB_VERSION='0.71.0' \
        FZF_STUB_ARGS="${case_dir}/fzf-args" \
        FZF_STUB_INPUT="${case_dir}/fzf-input" \
        TMUX_STUB_LOG="${case_dir}/tmux-log" \
        bash "${repo_dir}/select_pane.sh" \
            true 'center,70%,80%' 'right,,,nowrap' \
            'pane_id session_name window_name pane_title pane_current_command' \
            'three-row' 'plain' \
            'pane_title pane_current_command' \
            'session_name window_name' '│' '' '' \
            >"${case_dir}/stdout" 2>"${case_dir}/stderr"
    status=$?

    if [[ ${status} -eq 0 ]]; then
        fail "${name}: command succeeded"
    elif [[ -e "${case_dir}/fzf-input" ]]; then
        fail "${name}: fzf pane list was launched"
    elif ! command grep -q '@fzf_pane_switch_layout.*one-row.*two-row' "${case_dir}/tmux-log"; then
        fail "${name}: option-specific tmux error was not shown"
    else
        pass "${name}"
    fi
}

test_renders_optional_two_row_styles() {
    local name='renders indented and connected two-row styles'
    local style case_dir expected
    local field_separator=$'\037'

    for style in indented connected; do
        case_dir="${test_tmp}/style-${style}"
        mkdir -p "${case_dir}"
        if [[ "${style}" == 'indented' ]]; then
            expected=$'● Title │ nvim\n  work │ editor'
        else
            expected=$'╭─ Title │ nvim\n╰─ work │ editor'
        fi
        printf '%%1%s%s\0' "${field_separator}" "${expected}" > "${case_dir}/expected-input"

        PATH="${fixture_bin}:${PATH}" \
            FZF_STUB_VERSION='0.71.0' \
            FZF_STUB_ARGS="${case_dir}/fzf-args" \
            FZF_STUB_INPUT="${case_dir}/fzf-input" \
            FZF_STUB_OUTPUT='%1' \
            TMUX_STUB_LOG="${case_dir}/tmux-log" \
            TMUX_STUB_EXPAND_FORMAT='true' \
            bash "${repo_dir}/select_pane.sh" \
                true 'center,70%,80%' 'right,,,nowrap' \
                'pane_id session_name window_name pane_title pane_current_command' \
                'two-row' "${style}" \
                'pane_title pane_current_command' \
                'session_name window_name' '│' '' '' \
                >"${case_dir}/stdout" 2>"${case_dir}/stderr"

        if ! command cmp -s "${case_dir}/expected-input" "${case_dir}/fzf-input"; then
            fail "${name}: ${style} output differs"
            return
        fi
    done
    pass "${name}"
}

test_colours_fields_and_separators_without_bleeding() {
    local name='colours two-row fields and separators with isolated ANSI sequences'
    local case_dir="${test_tmp}/coloured-two-row"
    local field_separator=$'\037'
    local reset=$'\033[0m'
    local expected_display
    mkdir -p "${case_dir}"

    expected_display=$'\033[38;2;137;180;250mTitle'
    expected_display+="${reset} "$'\033[38;2;108;112;134m│'
    expected_display+="${reset} "$'\033[92mnvim'
    expected_display+="${reset}"$'\n\033[33mwork'
    expected_display+="${reset} "$'\033[38;2;108;112;134m│'
    expected_display+="${reset} "$'\033[95meditor'
    expected_display+="${reset}"
    printf '%%1%s%s\0' "${field_separator}" "${expected_display}" > "${case_dir}/expected-input"

    PATH="${fixture_bin}:${PATH}" \
        FZF_STUB_VERSION='0.71.0' \
        FZF_STUB_ARGS="${case_dir}/fzf-args" \
        FZF_STUB_INPUT="${case_dir}/fzf-input" \
        FZF_STUB_OUTPUT='%1' \
        TMUX_STUB_LOG="${case_dir}/tmux-log" \
        TMUX_STUB_EXPAND_FORMAT='true' \
        bash "${repo_dir}/select_pane.sh" \
            true 'center,70%,80%' 'right,,,nowrap' \
            'pane_id session_name window_name pane_title pane_current_command' \
            'two-row' 'plain' \
            'pane_title pane_current_command' \
            'session_name window_name' '│' \
            '' '#6c7086' \
            '#89b4fa bright-green' 'yellow bright-magenta' \
            >"${case_dir}/stdout" 2>"${case_dir}/stderr"

    if ! command cmp -s "${case_dir}/expected-input" "${case_dir}/fzf-input"; then
        fail "${name}: ANSI record differs"
    elif ! command grep -Fxq -- '--ansi' "${case_dir}/fzf-args"; then
        fail "${name}: --ansi was not supplied"
    else
        pass "${name}"
    fi
}

test_colours_complex_row_values_by_position() {
    local name='colours complex two-row values by position with none support'
    local case_dir="${test_tmp}/positional-row-colours"
    local field_separator=$'\037'
    local reset=$'\033[0m'
    local expected_display
    mkdir -p "${case_dir}"

    expected_display=$'\033[34mTitle'
    expected_display+="${reset} │ nvim"
    expected_display+=$'\n\033[33mwork'
    expected_display+="${reset} │ editor │ "$'\033[38;2;137;180;250m~/projects/fzf-pane-switch.tmux'
    expected_display+="${reset}"
    printf '%%1%s%s\0' "${field_separator}" "${expected_display}" > "${case_dir}/expected-input"

    PATH="${fixture_bin}:${PATH}" \
        FZF_STUB_VERSION='0.71.0' \
        FZF_STUB_HELP='--gap-line[=STR]' \
        FZF_STUB_ARGS="${case_dir}/fzf-args" \
        FZF_STUB_INPUT="${case_dir}/fzf-input" \
        FZF_STUB_OUTPUT='%1' \
        TMUX_STUB_LOG="${case_dir}/tmux-log" \
        TMUX_STUB_EXPAND_FORMAT='true' \
        bash "${repo_dir}/select_pane.sh" \
            true 'center,70%,80%' 'right,,,nowrap' \
            'pane_id session_name window_name pane_title pane_current_command' \
            two-row plain 'pane_title pane_current_command' \
            'session_name window_name s|/Users/[^/]*|~|:pane_current_path' '│' \
            '' '' \
            'blue none' 'yellow none #89b4fa' \
            >"${case_dir}/stdout" 2>"${case_dir}/stderr"

    if ! command cmp -s "${case_dir}/expected-input" "${case_dir}/fzf-input"; then
        fail "${name}: positional ANSI record differs"
    else
        pass "${name}"
    fi
}

test_styles_positional_colours_with_ansi_attributes() {
    local name='styles positional colours with dim italic and combined ANSI attributes'
    local case_dir="${test_tmp}/positional-attributes"
    local field_separator=$'\037'
    local reset=$'\033[0m'
    local expected_display
    mkdir -p "${case_dir}"

    expected_display=$'\033[90m\033[2mTitle'
    expected_display+="${reset} │ "$'\033[32m\033[3mnvim'
    expected_display+="${reset}"$'\n\033[38;2;249;226;175m\033[1m\033[4mwork'
    expected_display+="${reset} │ editor"
    printf '%%1%s%s\0' "${field_separator}" "${expected_display}" > "${case_dir}/expected-input"

    PATH="${fixture_bin}:${PATH}" \
        FZF_STUB_VERSION='0.71.0' \
        FZF_STUB_HELP='--gap-line[=STR]' \
        FZF_STUB_ARGS="${case_dir}/fzf-args" \
        FZF_STUB_INPUT="${case_dir}/fzf-input" \
        FZF_STUB_OUTPUT='%1' \
        TMUX_STUB_LOG="${case_dir}/tmux-log" \
        TMUX_STUB_EXPAND_FORMAT='true' \
        bash "${repo_dir}/select_pane.sh" \
            true 'center,70%,80%' 'right,,,nowrap' \
            'pane_id session_name window_name pane_title pane_current_command' \
            two-row plain 'pane_title pane_current_command' \
            'session_name window_name' '│' '' '' \
            'gray:dim green:italic' '#f9e2af:bold:underline none' \
            >"${case_dir}/stdout" 2>"${case_dir}/stderr"

    if ! command cmp -s "${case_dir}/expected-input" "${case_dir}/fzf-input"; then
        fail "${name}: attributed ANSI record differs"
    else
        pass "${name}"
    fi
}

test_colours_one_row_without_changing_legacy_layout() {
    local name='colours one-row fields without changing legacy order or spacing'
    local case_dir="${test_tmp}/coloured-one-row"
    local expected
    mkdir -p "${case_dir}"

    expected=$'%1 %1 \033[38;2;137;180;250mTitle\033[0m nvim \n'
    printf '%s' "${expected}" > "${case_dir}/expected-input"

    PATH="${fixture_bin}:${PATH}" \
        FZF_STUB_VERSION='0.71.0' \
        FZF_STUB_ARGS="${case_dir}/fzf-args" \
        FZF_STUB_INPUT="${case_dir}/fzf-input" \
        FZF_STUB_OUTPUT='%1' \
        TMUX_STUB_LOG="${case_dir}/tmux-log" \
        TMUX_STUB_EXPAND_FORMAT='true' \
        bash "${repo_dir}/select_pane.sh" \
            true 'center,70%,80%' 'right,,,nowrap' \
            'pane_id pane_title pane_current_command' \
            'one-row' 'plain' \
            'pane_title pane_current_command' \
            'session_name window_name' '│' \
            'none #89b4fa none' '#6c7086' \
            >"${case_dir}/stdout" 2>"${case_dir}/stderr"

    if ! command cmp -s "${case_dir}/expected-input" "${case_dir}/fzf-input"; then
        fail "${name}: rendered row differs"
    elif ! command grep -Fxq -- '--ansi' "${case_dir}/fzf-args"; then
        fail "${name}: --ansi was not supplied"
    else
        pass "${name}"
    fi
}

test_tmux_entrypoint_passes_structured_configuration() {
    local name='tmux entrypoint binds the switcher with layout and colour configuration'
    local case_dir="${test_tmp}/tmux-entrypoint"
    mkdir -p "${case_dir}"

    PATH="${fixture_bin}:${PATH}" \
        TMUX_STUB_LOG="${case_dir}/tmux-log" \
        TMUX_STUB_LAYOUT='two-row' \
        TMUX_STUB_STYLE='connected' \
        TMUX_STUB_ROW_1='pane_title pane_current_command' \
        TMUX_STUB_ROW_2='session_name window_name' \
        TMUX_STUB_SEPARATOR='·' \
        TMUX_STUB_LIST_COLOURS='none #89b4fa none none none' \
        TMUX_STUB_ROW_1_COLOURS='#89b4fa none' \
        TMUX_STUB_ROW_2_COLOURS='#f9e2af none #89b4fa' \
        TMUX_STUB_SEPARATOR_COLOUR='bright-black' \
        TMUX_STUB_FOOTER='true' \
        TMUX_STUB_JUMP_LABELS='true' \
        TMUX_STUB_REFRESH='true' \
        TMUX_STUB_PREVIEW_PANE_START='hidden' \
        TMUX_STUB_TREE_SESSION='session_name session_windows' \
        TMUX_STUB_TREE_WINDOW='window_index window_name' \
        TMUX_STUB_TREE_PANE='pane_index pane_title' \
        TMUX_STUB_TREE_SESSION_COLOURS='blue none' \
        TMUX_STUB_TREE_WINDOW_COLOURS='yellow none' \
        TMUX_STUB_TREE_PANE_COLOURS='none magenta' \
        bash "${repo_dir}/select_pane.tmux"

    if ! command grep -q "two-row.*connected.*pane_title pane_current_command.*session_name window_name.*·" "${case_dir}/tmux-log"; then
        fail "${name}: layout arguments are missing from binding"
    elif ! command grep -q 'none #89b4fa none none none.*#89b4fa none.*#f9e2af none #89b4fa' "${case_dir}/tmux-log"; then
        fail "${name}: positional colour arguments are missing from binding"
    elif ! command grep -q 'bright-black' "${case_dir}/tmux-log"; then
        fail "${name}: separator colour is missing from binding"
    elif ! command grep -q "'true' 'true' 'true' 'hidden'" "${case_dir}/tmux-log"; then
        fail "${name}: action or preview-start setting is missing from binding"
    elif ! command grep -q "session_name session_windows.*pane_index pane_title.*blue none.*none magenta" "${case_dir}/tmux-log"; then
        fail "${name}: tree configuration is missing from binding"
    else
        pass "${name}"
    fi
}

test_tmux_entrypoint_configures_binding_mode() {
    local name='tmux entrypoint supports prefix and root binding modes'
    local case_dir="${test_tmp}/tmux-binding-mode"
    mkdir -p "${case_dir}"

    PATH="${fixture_bin}:${PATH}" \
        TMUX_STUB_LOG="${case_dir}/prefix-log" \
        bash "${repo_dir}/select_pane.tmux"

    PATH="${fixture_bin}:${PATH}" \
        TMUX_STUB_LOG="${case_dir}/root-log" \
        TMUX_STUB_BIND_KEY_MODE='root' \
        bash "${repo_dir}/select_pane.tmux"

    if ! command grep -q '^bind-key s run-shell ' "${case_dir}/prefix-log"; then
        fail "${name}: prefix mode was not the default"
    elif ! command grep -q '^bind-key -T root s run-shell ' "${case_dir}/root-log"; then
        fail "${name}: root mode did not bind in the root key table"
    else
        pass "${name}"
    fi
}

test_tmux_entrypoint_rejects_invalid_binding_mode() {
    local name='tmux entrypoint rejects an invalid binding mode'
    local case_dir="${test_tmp}/tmux-invalid-binding-mode" status
    mkdir -p "${case_dir}"

    PATH="${fixture_bin}:${PATH}" \
        TMUX_STUB_LOG="${case_dir}/tmux-log" \
        TMUX_STUB_BIND_KEY_MODE='global' \
        bash "${repo_dir}/select_pane.tmux"
    status=$?

    if [[ ${status} -eq 0 ]]; then
        fail "${name}: command succeeded"
    elif command grep -q '^bind-key ' "${case_dir}/tmux-log"; then
        fail "${name}: invalid mode registered a binding"
    elif ! command grep -q '@fzf_pane_switch_bind-key-mode must be prefix or root (got: global)' "${case_dir}/tmux-log"; then
        fail "${name}: clear tmux error was not shown"
    else
        pass "${name}"
    fi
}

assert_invalid_configuration() {
    local case_name="$1" expected_option="$2" layout="$3" style="$4"
    local row_1="$5" row_2="$6" separator="$7" list_colours="$8" separator_colour="$9"
    local row_1_colours="${10:-}" row_2_colours="${11:-}"
    local case_dir="${test_tmp}/invalid-${case_name}" status
    mkdir -p "${case_dir}"

    PATH="${fixture_bin}:${PATH}" \
        FZF_STUB_VERSION='0.71.0' \
        FZF_STUB_ARGS="${case_dir}/fzf-args" \
        FZF_STUB_INPUT="${case_dir}/fzf-input" \
        TMUX_STUB_LOG="${case_dir}/tmux-log" \
        bash "${repo_dir}/select_pane.sh" \
            true 'center,70%,80%' 'right,,,nowrap' \
            'pane_id session_name window_name pane_title pane_current_command' \
            "${layout}" "${style}" "${row_1}" "${row_2}" "${separator}" \
            "${list_colours}" "${separator_colour}" "${row_1_colours}" "${row_2_colours}" \
            >"${case_dir}/stdout" 2>"${case_dir}/stderr"
    status=$?

    [[ ${status} -ne 0 ]] && \
        [[ ! -e "${case_dir}/fzf-input" ]] && \
        command grep -q "${expected_option}" "${case_dir}/tmux-log"
}

test_rejects_invalid_structured_configuration() {
    local name='rejects invalid structured configuration before opening the pane list'

    if ! assert_invalid_configuration style '@fzf_pane_switch_two-row-style' \
        two-row stacked 'pane_title pane_current_command' 'session_name window_name' '│' '' ''; then
        fail "${name}: unknown style"
    elif ! assert_invalid_configuration row-1 '@fzf_pane_switch_row-1-format' \
        two-row plain '' 'session_name window_name' '│' '' ''; then
        fail "${name}: empty first row"
    elif ! assert_invalid_configuration separator '@fzf_pane_switch_separator' \
        two-row plain 'pane_title' 'session_name' $'bad\nseparator' '' ''; then
        fail "${name}: newline separator"
    elif ! assert_invalid_configuration short-hex '@fzf_pane_switch_list-panes-colours' \
        one-row plain 'pane_title' 'session_name' '│' '#abc none none none none' ''; then
        fail "${name}: three-digit hex"
    elif ! assert_invalid_configuration numeric '@fzf_pane_switch_list-panes-colours' \
        one-row plain 'pane_title' 'session_name' '│' '123 none none none none' ''; then
        fail "${name}: numeric colour"
    elif ! assert_invalid_configuration row-colour-count '@fzf_pane_switch_row-2-colours' \
        two-row plain 'pane_title' 'session_name window_name' '│' '' '' '' '#89b4fa'; then
        fail "${name}: positional colour count"
    elif ! assert_invalid_configuration row-colour-value '@fzf_pane_switch_row-1-colours' \
        two-row plain 'pane_title' 'session_name' '│' '' '' '#abc' 'none'; then
        fail "${name}: positional colour value"
    elif ! assert_invalid_configuration row-colour-attribute '@fzf_pane_switch_row-1-colours' \
        two-row plain 'pane_title' 'session_name' '│' '' '' 'gray:blink' 'none'; then
        fail "${name}: positional colour attribute"
    elif ! assert_invalid_configuration styled-none '@fzf_pane_switch_row-1-colours' \
        two-row plain 'pane_title' 'session_name' '│' '' '' 'none:dim' 'none'; then
        fail "${name}: styled none placeholder"
    else
        pass "${name}"
    fi
}

test_preserves_selection_and_unmatched_query_outcomes() {
    local name='switches selected panes and preserves raw unmatched queries'
    local output case_dir

    for output in '%1' 'new workspace'; do
        case_dir="${test_tmp}/outcome-${output// /-}"
        mkdir -p "${case_dir}"
        PATH="${fixture_bin}:${PATH}" \
            FZF_STUB_VERSION='0.71.0' \
            FZF_STUB_ARGS="${case_dir}/fzf-args" \
            FZF_STUB_INPUT="${case_dir}/fzf-input" \
            FZF_STUB_OUTPUT="${output}" \
            TMUX_STUB_LOG="${case_dir}/tmux-log" \
            TMUX_STUB_EXPAND_FORMAT='true' \
            bash "${repo_dir}/select_pane.sh" \
                false 'center,70%,80%' 'right,,,nowrap' \
                'pane_id session_name window_name pane_title pane_current_command' \
                one-row plain 'pane_title pane_current_command' \
                'session_name window_name' '│' '' '' \
                >"${case_dir}/stdout" 2>"${case_dir}/stderr"
    done

    if ! command grep -q 'switch-client -t %1' "${test_tmp}/outcome-%1/tmux-log"; then
        fail "${name}: selected pane was not switched"
    elif ! command grep -q 'new workspace.*new-window -n "new workspace"' \
        "${test_tmp}/outcome-new-workspace/tmux-log"; then
        fail "${name}: raw query was not preserved"
    else
        pass "${name}"
    fi
}

test_toggles_the_preview_without_a_footer() {
    local name='binds Ctrl-/ to toggle the preview without adding a footer'
    local case_dir="${test_tmp}/preview-toggle"
    mkdir -p "${case_dir}"

    PATH="${fixture_bin}:${PATH}" \
        FZF_STUB_VERSION='0.71.0' \
        FZF_STUB_ARGS="${case_dir}/fzf-args" \
        FZF_STUB_INPUT="${case_dir}/fzf-input" \
        FZF_STUB_OUTPUT='%1' \
        TMUX_STUB_LOG="${case_dir}/tmux-log" \
        TMUX_STUB_EXPAND_FORMAT='true' \
        bash "${repo_dir}/select_pane.sh" \
            true 'center,70%,80%' 'right,,,nowrap' \
            'pane_id session_name window_name pane_title pane_current_command' \
            >"${case_dir}/stdout" 2>"${case_dir}/stderr"

    if ! command grep -Fxq -- '--bind=ctrl-/:toggle-preview' "${case_dir}/fzf-args"; then
        fail "${name}: toggle binding was not supplied"
    elif command grep -Fxq -- '--bind=alt-j:jump,jump:accept' "${case_dir}/fzf-args"; then
        fail "${name}: disabled jump binding was supplied"
    elif command grep -q -- '^--bind=ctrl-r:track-current+reload-sync' "${case_dir}/fzf-args"; then
        fail "${name}: disabled refresh binding was supplied"
    elif command grep -q -- '^--footer=' "${case_dir}/fzf-args"; then
        fail "${name}: footer was supplied"
    else
        pass "${name}"
    fi
}

test_configures_the_initial_preview_visibility() {
    local name='starts an enabled preview visible or hidden and omits a disabled preview'
    local preview start case_dir status

    for preview in true false; do
        for start in visible hidden; do
            case_dir="${test_tmp}/preview-start-${preview}-${start}"
            mkdir -p "${case_dir}"
            PATH="${fixture_bin}:${PATH}" \
                FZF_STUB_VERSION='0.71.0' \
                FZF_STUB_ARGS="${case_dir}/fzf-args" \
                FZF_STUB_INPUT="${case_dir}/fzf-input" \
                FZF_STUB_OUTPUT='%1' \
                TMUX_STUB_LOG="${case_dir}/tmux-log" \
                TMUX_STUB_EXPAND_FORMAT='true' \
                bash "${repo_dir}/select_pane.sh" \
                    "${preview}" 'center,70%,80%' 'right,,,nowrap' \
                    'pane_id session_name window_name pane_title pane_current_command' \
                    one-row plain 'pane_title pane_current_command' \
                    'session_name window_name' '│' '' '' '' '' \
                    false false false "${start}" \
                    >"${case_dir}/stdout" 2>"${case_dir}/stderr"
        done
    done

    case_dir="${test_tmp}/preview-start-invalid"
    mkdir -p "${case_dir}"
    PATH="${fixture_bin}:${PATH}" \
        FZF_STUB_VERSION='0.71.0' \
        FZF_STUB_ARGS="${case_dir}/fzf-args" \
        FZF_STUB_INPUT="${case_dir}/fzf-input" \
        TMUX_STUB_LOG="${case_dir}/tmux-log" \
        bash "${repo_dir}/select_pane.sh" \
            true 'center,70%,80%' 'right,,,nowrap' \
            'pane_id session_name window_name pane_title pane_current_command' \
            one-row plain 'pane_title pane_current_command' \
            'session_name window_name' '│' '' '' '' '' \
            false false false collapsed \
            >"${case_dir}/stdout" 2>"${case_dir}/stderr"
    status=$?

    if ! command grep -Fxq -- '--preview-window=right,,,nowrap' \
        "${test_tmp}/preview-start-true-visible/fzf-args"; then
        fail "${name}: visible preview window was not supplied"
    elif ! command grep -Fxq -- '--preview-window=right,,,nowrap,hidden' \
        "${test_tmp}/preview-start-true-hidden/fzf-args"; then
        fail "${name}: hidden preview window was not supplied"
    elif command grep -Eq -- '^--preview$|^--preview-window=' \
        "${test_tmp}/preview-start-false-hidden/fzf-args"; then
        fail "${name}: disabled preview arguments were supplied"
    elif [[ ${status} -eq 0 ]] || [[ -e "${case_dir}/fzf-input" ]] || \
        ! command grep -q '@fzf_pane_switch_preview-pane-start' "${case_dir}/tmux-log"; then
        fail "${name}: invalid start value was not rejected"
    else
        pass "${name}"
    fi
}

test_optionally_shows_enabled_actions_in_the_footer() {
    local name='shows enabled actions only when the optional footer is enabled'
    local preview case_dir expected_footer

    for preview in true false; do
        case_dir="${test_tmp}/footer-${preview}"
        mkdir -p "${case_dir}"
        PATH="${fixture_bin}:${PATH}" \
            FZF_STUB_VERSION='0.71.0' \
            FZF_STUB_ARGS="${case_dir}/fzf-args" \
            FZF_STUB_INPUT="${case_dir}/fzf-input" \
            FZF_STUB_OUTPUT='%1' \
            TMUX_STUB_LOG="${case_dir}/tmux-log" \
            TMUX_STUB_EXPAND_FORMAT='true' \
            bash "${repo_dir}/select_pane.sh" \
                "${preview}" 'center,70%,80%' 'right,,,nowrap' \
                'pane_id session_name window_name pane_title pane_current_command' \
                one-row plain 'pane_title pane_current_command' \
                'session_name window_name' '│' '' '' '' '' true \
                >"${case_dir}/stdout" 2>"${case_dir}/stderr"
    done

    expected_footer=$'--footer=  \033[1m[Enter]\033[0m \033[2mSwitch\033[0m  \033[2m·\033[0m  \033[1m[Ctrl-/]\033[0m \033[2mPreview\033[0m  '
    if ! command grep -Fxq -- "${expected_footer}" \
        "${test_tmp}/footer-true/fzf-args"; then
        fail "${name}: styled preview action was not shown"
    elif ! command grep -Fxq -- $'--footer=  \033[1m[Enter]\033[0m \033[2mSwitch\033[0m  ' \
        "${test_tmp}/footer-false/fzf-args"; then
        fail "${name}: styled base action was not shown without preview"
    else
        pass "${name}"
    fi
}

test_optionally_jumps_directly_to_visible_panes() {
    local name='optionally binds jump labels across one-row and two-row layouts'
    local layout case_dir expected_footer

    for layout in one-row two-row; do
        case_dir="${test_tmp}/jump-${layout}"
        mkdir -p "${case_dir}"
        PATH="${fixture_bin}:${PATH}" \
            FZF_STUB_VERSION='0.71.0' \
            FZF_STUB_HELP='--gap-line[=STR]' \
            FZF_STUB_ARGS="${case_dir}/fzf-args" \
            FZF_STUB_INPUT="${case_dir}/fzf-input" \
            FZF_STUB_OUTPUT='%1' \
            TMUX_STUB_LOG="${case_dir}/tmux-log" \
            TMUX_STUB_EXPAND_FORMAT='true' \
            bash "${repo_dir}/select_pane.sh" \
                true 'center,70%,80%' 'right,,,nowrap' \
                'pane_id session_name window_name pane_title pane_current_command' \
                "${layout}" plain 'pane_title pane_current_command' \
                'session_name window_name' '│' '' '' '' '' true true \
                >"${case_dir}/stdout" 2>"${case_dir}/stderr"
    done

    expected_footer=$'--footer=  \033[1m[Enter]\033[0m \033[2mSwitch\033[0m  \033[2m·\033[0m  \033[1m[Ctrl-/]\033[0m \033[2mPreview\033[0m  \033[2m·\033[0m  \033[1m[Alt-J]\033[0m \033[2mJump\033[0m  '
    for layout in one-row two-row; do
        if ! command grep -Fxq -- '--bind=alt-j:jump,jump:accept' \
            "${test_tmp}/jump-${layout}/fzf-args"; then
            fail "${name}: ${layout} jump binding was not supplied"
            return
        elif ! command grep -Fxq -- "${expected_footer}" \
            "${test_tmp}/jump-${layout}/fzf-args"; then
            fail "${name}: ${layout} jump action was not shown in the footer"
            return
        fi
    done

    pass "${name}"
}

test_optionally_refreshes_panes_and_preview() {
    local name='optionally refreshes pane records and preview while tracking the pane ID'
    local layout preview case_dir expected_footer

    for layout in one-row two-row; do
        for preview in true false; do
            case_dir="${test_tmp}/refresh-${layout}-${preview}"
            mkdir -p "${case_dir}"
            PATH="${fixture_bin}:${PATH}" \
                FZF_STUB_VERSION='0.71.0' \
                FZF_STUB_HELP='--gap-line[=STR]' \
                FZF_STUB_ARGS="${case_dir}/fzf-args" \
                FZF_STUB_INPUT="${case_dir}/fzf-input" \
                FZF_STUB_OUTPUT='%1' \
                TMUX_STUB_LOG="${case_dir}/tmux-log" \
                TMUX_STUB_EXPAND_FORMAT='true' \
                bash "${repo_dir}/select_pane.sh" \
                    "${preview}" 'center,70%,80%' 'right,,,nowrap' \
                    'pane_id session_name window_name pane_title pane_current_command' \
                    "${layout}" plain 'pane_title pane_current_command' \
                    'session_name window_name' '│' '' '' '' '' true false true \
                    >"${case_dir}/stdout" 2>"${case_dir}/stderr"
        done
    done

    expected_footer=$'--footer=  \033[1m[Enter]\033[0m \033[2mSwitch\033[0m  \033[2m·\033[0m  \033[1m[Ctrl-/]\033[0m \033[2mPreview\033[0m  \033[2m·\033[0m  \033[1m[Ctrl-R]\033[0m \033[2mRefresh\033[0m  '
    for layout in one-row two-row; do
        if ! command grep -Eq -- "^--bind=ctrl-r:track-current\+reload-sync\('.*/select_pane\.sh' --records\)\+refresh-preview$" \
            "${test_tmp}/refresh-${layout}-true/fzf-args"; then
            fail "${name}: ${layout} preview refresh binding was not supplied"
            return
        elif ! command grep -Eq -- "^--bind=ctrl-r:track-current\+reload-sync\('.*/select_pane\.sh' --records\)$" \
            "${test_tmp}/refresh-${layout}-false/fzf-args"; then
            fail "${name}: ${layout} list-only refresh binding was not supplied"
            return
        elif ! command grep -Fxq -- '--id-nth=1' "${test_tmp}/refresh-${layout}-true/fzf-args"; then
            fail "${name}: ${layout} pane-ID tracking was not supplied"
            return
        elif ! command grep -Fxq -- "${expected_footer}" \
            "${test_tmp}/refresh-${layout}-true/fzf-args"; then
            fail "${name}: ${layout} refresh action was not shown in the footer"
            return
        fi
    done

    pass "${name}"
}

test_regenerates_records_for_fzf_reload() {
    local name='regenerates configured records through the internal reload command'
    local case_dir="${test_tmp}/reload-records"
    mkdir -p "${case_dir}"

    PATH="${fixture_bin}:${PATH}" \
        TMUX_STUB_LOG="${case_dir}/tmux-log" \
        TMUX_STUB_EXPAND_FORMAT='true' \
        FZF_PANE_SWITCH_LAYOUT='two-row' \
        FZF_PANE_SWITCH_PANE_FORMAT=$'#{pane_id}\037#{pane_title}\n#{session_name}\036' \
        bash "${repo_dir}/select_pane.sh" --records >"${case_dir}/records"

    if ! command grep -q 'list-panes -aF' "${case_dir}/tmux-log"; then
        fail "${name}: panes were not requested from tmux"
    elif [[ "$(command tr '\0' '|' < "${case_dir}/records")" != $'%1\037Title\nwork|' ]]; then
        fail "${name}: two-row record framing was not preserved"
    else
        pass "${name}"
    fi
}

test_separates_only_two_row_entries_with_a_horizontal_rule() {
    local name='adds horizontal rules between two-row entries only'
    local layout case_dir

    for layout in one-row two-row; do
        case_dir="${test_tmp}/gap-${layout}"
        mkdir -p "${case_dir}"
        PATH="${fixture_bin}:${PATH}" \
            FZF_STUB_VERSION='0.71.0' \
            FZF_STUB_HELP='--gap-line[=STR]' \
            FZF_STUB_ARGS="${case_dir}/fzf-args" \
            FZF_STUB_INPUT="${case_dir}/fzf-input" \
            FZF_STUB_OUTPUT='%1' \
            TMUX_STUB_LOG="${case_dir}/tmux-log" \
            TMUX_STUB_EXPAND_FORMAT='true' \
            bash "${repo_dir}/select_pane.sh" \
                true 'center,70%,80%' 'right,,,nowrap' \
                'pane_id session_name window_name pane_title pane_current_command' \
                "${layout}" plain 'pane_title pane_current_command' \
                'session_name window_name' '│' '' '' \
                >"${case_dir}/stdout" 2>"${case_dir}/stderr"
    done

    if ! command grep -Fxq -- '--gap=1' "${test_tmp}/gap-two-row/fzf-args" || \
        ! command grep -Fxq -- '--gap-line=─' "${test_tmp}/gap-two-row/fzf-args"; then
        fail "${name}: two-row gap arguments were not supplied"
    elif command grep -Eq -- '^--gap(=|-line)' "${test_tmp}/gap-one-row/fzf-args"; then
        fail "${name}: gap arguments leaked into one-row mode"
    else
        pass "${name}"
    fi
}

# Literal tmux IDs intentionally use '$' and expected records are appended incrementally.
# shellcheck disable=SC2016,SC2129
test_renders_and_switches_tree_nodes() {
    local name='renders searchable tree nodes and switches each target scope'
    local field_separator=$'\037' reset=$'\033[0m' dim=$'\033[2m'
    local case_dir="${test_tmp}/tree" expected
    mkdir -p "${case_dir}"

    printf 'session%s$1%sWork%sWork\nsession%s$2%sPersonal%sPersonal\n' \
        "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" > "${case_dir}/sessions"
    printf 'window%s$1%s@1%sProduction%s0 │ Production\nwindow%s$1%s@2%sNonProduction%s1 │ NonProduction\nwindow%s$2%s@3%sNotes%s0 │ Notes\n' \
        "${field_separator}" "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" "${field_separator}" > "${case_dir}/windows"
    printf 'pane%s@1%s%%1%s0 │ puppetserver │ bash\npane%s@2%s%%2%s0 │ puppetserver │ bash\npane%s@3%s%%3%s0 │ nvim │ nvim\n' \
        "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" > "${case_dir}/panes"

    expected="${case_dir}/expected-input"
    printf '$1%ssession%sWork\0' "${field_separator}" "${field_separator}" > "${expected}"
    printf '@1%swindow%s  ├─ 0 │ Production  %sWork%s\0' "${field_separator}" "${field_separator}" "${dim}" "${reset}" >> "${expected}"
    printf '%%1%spane%s  │  └─ 0 │ puppetserver │ bash  %sWork › Production%s\0' "${field_separator}" "${field_separator}" "${dim}" "${reset}" >> "${expected}"
    printf '@2%swindow%s  └─ 1 │ NonProduction  %sWork%s\0' "${field_separator}" "${field_separator}" "${dim}" "${reset}" >> "${expected}"
    printf '%%2%spane%s     └─ 0 │ puppetserver │ bash  %sWork › NonProduction%s\0' "${field_separator}" "${field_separator}" "${dim}" "${reset}" >> "${expected}"
    printf '$2%ssession%sPersonal\0' "${field_separator}" "${field_separator}" >> "${expected}"
    printf '@3%swindow%s  └─ 0 │ Notes  %sPersonal%s\0' "${field_separator}" "${field_separator}" "${dim}" "${reset}" >> "${expected}"
    printf '%%3%spane%s     └─ 0 │ nvim │ nvim  %sPersonal › Notes%s\0' "${field_separator}" "${field_separator}" "${dim}" "${reset}" >> "${expected}"

    PATH="${fixture_bin}:${PATH}" \
        FZF_STUB_VERSION='0.71.0' \
        FZF_STUB_ARGS="${case_dir}/fzf-args" \
        FZF_STUB_INPUT="${case_dir}/fzf-input" \
        FZF_STUB_OUTPUT="\$1${field_separator}session" \
        TMUX_STUB_LOG="${case_dir}/tmux-log" \
        TMUX_STUB_SESSIONS_OUTPUT="$(command cat "${case_dir}/sessions")"$'\n' \
        TMUX_STUB_WINDOWS_OUTPUT="$(command cat "${case_dir}/windows")"$'\n' \
        TMUX_STUB_LIST_OUTPUT="$(command cat "${case_dir}/panes")"$'\n' \
        bash "${repo_dir}/select_pane.sh" \
            true 'center,70%,80%' 'right,,,nowrap' \
            'pane_id session_name window_name pane_title pane_current_command' \
            tree plain 'pane_title pane_current_command' \
            'session_name window_name' '│' '' '' '' '' \
            false false true visible \
            session_name 'window_index window_name' 'pane_index pane_title pane_current_command' \
            '' '' '' >"${case_dir}/stdout" 2>"${case_dir}/stderr"

    if ! command cmp -s "${expected}" "${case_dir}/fzf-input"; then
        fail "${name}: rendered records differ"
    elif ! command grep -Fxq -- '--with-nth=3..' "${case_dir}/fzf-args"; then
        fail "${name}: hidden target metadata was displayed"
    elif ! command grep -q 'capture-pane .* -t {1}' "${case_dir}/fzf-args"; then
        fail "${name}: scope-aware preview target was not supplied"
    elif ! command grep -q '^--bind=ctrl-r:track-current+reload-sync' "${case_dir}/fzf-args" || \
        ! command grep -Fxq -- '--id-nth=1' "${case_dir}/fzf-args"; then
        fail "${name}: full-tree refresh was not configured"
    elif ! command grep -q 'switch-client -t \$1' "${case_dir}/tmux-log"; then
        fail "${name}: selected session was not switched"
    else
        pass "${name}"
    fi
}

# Literal tmux IDs intentionally use '$'.
# shellcheck disable=SC2016
test_joins_tree_records_by_stable_parent_ids() {
    local name='joins shuffled tree snapshots by stable parent IDs and skips orphans'
    local field_separator=$'\037' case_dir="${test_tmp}/tree-shuffled"
    mkdir -p "${case_dir}"

    printf 'session%s$1%sWork%sWork\nsession%s$2%sPersonal%sPersonal\n' \
        "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" > "${case_dir}/sessions"
    printf 'window%s$2%s@3%sNotes%s0 │ Notes\nwindow%s$1%s@1%sProduction%s0 │ Production\nwindow%s$9%s@9%sOrphan%s9 │ Orphan\nwindow%s$1%s@2%sNonProduction%s1 │ NonProduction\n' \
        "${field_separator}" "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" "${field_separator}" > "${case_dir}/windows"
    printf 'pane%s@2%s%%2%s0 │ puppetserver │ bash\npane%s@3%s%%3%s0 │ nvim │ nvim\npane%s@99%s%%9%s9 │ orphan │ sh\npane%s@1%s%%1%s0 │ puppetserver │ bash\n' \
        "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" > "${case_dir}/panes"

    PATH="${fixture_bin}:${PATH}" \
        FZF_STUB_VERSION='0.71.0' \
        FZF_STUB_ARGS="${case_dir}/fzf-args" \
        FZF_STUB_INPUT="${case_dir}/fzf-input" \
        FZF_STUB_OUTPUT="\$1${field_separator}session" \
        TMUX_STUB_LOG="${case_dir}/tmux-log" \
        TMUX_STUB_SESSIONS_OUTPUT="$(command cat "${case_dir}/sessions")"$'\n' \
        TMUX_STUB_WINDOWS_OUTPUT="$(command cat "${case_dir}/windows")"$'\n' \
        TMUX_STUB_LIST_OUTPUT="$(command cat "${case_dir}/panes")"$'\n' \
        bash "${repo_dir}/select_pane.sh" \
            false 'center,70%,80%' 'right,,,nowrap' \
            'pane_id session_name window_name pane_title pane_current_command' \
            tree plain 'pane_title pane_current_command' \
            'session_name window_name' '│' '' '' '' '' \
            false false false visible \
            session_name 'window_index window_name' 'pane_index pane_title pane_current_command' \
            '' '' '' >"${case_dir}/stdout" 2>"${case_dir}/stderr"

    if ! command cmp -s "${test_tmp}/tree/expected-input" "${case_dir}/fzf-input"; then
        fail "${name}: shuffled records changed the hierarchy or child order"
    elif command grep -aEq 'Orphan|orphan' "${case_dir}/fzf-input"; then
        fail "${name}: orphaned records were rendered"
    else
        pass "${name}"
    fi
}

# Literal tmux session IDs intentionally use '$'.
# shellcheck disable=SC2016
test_distinguishes_tree_targets_from_raw_queries() {
    local name='reports stale tree targets and preserves unmatched-query creation'
    local field_separator=$'\037' output case_dir

    for output in "\$1${field_separator}session" 'new workspace'; do
        case_dir="${test_tmp}/tree-outcome-${output// /-}"
        mkdir -p "${case_dir}"
        PATH="${fixture_bin}:${PATH}" \
            FZF_STUB_VERSION='0.71.0' \
            FZF_STUB_ARGS="${case_dir}/fzf-args" \
            FZF_STUB_INPUT="${case_dir}/fzf-input" \
            FZF_STUB_OUTPUT="${output}" \
            TMUX_STUB_LOG="${case_dir}/tmux-log" \
            TMUX_STUB_TARGET_EXISTS='false' \
            TMUX_STUB_SESSIONS_OUTPUT="session${field_separator}\$1${field_separator}Work${field_separator}Work"$'\n' \
            bash "${repo_dir}/select_pane.sh" \
                false 'center,70%,80%' 'right,,,nowrap' \
                'pane_id session_name window_name pane_title pane_current_command' \
                tree plain 'pane_title pane_current_command' \
                'session_name window_name' '│' '' '' '' '' \
                false false false visible \
                session_name 'window_index window_name' 'pane_index pane_title pane_current_command' \
                '' '' '' >"${case_dir}/stdout" 2>"${case_dir}/stderr"
    done

    if ! command grep -q 'Selected session target no longer exists: \$1' \
        "${test_tmp}/tree-outcome-\$1${field_separator}session/tmux-log"; then
        fail "${name}: stale target error was not shown"
    elif command grep -q 'new-window' "${test_tmp}/tree-outcome-\$1${field_separator}session/tmux-log"; then
        fail "${name}: stale target entered the create-window flow"
    elif ! command grep -q 'new workspace.*new-window -n "new workspace"' \
        "${test_tmp}/tree-outcome-new-workspace/tmux-log"; then
        fail "${name}: raw query was not preserved"
    else
        pass "${name}"
    fi
}

test_rejects_old_fzf
test_preserves_uncoloured_legacy_one_row
test_renders_plain_two_row_records
test_rejects_unknown_layout
test_renders_optional_two_row_styles
test_colours_fields_and_separators_without_bleeding
test_colours_complex_row_values_by_position
test_styles_positional_colours_with_ansi_attributes
test_colours_one_row_without_changing_legacy_layout
test_tmux_entrypoint_passes_structured_configuration
test_tmux_entrypoint_configures_binding_mode
test_tmux_entrypoint_rejects_invalid_binding_mode
test_rejects_invalid_structured_configuration
test_preserves_selection_and_unmatched_query_outcomes
test_toggles_the_preview_without_a_footer
test_configures_the_initial_preview_visibility
test_optionally_shows_enabled_actions_in_the_footer
test_optionally_jumps_directly_to_visible_panes
test_optionally_refreshes_panes_and_preview
test_regenerates_records_for_fzf_reload
test_separates_only_two_row_entries_with_a_horizontal_rule
test_renders_and_switches_tree_nodes
test_joins_tree_records_by_stable_parent_ids
test_distinguishes_tree_targets_from_raw_queries

if [[ ${failures} -ne 0 ]]; then
    exit 1
fi
