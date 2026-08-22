#!/usr/bin/env bats

bats_require_minimum_version 1.11.0
load ../test_helper

setup() {
    if [[ "${RUN_FZF_PANE_SWITCH_INTEGRATION:-false}" != true ]]; then
        skip 'set RUN_FZF_PANE_SWITCH_INTEGRATION=true to run real tmux/fzf integration tests'
    fi

    REPO_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    export REPO_DIR
    REAL_TMUX="${TMUX_INTEGRATION_BINARY:-$(PATH='/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin' command -v tmux)}"
    REAL_FZF="${FZF_INTEGRATION_BINARY:-$(PATH='/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin' command -v fzf)}"
    REAL_PYTHON="${PYTHON_INTEGRATION_BINARY:-$(PATH='/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin' command -v python3)}"
    [[ -x "${REAL_TMUX}" && -x "${REAL_FZF}" && -x "${REAL_PYTHON}" ]] ||
        skip 'real tmux, fzf, and Python 3 are required'
    export REAL_TMUX REAL_FZF REAL_PYTHON
    export TMUX_TEST_SOCKET="fzf-pane-switch-integration-$$-${BATS_TEST_NUMBER}"
    PATH="$(dirname "${REAL_FZF}"):$(dirname "${REAL_TMUX}"):/usr/bin:/bin:/usr/sbin:/sbin"
    export PATH

    tmux() {
        "${REAL_TMUX}" -L "${TMUX_TEST_SOCKET}" "$@"
    }
    export -f tmux

    "${REAL_TMUX}" -L "${TMUX_TEST_SOCKET}" -f /dev/null new-session -d \
        -s integration -x 120 -y 40 \
        "printf 'integration-alpha-token\\n'; exec sleep 60"
    "${REAL_TMUX}" -L "${TMUX_TEST_SOCKET}" new-window -d -t integration: \
        "printf 'integration-beta-token\\n'; exec sleep 60"

    match_dir="$(mktemp -d "${BATS_TEST_TMPDIR}/fzf-pane-switch.XXXXXX")"
    export match_dir
    export TMPDIR="${BATS_TEST_TMPDIR}"
    export FZF_PANE_SWITCH_LAYOUT='one-row'
    export FZF_PANE_SWITCH_PANE_FORMAT='#{pane_id} #{window_name}'
    field_separator=$'\037'
    export field_separator

    while IFS= read -r pane_id; do
        printf '%s%spane%sintegration target\0' \
            "${pane_id}" "${field_separator}" "${field_separator}" \
            >> "${match_dir}/metadata.1"
        printf '%s%spane%sintegration target%sintegration target\0' \
            "${pane_id}" "${field_separator}" "${field_separator}" "${field_separator}" \
            >> "${match_dir}/metadata-search.1"
    done < <(tmux list-panes -aF '#{pane_id}')
    printf '1\n' > "${match_dir}/generation"
    printf 'indexing\n' > "${match_dir}/state.1"
}

teardown() {
    if [[ -n "${REAL_TMUX:-}" && -n "${TMUX_TEST_SOCKET:-}" ]]; then
        "${REAL_TMUX}" -L "${TMUX_TEST_SOCKET}" kill-server 2>/dev/null || true
    fi
}

@test "real tmux capture and fzf filtering survive repeated snapshot refresh" {
    run bash "${REPO_DIR}/select_pane.sh" --match-index "${match_dir}" 30
    assert_status 0
    assert_value_equal 'ready' "$(command cat "${match_dir}/state.1")"
    assert_file_contains "${match_dir}/index.1" 'integration-beta-token'

    bash "${REPO_DIR}/select_pane.sh" --match-filter "${match_dir}" \
        integration-beta-token > "${BATS_TEST_TMPDIR}/filtered"
    assert_file_contains "${BATS_TEST_TMPDIR}/filtered" 'integration target'

    tmux send-keys -t integration:1.0 "printf 'integration-refresh-token\\n'" Enter
    run bash "${REPO_DIR}/select_pane.sh" --match-refresh "${match_dir}"
    assert_status 0
    run bash "${REPO_DIR}/select_pane.sh" --match-index "${match_dir}" 30
    assert_status 0

    assert_value_equal '2' "$(command cat "${match_dir}/generation")"
    assert_value_equal 'ready' "$(command cat "${match_dir}/state.2")"
    assert_file_contains "${match_dir}/index.2" 'integration-refresh-token'
    refute_path_exists "${match_dir}/index.1"
}

@test "real fzf Ctrl-R refresh completes and clears its indexing state" {
    tmux set-environment -g TMPDIR "${BATS_TEST_TMPDIR}"
    tmux set-option -g @fzf_pane_switch_preview-pane false
    tmux set-option -g @fzf_pane_switch_preview-pane-match true
    tmux set-option -g @fzf_pane_switch_refresh true
    tmux set-option -g @fzf_pane_switch_footer true
    tmux set-option -g @fzf_pane_switch_layout one-row
    tmux run-shell "${REPO_DIR}/select_pane.tmux"

    run "${REAL_PYTHON}" "${REPO_DIR}/tests/integration/drive_switcher.py" \
        "${REAL_TMUX}" "${TMUX_TEST_SOCKET}" "${BATS_TEST_TMPDIR}"

    assert_status 0
}
