#!/usr/bin/env bats

# Each Bats test runs in its own process by design.
# shellcheck disable=SC2030,SC2031

bats_require_minimum_version 1.11.0
load test_helper

setup() {
    setup_test_environment
}

@test "tmux entrypoint binds the switcher with structured configuration" {
    export TMUX_STUB_LAYOUT='two-row'
    export TMUX_STUB_STYLE='connected'
    export TMUX_STUB_ROW_1='pane_title pane_current_command'
    export TMUX_STUB_ROW_2='session_name window_name'
    export TMUX_STUB_SEPARATOR='·'
    export TMUX_STUB_LIST_COLOURS='none #89b4fa none none none'
    export TMUX_STUB_ROW_1_COLOURS='#89b4fa none'
    export TMUX_STUB_ROW_2_COLOURS='#f9e2af none #89b4fa'
    export TMUX_STUB_SEPARATOR_COLOUR='bright-black'
    export TMUX_STUB_FOOTER='true'
    export TMUX_STUB_JUMP_LABELS='true'
    export TMUX_STUB_REFRESH='true'
    export TMUX_STUB_PREVIEW_PANE_START='hidden'
    export TMUX_STUB_TREE_SESSION='session_name session_windows'
    export TMUX_STUB_TREE_WINDOW='window_index window_name'
    export TMUX_STUB_TREE_PANE='pane_index pane_title'
    export TMUX_STUB_TREE_SESSION_COLOURS='blue none'
    export TMUX_STUB_TREE_WINDOW_COLOURS='yellow none'
    export TMUX_STUB_TREE_PANE_COLOURS='none magenta'

    run_tmux_entrypoint

    assert_status 0
    assert_file_contains "${TMUX_STUB_LOG}" \
        'two-row.*connected.*pane_title pane_current_command.*session_name window_name.*·'
    assert_file_contains "${TMUX_STUB_LOG}" \
        'none #89b4fa none none none.*#89b4fa none.*#f9e2af none #89b4fa'
    assert_file_contains "${TMUX_STUB_LOG}" 'bright-black'
    assert_file_contains "${TMUX_STUB_LOG}" \
        "'true' 'true' 'true' 'hidden'"
    assert_file_contains "${TMUX_STUB_LOG}" \
        'session_name session_windows.*pane_index pane_title.*blue none.*none magenta'
}

@test "tmux entrypoint uses prefix binding mode by default" {
    run_tmux_entrypoint

    assert_status 0
    assert_file_contains "${TMUX_STUB_LOG}" '^bind-key s run-shell '
}

@test "tmux entrypoint supports root binding mode" {
    export TMUX_STUB_BIND_KEY_MODE='root'

    run_tmux_entrypoint

    assert_status 0
    assert_file_contains "${TMUX_STUB_LOG}" '^bind-key -T root s run-shell '
}

@test "tmux entrypoint rejects an invalid binding mode" {
    export TMUX_STUB_BIND_KEY_MODE='global'

    run_tmux_entrypoint

    assert_status 1
    refute_file_contains "${TMUX_STUB_LOG}" '^bind-key '
    assert_file_contains "${TMUX_STUB_LOG}" \
        '@fzf_pane_switch_bind-key-mode must be prefix or root \(got: global\)'
}
