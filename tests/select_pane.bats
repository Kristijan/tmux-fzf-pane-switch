#!/usr/bin/env bats

# Each Bats test runs in its own process by design.
# shellcheck disable=SC2030,SC2031

bats_require_minimum_version 1.11.0
load test_helper

setup() {
    setup_test_environment
}

@test "launches the switcher from named configuration in any order" {
    printf '%%1 %%1 work editor Title nvim \n' > "${CASE_DIR}/expected-input"
    export TMUX_STUB_EXPAND_FORMAT='false'
    export TMUX_STUB_LIST_OUTPUT=$'%1 %1 work editor Title nvim \n'

    run_select_pane \
        --launch \
        --preview-pane-match false \
        --layout one-row \
        --list-panes-format \
        'pane_id session_name window_name pane_title pane_current_command' \
        --window-position 'center,70%,80%' \
        --preview-pane true \
        --preview-pane-position 'right,,,nowrap' \
        --two-row-style plain \
        --row-1-format 'pane_title pane_current_command' \
        --row-2-format 'session_name window_name' \
        --separator '│' \
        --list-panes-colours '' \
        --colour-separator '' \
        --row-1-colours '' \
        --row-2-colours '' \
        --footer false \
        --jump-labels false \
        --refresh false \
        --preview-pane-start visible \
        --tree-session-format session_name \
        --tree-window-format 'window_index window_name' \
        --tree-pane-format 'pane_index pane_title pane_current_command' \
        --tree-session-colours '' \
        --tree-window-colours '' \
        --tree-pane-colours ''

    assert_status 0
    assert_files_equal_bytes "${CASE_DIR}/expected-input" "${FZF_STUB_INPUT}"
    assert_file_has_line "${FZF_STUB_ARGS}" '--tmux'
    assert_file_has_line "${FZF_STUB_ARGS}" 'center,70%,80%'
    assert_file_has_line "${FZF_STUB_ARGS}" '--preview-window=right,,,nowrap'
}

@test "rejects an unknown named launch option" {
    run_select_pane --launch --unknown-option value

    assert_status 1
    refute_path_exists "${FZF_STUB_INPUT}"
    assert_file_contains "${TMUX_STUB_LOG}" \
        'Unknown launch option: --unknown-option'
}

@test "rejects a named launch option without a value" {
    run_select_pane --launch --preview-pane

    assert_status 1
    refute_path_exists "${FZF_STUB_INPUT}"
    assert_file_contains "${TMUX_STUB_LOG}" \
        'Launch option requires a value: --preview-pane'
}

@test "rejects a duplicate named launch option" {
    run_select_pane \
        --launch \
        --preview-pane true \
        --preview-pane false

    assert_status 1
    refute_path_exists "${FZF_STUB_INPUT}"
    assert_file_contains "${TMUX_STUB_LOG}" \
        'Launch option was provided more than once: --preview-pane'
}

@test "rejects incomplete named launch configuration" {
    run_select_pane --launch --preview-pane true

    assert_status 1
    refute_path_exists "${FZF_STUB_INPUT}"
    assert_file_contains "${TMUX_STUB_LOG}" \
        'Missing launch option: --window-position'
}

@test "rejects fzf older than 0.71 before opening the pane list" {
    export FZF_STUB_VERSION='0.70.0'

    run_select_pane \
        true 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command'

    assert_status 1
    refute_path_exists "${FZF_STUB_INPUT}"
    assert_file_contains "${TMUX_STUB_LOG}" \
        'fzf 0\.71\.0 or later is required'
}

@test "accepts positional configuration from a previously registered binding" {
    printf '%%1 %%1 work editor Title nvim \n' > "${CASE_DIR}/expected-input"
    export TMUX_STUB_EXPAND_FORMAT='false'
    export TMUX_STUB_LIST_OUTPUT=$'%1 %1 work editor Title nvim \n'

    run_select_pane \
        true 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command'

    assert_status 0
    assert_files_equal_bytes "${CASE_DIR}/expected-input" "${FZF_STUB_INPUT}"
    refute_file_contains "${FZF_STUB_ARGS}" '^--(ansi|read0)$'
}

@test "renders a plain two-row pane as one NUL-delimited fzf item" {
    local field_separator=$'\037' record_separator=$'\036'
    printf '%%1%sTitle │ nvim\nwork │ editor\0' "${field_separator}" \
        > "${CASE_DIR}/expected-input"
    export TMUX_STUB_LIST_OUTPUT="%1${field_separator}Title │ nvim
work │ editor${record_separator}
"

    run_select_pane \
        true 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command' \
        two-row plain \
        'pane_title pane_current_command' \
        'session_name window_name' '│' '' ''

    assert_status 0
    assert_files_equal_bytes "${CASE_DIR}/expected-input" "${FZF_STUB_INPUT}"
    assert_file_has_line "${FZF_STUB_ARGS}" '--read0'
    assert_file_has_line "${FZF_STUB_ARGS}" '--accept-nth=1'
}

@test "rejects an unknown layout before opening the pane list" {
    run_select_pane \
        true 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command' \
        three-row plain \
        'pane_title pane_current_command' \
        'session_name window_name' '│' '' ''

    assert_status 1
    refute_path_exists "${FZF_STUB_INPUT}"
    assert_file_contains "${TMUX_STUB_LOG}" \
        '@fzf_pane_switch_layout.*one-row.*two-row'
}

two_row_style_case() {
    local style="$1" expected="$2" field_separator=$'\037'
    printf '%%1%s%s\0' "${field_separator}" "${expected}" \
        > "${CASE_DIR}/expected-input"

    run_select_pane \
        true 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command' \
        two-row "${style}" \
        'pane_title pane_current_command' \
        'session_name window_name' '│' '' ''

    assert_status 0
    assert_files_equal_bytes "${CASE_DIR}/expected-input" "${FZF_STUB_INPUT}"
}

bats_test_function --description 'renders the indented two-row style' -- \
    two_row_style_case indented $'● Title │ nvim\n  work │ editor'
bats_test_function --description 'renders the connected two-row style' -- \
    two_row_style_case connected $'╭─ Title │ nvim\n╰─ work │ editor'

@test "colours two-row fields and separators with isolated ANSI sequences" {
    local field_separator=$'\037' reset=$'\033[0m' expected_display
    expected_display=$'\033[38;2;137;180;250mTitle'
    expected_display+="${reset} "$'\033[38;2;108;112;134m│'
    expected_display+="${reset} "$'\033[92mnvim'
    expected_display+="${reset}"$'\n\033[33mwork'
    expected_display+="${reset} "$'\033[38;2;108;112;134m│'
    expected_display+="${reset} "$'\033[95meditor'
    expected_display+="${reset}"
    printf '%%1%s%s\0' "${field_separator}" "${expected_display}" \
        > "${CASE_DIR}/expected-input"

    run_select_pane \
        true 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command' \
        two-row plain \
        'pane_title pane_current_command' \
        'session_name window_name' '│' \
        '' '#6c7086' \
        '#89b4fa bright-green' 'yellow bright-magenta'

    assert_status 0
    assert_files_equal_bytes "${CASE_DIR}/expected-input" "${FZF_STUB_INPUT}"
    assert_file_has_line "${FZF_STUB_ARGS}" '--ansi'
}

@test "colours complex two-row values by position with none support" {
    local field_separator=$'\037' reset=$'\033[0m' expected_display
    expected_display=$'\033[34mTitle'
    expected_display+="${reset} │ nvim"
    expected_display+=$'\n\033[33mwork'
    expected_display+="${reset} │ editor │ "$'\033[38;2;137;180;250m~/projects/fzf-pane-switch.tmux'
    expected_display+="${reset}"
    printf '%%1%s%s\0' "${field_separator}" "${expected_display}" \
        > "${CASE_DIR}/expected-input"
    export FZF_STUB_HELP='--gap-line[=STR]'

    run_select_pane \
        true 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command' \
        two-row plain \
        'pane_title pane_current_command' \
        'session_name window_name s|/Users/[^/]*|~|:pane_current_path' '│' \
        '' '' 'blue none' 'yellow none #89b4fa'

    assert_status 0
    assert_files_equal_bytes "${CASE_DIR}/expected-input" "${FZF_STUB_INPUT}"
}

@test "styles positional colours with dim italic and combined ANSI attributes" {
    local field_separator=$'\037' reset=$'\033[0m' expected_display
    expected_display=$'\033[90m\033[2mTitle'
    expected_display+="${reset} │ "$'\033[32m\033[3mnvim'
    expected_display+="${reset}"$'\n\033[38;2;249;226;175m\033[1m\033[4mwork'
    expected_display+="${reset} │ editor"
    printf '%%1%s%s\0' "${field_separator}" "${expected_display}" \
        > "${CASE_DIR}/expected-input"
    export FZF_STUB_HELP='--gap-line[=STR]'

    run_select_pane \
        true 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command' \
        two-row plain \
        'pane_title pane_current_command' \
        'session_name window_name' '│' '' '' \
        'gray:dim green:italic' '#f9e2af:bold:underline none'

    assert_status 0
    assert_files_equal_bytes "${CASE_DIR}/expected-input" "${FZF_STUB_INPUT}"
}

@test "colours one-row fields without changing legacy order or spacing" {
    printf '%s' $'%1 %1 \033[38;2;137;180;250mTitle\033[0m nvim \n' \
        > "${CASE_DIR}/expected-input"

    run_select_pane \
        true 'center,70%,80%' 'right,,,nowrap' \
        'pane_id pane_title pane_current_command' \
        one-row plain \
        'pane_title pane_current_command' \
        'session_name window_name' '│' \
        'none #89b4fa none' '#6c7086'

    assert_status 0
    assert_files_equal_bytes "${CASE_DIR}/expected-input" "${FZF_STUB_INPUT}"
    assert_file_has_line "${FZF_STUB_ARGS}" '--ansi'
}

invalid_configuration_case() {
    local expected_option="$1" layout="$2" style="$3"
    local row_1="$4" row_2="$5" separator="$6"
    local list_colours="$7" separator_colour="$8"
    local row_1_colours="${9:-}" row_2_colours="${10:-}"

    run_select_pane \
        true 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command' \
        "${layout}" "${style}" "${row_1}" "${row_2}" "${separator}" \
        "${list_colours}" "${separator_colour}" \
        "${row_1_colours}" "${row_2_colours}"

    assert_status 1
    refute_path_exists "${FZF_STUB_INPUT}"
    assert_file_contains "${TMUX_STUB_LOG}" "${expected_option}"
}

bats_test_function --description 'rejects an unknown two-row style' -- \
    invalid_configuration_case '@fzf_pane_switch_two-row-style' \
    two-row stacked 'pane_title pane_current_command' \
    'session_name window_name' '│' '' ''
bats_test_function --description 'rejects an empty first row' -- \
    invalid_configuration_case '@fzf_pane_switch_row-1-format' \
    two-row plain '' 'session_name window_name' '│' '' ''
bats_test_function --description 'rejects a newline separator' -- \
    invalid_configuration_case '@fzf_pane_switch_separator' \
    two-row plain pane_title session_name $'bad\nseparator' '' ''
bats_test_function --description 'rejects a three-digit list colour' -- \
    invalid_configuration_case '@fzf_pane_switch_list-panes-colours' \
    one-row plain pane_title session_name '│' '#abc none none none none' ''
bats_test_function --description 'rejects a numeric list colour' -- \
    invalid_configuration_case '@fzf_pane_switch_list-panes-colours' \
    one-row plain pane_title session_name '│' '123 none none none none' ''
bats_test_function --description 'rejects a positional row-colour count mismatch' -- \
    invalid_configuration_case '@fzf_pane_switch_row-2-colours' \
    two-row plain pane_title 'session_name window_name' '│' '' '' '' '#89b4fa'
bats_test_function --description 'rejects an invalid positional row colour' -- \
    invalid_configuration_case '@fzf_pane_switch_row-1-colours' \
    two-row plain pane_title session_name '│' '' '' '#abc' none
bats_test_function --description 'rejects an invalid positional colour attribute' -- \
    invalid_configuration_case '@fzf_pane_switch_row-1-colours' \
    two-row plain pane_title session_name '│' '' '' 'gray:blink' none
bats_test_function --description 'rejects a styled none placeholder' -- \
    invalid_configuration_case '@fzf_pane_switch_row-1-colours' \
    two-row plain pane_title session_name '│' '' '' 'none:dim' none

selection_outcome_case() {
    local selected="$1" expected="$2"
    export FZF_STUB_OUTPUT="${selected}"

    run_select_pane \
        false 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command' \
        one-row plain \
        'pane_title pane_current_command' \
        'session_name window_name' '│' '' ''

    assert_status 0
    assert_file_contains "${TMUX_STUB_LOG}" "${expected}"
}

bats_test_function --description 'switches a selected pane' -- \
    selection_outcome_case '%1' 'switch-client -t %1'
bats_test_function --description 'preserves a raw unmatched query as a window name' -- \
    selection_outcome_case 'new workspace' 'new workspace.*new-window -n "new workspace"'

@test "binds Ctrl-/ to toggle the preview without adding a footer" {
    run_select_pane \
        true 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command'

    assert_status 0
    assert_file_has_line "${FZF_STUB_ARGS}" '--bind=ctrl-/:toggle-preview'
    refute_file_contains "${FZF_STUB_ARGS}" '^--bind=alt-j:jump,jump:accept$'
    refute_file_contains "${FZF_STUB_ARGS}" \
        '^--bind=ctrl-r:track-current\+reload-sync'
    refute_file_contains "${FZF_STUB_ARGS}" '^--footer='
}

preview_visibility_case() {
    local preview="$1" start="$2" expected="$3"

    run_select_pane \
        "${preview}" 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command' \
        one-row plain \
        'pane_title pane_current_command' \
        'session_name window_name' '│' '' '' '' '' \
        false false false "${start}"

    assert_status 0
    case "${expected}" in
        visible)
            assert_file_has_line "${FZF_STUB_ARGS}" \
                '--preview-window=right,,,nowrap'
            ;;
        hidden)
            assert_file_has_line "${FZF_STUB_ARGS}" \
                '--preview-window=right,,,nowrap,hidden'
            ;;
        absent)
            refute_file_contains "${FZF_STUB_ARGS}" \
                '^--preview$|^--preview-window='
            ;;
    esac
}

bats_test_function --description 'enabled preview starts visible' -- \
    preview_visibility_case true visible visible
bats_test_function --description 'enabled preview starts hidden' -- \
    preview_visibility_case true hidden hidden
bats_test_function --description 'disabled preview omits visible preview arguments' -- \
    preview_visibility_case false visible absent
bats_test_function --description 'disabled preview omits hidden preview arguments' -- \
    preview_visibility_case false hidden absent

@test "rejects an invalid initial preview visibility" {
    run_select_pane \
        true 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command' \
        one-row plain \
        'pane_title pane_current_command' \
        'session_name window_name' '│' '' '' '' '' \
        false false false collapsed

    assert_status 1
    refute_path_exists "${FZF_STUB_INPUT}"
    assert_file_contains "${TMUX_STUB_LOG}" \
        '@fzf_pane_switch_preview-pane-start'
}

footer_case() {
    local preview="$1" expected_footer="$2"

    run_select_pane \
        "${preview}" 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command' \
        one-row plain \
        'pane_title pane_current_command' \
        'session_name window_name' '│' '' '' '' '' true

    assert_status 0
    assert_file_has_line "${FZF_STUB_ARGS}" "${expected_footer}"
}

bats_test_function --description 'footer shows switch and preview actions when preview is enabled' -- \
    footer_case true $'--footer=  \033[1m[Enter]\033[0m \033[2mSwitch\033[0m  \033[2m·\033[0m  \033[1m[Ctrl-/]\033[0m \033[2mPreview\033[0m  '
bats_test_function --description 'footer shows only the switch action when preview is disabled' -- \
    footer_case false $'--footer=  \033[1m[Enter]\033[0m \033[2mSwitch\033[0m  '

jump_labels_case() {
    local layout="$1"
    local expected_footer=$'--footer=  \033[1m[Enter]\033[0m \033[2mSwitch\033[0m  \033[2m·\033[0m  \033[1m[Ctrl-/]\033[0m \033[2mPreview\033[0m  \033[2m·\033[0m  \033[1m[Alt-J]\033[0m \033[2mJump\033[0m  '
    export FZF_STUB_HELP='--gap-line[=STR]'

    run_select_pane \
        true 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command' \
        "${layout}" plain \
        'pane_title pane_current_command' \
        'session_name window_name' '│' '' '' '' '' true true

    assert_status 0
    assert_file_has_line "${FZF_STUB_ARGS}" '--bind=alt-j:jump,jump:accept'
    assert_file_has_line "${FZF_STUB_ARGS}" "${expected_footer}"
}

bats_test_function --description 'one-row layout supports jump labels' -- \
    jump_labels_case one-row
bats_test_function --description 'two-row layout supports jump labels' -- \
    jump_labels_case two-row

refresh_case() {
    local layout="$1" preview="$2"
    local expected_footer=$'--footer=  \033[1m[Enter]\033[0m \033[2mSwitch\033[0m  \033[2m·\033[0m  \033[1m[Ctrl-/]\033[0m \033[2mPreview\033[0m  \033[2m·\033[0m  \033[1m[Ctrl-R]\033[0m \033[2mRefresh\033[0m  '
    export FZF_STUB_HELP='--gap-line[=STR]'

    run_select_pane \
        "${preview}" 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command' \
        "${layout}" plain \
        'pane_title pane_current_command' \
        'session_name window_name' '│' '' '' '' '' true false true

    assert_status 0
    if [[ "${preview}" == true ]]; then
        assert_file_contains "${FZF_STUB_ARGS}" \
            "^--bind=ctrl-r:track-current\\+reload-sync\\('.*/select_pane\\.sh' --records\\)\\+refresh-preview$"
        assert_file_has_line "${FZF_STUB_ARGS}" "${expected_footer}"
    else
        assert_file_contains "${FZF_STUB_ARGS}" \
            "^--bind=ctrl-r:track-current\\+reload-sync\\('.*/select_pane\\.sh' --records\\)$"
    fi
    assert_file_has_line "${FZF_STUB_ARGS}" '--id-nth=1'
}

bats_test_function --description 'one-row layout refreshes records and preview' -- \
    refresh_case one-row true
bats_test_function --description 'one-row layout refreshes records without preview' -- \
    refresh_case one-row false
bats_test_function --description 'two-row layout refreshes records and preview' -- \
    refresh_case two-row true
bats_test_function --description 'two-row layout refreshes records without preview' -- \
    refresh_case two-row false

@test "regenerates configured records through the internal reload command" {
    export FZF_PANE_SWITCH_LAYOUT='two-row'
    export FZF_PANE_SWITCH_PANE_FORMAT=$'#{pane_id}\037#{pane_title}\n#{session_name}\036'

    run bash -c 'bash "$1/select_pane.sh" --records > "$2/records"' \
        _ "${REPO_DIR}" "${CASE_DIR}"

    assert_status 0
    assert_file_contains "${TMUX_STUB_LOG}" 'list-panes -aF'
    assert_value_equal $'%1\037Title\nwork|' \
        "$(command tr '\0' '|' < "${CASE_DIR}/records")"
}

gap_case() {
    local layout="$1" expected="$2"
    export FZF_STUB_HELP='--gap-line[=STR]'

    run_select_pane \
        true 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command' \
        "${layout}" plain \
        'pane_title pane_current_command' \
        'session_name window_name' '│' '' ''

    assert_status 0
    if [[ "${expected}" == present ]]; then
        assert_file_has_line "${FZF_STUB_ARGS}" '--gap=1'
        assert_file_has_line "${FZF_STUB_ARGS}" '--gap-line=─'
    else
        refute_file_contains "${FZF_STUB_ARGS}" '^--gap(=|-line)'
    fi
}

bats_test_function --description 'two-row layout separates entries with a horizontal rule' -- \
    gap_case two-row present
bats_test_function --description 'one-row layout omits entry-separator arguments' -- \
    gap_case one-row absent
