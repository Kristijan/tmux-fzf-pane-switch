#!/usr/bin/env bash

# Bats defines status and output after run.
# shellcheck disable=SC2154

setup_test_environment() {
    REPO_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    FIXTURE_BIN="${REPO_DIR}/tests/fixtures/bin"
    CASE_DIR="${BATS_TEST_TMPDIR}/case"
    mkdir -p "${CASE_DIR}"

    unset FZF_STUB_HELP
    unset TMUX_STUB_BIND_KEY_MODE TMUX_STUB_LAYOUT TMUX_STUB_STYLE
    unset TMUX_STUB_ROW_1 TMUX_STUB_ROW_2 TMUX_STUB_SEPARATOR
    unset TMUX_STUB_LIST_COLOURS TMUX_STUB_ROW_1_COLOURS
    unset TMUX_STUB_ROW_2_COLOURS TMUX_STUB_SEPARATOR_COLOUR
    unset TMUX_STUB_FOOTER TMUX_STUB_JUMP_LABELS TMUX_STUB_REFRESH
    unset TMUX_STUB_PREVIEW_PANE_START TMUX_STUB_TREE_SESSION
    unset TMUX_STUB_TREE_WINDOW TMUX_STUB_TREE_PANE
    unset TMUX_STUB_TREE_SESSION_COLOURS TMUX_STUB_TREE_WINDOW_COLOURS
    unset TMUX_STUB_TREE_PANE_COLOURS TMUX_STUB_SHOW_OPTIONS
    unset TMUX_STUB_SESSIONS_OUTPUT TMUX_STUB_WINDOWS_OUTPUT
    unset TMUX_STUB_LIST_OUTPUT TMUX_STUB_TARGET_EXISTS

    export REPO_DIR FIXTURE_BIN CASE_DIR
    export PATH="${FIXTURE_BIN}:${PATH}"
    export FZF_STUB_VERSION='0.71.0'
    export FZF_STUB_ARGS="${CASE_DIR}/fzf-args"
    export FZF_STUB_INPUT="${CASE_DIR}/fzf-input"
    export FZF_STUB_OUTPUT='%1'
    export TMUX_STUB_LOG="${CASE_DIR}/tmux-log"
    export TMUX_STUB_EXPAND_FORMAT='true'
}

run_select_pane() {
    run bash "${REPO_DIR}/select_pane.sh" "$@"
}

run_tmux_entrypoint() {
    run bash "${REPO_DIR}/select_pane.tmux"
}

run_configuration_checker() {
    run bash "${REPO_DIR}/tests/check_tmux_config.sh"
}

assert_status() {
    local expected="$1"
    if [[ "${status}" -ne "${expected}" ]]; then
        printf 'expected status: %s\nactual status:   %s\noutput:\n%s\n' \
            "${expected}" "${status}" "${output}" >&2
        return 1
    fi
}

assert_value_equal() {
    local expected="$1" actual="$2"
    if [[ "${actual}" != "${expected}" ]]; then
        printf 'expected:\n%s\nactual:\n%s\n' "${expected}" "${actual}" >&2
        return 1
    fi
}

assert_output_contains() {
    local expected="$1"
    if ! grep -Fq -- "${expected}" <<< "${output}"; then
        printf 'expected output to contain:\n%s\nactual output:\n%s\n' \
            "${expected}" "${output}" >&2
        return 1
    fi
}

assert_output_line_count() {
    local pattern="$1" expected="$2" actual
    actual="$(grep -c -- "${pattern}" <<< "${output}")"
    if [[ "${actual}" -ne "${expected}" ]]; then
        printf 'expected %s output lines matching %s, got %s\noutput:\n%s\n' \
            "${expected}" "${pattern}" "${actual}" "${output}" >&2
        return 1
    fi
}

assert_file_exists() {
    local path="$1"
    if [[ ! -f "${path}" ]]; then
        printf 'expected file to exist: %s\n' "${path}" >&2
        return 1
    fi
}

refute_path_exists() {
    local path="$1"
    if [[ -e "${path}" ]]; then
        printf 'expected path not to exist: %s\n' "${path}" >&2
        return 1
    fi
}

assert_file_contains() {
    local path="$1" expected="$2"
    if ! grep -aEq -- "${expected}" "${path}"; then
        printf 'expected %s to match:\n%s\nactual contents:\n' \
            "${path}" "${expected}" >&2
        command sed -n '1,160p' "${path}" >&2
        return 1
    fi
}

refute_file_contains() {
    local path="$1" unexpected="$2"
    if grep -aEq -- "${unexpected}" "${path}"; then
        printf 'expected %s not to match:\n%s\nactual contents:\n' \
            "${path}" "${unexpected}" >&2
        command sed -n '1,160p' "${path}" >&2
        return 1
    fi
}

assert_file_has_line() {
    local path="$1" expected="$2"
    if ! grep -Fxq -- "${expected}" "${path}"; then
        printf 'expected %s to contain line:\n%s\nactual contents:\n' \
            "${path}" "${expected}" >&2
        command sed -n '1,160p' "${path}" >&2
        return 1
    fi
}

assert_files_equal_bytes() {
    local expected="$1" actual="$2"
    if ! command cmp -s "${expected}" "${actual}"; then
        printf 'byte mismatch\nexpected file: %s\nactual file:   %s\n' \
            "${expected}" "${actual}" >&2
        printf 'expected bytes:\n' >&2
        command od -An -tx1 -v "${expected}" >&2
        printf 'actual bytes:\n' >&2
        command od -An -tx1 -v "${actual}" >&2
        return 1
    fi
}
