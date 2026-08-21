#!/usr/bin/env bats

bats_require_minimum_version 1.11.0
load test_helper

setup() {
    setup_test_environment
}

write_tree_sessions() {
    local field_separator=$'\037'
    # Literal tmux IDs intentionally use '$'.
    # shellcheck disable=SC2016
    printf 'session%s$1%sWork%sWork\nsession%s$2%sPersonal%sPersonal\n' \
        "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" \
        > "${CASE_DIR}/sessions"
}

write_ordered_tree_snapshots() {
    local field_separator=$'\037'
    write_tree_sessions
    # Literal tmux IDs intentionally use '$'.
    # shellcheck disable=SC2016
    printf 'window%s$1%s@1%sProduction%s0 │ Production\nwindow%s$1%s@2%sNonProduction%s1 │ NonProduction\nwindow%s$2%s@3%sNotes%s0 │ Notes\n' \
        "${field_separator}" "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" "${field_separator}" \
        > "${CASE_DIR}/windows"
    printf 'pane%s@1%s%%1%s0 │ puppetserver │ bash\npane%s@2%s%%2%s0 │ puppetserver │ bash\npane%s@3%s%%3%s0 │ nvim │ nvim\n' \
        "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" \
        > "${CASE_DIR}/panes"
}

write_shuffled_tree_snapshots() {
    local field_separator=$'\037'
    write_tree_sessions
    # Literal tmux IDs intentionally use '$'.
    # shellcheck disable=SC2016
    printf 'window%s$2%s@3%sNotes%s0 │ Notes\nwindow%s$1%s@1%sProduction%s0 │ Production\nwindow%s$9%s@9%sOrphan%s9 │ Orphan\nwindow%s$1%s@2%sNonProduction%s1 │ NonProduction\n' \
        "${field_separator}" "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" "${field_separator}" \
        > "${CASE_DIR}/windows"
    printf 'pane%s@2%s%%2%s0 │ puppetserver │ bash\npane%s@3%s%%3%s0 │ nvim │ nvim\npane%s@99%s%%9%s9 │ orphan │ sh\npane%s@1%s%%1%s0 │ puppetserver │ bash\n' \
        "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" \
        > "${CASE_DIR}/panes"
}

write_expected_tree_records() {
    local field_separator=$'\037' reset=$'\033[0m' dim=$'\033[2m'
    local expected="${CASE_DIR}/expected-input"
    {
        printf '%s%ssession%sWork\0' "\$1" \
            "${field_separator}" "${field_separator}"
        printf '@1%swindow%s  ├─ 0 │ Production  %sWork%s\0' \
            "${field_separator}" "${field_separator}" "${dim}" "${reset}"
        printf '%%1%spane%s  │  └─ 0 │ puppetserver │ bash  %sWork › Production%s\0' \
            "${field_separator}" "${field_separator}" "${dim}" "${reset}"
        printf '@2%swindow%s  └─ 1 │ NonProduction  %sWork%s\0' \
            "${field_separator}" "${field_separator}" "${dim}" "${reset}"
        printf '%%2%spane%s     └─ 0 │ puppetserver │ bash  %sWork › NonProduction%s\0' \
            "${field_separator}" "${field_separator}" "${dim}" "${reset}"
        printf '%s%ssession%sPersonal\0' "\$2" \
            "${field_separator}" "${field_separator}"
        printf '@3%swindow%s  └─ 0 │ Notes  %sPersonal%s\0' \
            "${field_separator}" "${field_separator}" "${dim}" "${reset}"
        printf '%%3%spane%s     └─ 0 │ nvim │ nvim  %sPersonal › Notes%s\0' \
            "${field_separator}" "${field_separator}" "${dim}" "${reset}"
    } > "${expected}"
}

run_tree_switcher() {
    local preview="$1" refresh="$2"
    local field_separator=$'\037'
    export FZF_STUB_OUTPUT="\$1${field_separator}session"
    export TMUX_STUB_EXPAND_FORMAT='false'
    TMUX_STUB_SESSIONS_OUTPUT="$(command cat "${CASE_DIR}/sessions")"$'\n'
    TMUX_STUB_WINDOWS_OUTPUT="$(command cat "${CASE_DIR}/windows")"$'\n'
    TMUX_STUB_LIST_OUTPUT="$(command cat "${CASE_DIR}/panes")"$'\n'
    export TMUX_STUB_SESSIONS_OUTPUT TMUX_STUB_WINDOWS_OUTPUT TMUX_STUB_LIST_OUTPUT

    run_select_pane \
        "${preview}" 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command' \
        tree plain \
        'pane_title pane_current_command' \
        'session_name window_name' '│' '' '' '' '' \
        false false "${refresh}" visible \
        session_name 'window_index window_name' \
        'pane_index pane_title pane_current_command' '' '' ''
}

@test "renders searchable tree nodes and switches each target scope" {
    write_ordered_tree_snapshots
    write_expected_tree_records

    run_tree_switcher true true

    assert_status 0
    assert_files_equal_bytes "${CASE_DIR}/expected-input" "${FZF_STUB_INPUT}"
    assert_file_has_line "${FZF_STUB_ARGS}" '--with-nth=3..'
    assert_file_contains "${FZF_STUB_ARGS}" 'capture-pane .* -t \{1\}'
    assert_file_contains "${FZF_STUB_ARGS}" \
        '^--bind=ctrl-r:track-current\+reload-sync'
    assert_file_has_line "${FZF_STUB_ARGS}" '--id-nth=1'
    # Literal tmux ID intentionally uses '$'.
    # shellcheck disable=SC2016
    assert_file_contains "${TMUX_STUB_LOG}" 'switch-client -t \$1'
}

@test "joins shuffled tree snapshots by stable parent IDs and skips orphans" {
    write_shuffled_tree_snapshots
    write_expected_tree_records

    run_tree_switcher false false

    assert_status 0
    assert_files_equal_bytes "${CASE_DIR}/expected-input" "${FZF_STUB_INPUT}"
    refute_file_contains "${FZF_STUB_INPUT}" 'Orphan|orphan'
}

tree_outcome_case() {
    local selected="$1" expected_status="$2" expected="$3" unexpected="${4:-}"
    local field_separator=$'\037'
    export FZF_STUB_OUTPUT="${selected}"
    export TMUX_STUB_TARGET_EXISTS='false'
    export TMUX_STUB_SESSIONS_OUTPUT="session${field_separator}\$1${field_separator}Work${field_separator}Work"$'\n'

    run_select_pane \
        false 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command' \
        tree plain \
        'pane_title pane_current_command' \
        'session_name window_name' '│' '' '' '' '' \
        false false false visible \
        session_name 'window_index window_name' \
        'pane_index pane_title pane_current_command' '' '' ''

    assert_status "${expected_status}"
    assert_file_contains "${TMUX_STUB_LOG}" "${expected}"
    if [[ -n "${unexpected}" ]]; then
        refute_file_contains "${TMUX_STUB_LOG}" "${unexpected}"
    fi
}

# Literal tmux ID intentionally uses '$'.
# shellcheck disable=SC2016
bats_test_function --description 'reports a stale structured tree target without creating a window' -- \
    tree_outcome_case $'$1\037session' 1 \
    'Selected session target no longer exists: \$1' 'new-window'
bats_test_function --description 'preserves an unmatched tree query as a window name' -- \
    tree_outcome_case 'new workspace' 0 \
    'new workspace.*new-window -n "new workspace"'
