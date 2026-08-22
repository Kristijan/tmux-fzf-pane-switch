#!/usr/bin/env bats

# Each Bats test runs in its own process by design.
# shellcheck disable=SC2030,SC2031

bats_require_minimum_version 1.11.0
load test_helper

setup() {
    setup_test_environment
}

@test "configuration checker accepts names, predefined values, and positional colours" {
    export TMUX_STUB_SHOW_OPTIONS=$'status-keys vi\n@fzf_pane_switch_layout tree\n@fzf_pane_switch_preview-pane true\n@fzf_pane_switch_preview-pane-match true\n@fzf_pane_switch_row-2-colours blue none\n@fzf_pane_switch_tree-pane-format pane_index pane_title\n@fzf_pane_switch_tree-pane-colours cyan magenta\n'

    run_configuration_checker

    assert_status 0
    assert_output_line_count '^PASS @fzf_pane_switch' 6
    assert_output_contains 'All 6 fzf-pane-switch options passed.'
}

@test "configuration checker reports every invalid option with a fix" {
    export TMUX_STUB_SHOW_OPTIONS=$'@fzf_pane_switch_bind-key-mode global\n@fzf_pane_switch_row-1-format pane_title pane_current_command pane_pid\n@fzf_pane_switch_row-1-colours blue green\n@fzf_pane_switch_typo true\n'

    run_configuration_checker

    assert_status 1
    assert_output_line_count '^FAIL @fzf_pane_switch' 3
    assert_output_contains 'set it to one of: prefix root'
    assert_output_contains 'set exactly 3 colour entries'
    assert_output_contains 'unknown option'
}

@test "configuration checker rejects a running tmux configuration without plugin options" {
    export TMUX_STUB_SHOW_OPTIONS=$'status-keys vi\n'

    run_configuration_checker

    assert_status 1
    assert_output_contains 'No options beginning with @fzf_pane_switch were found'
}
