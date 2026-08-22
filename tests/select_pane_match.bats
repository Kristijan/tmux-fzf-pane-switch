#!/usr/bin/env bats

bats_require_minimum_version 1.11.0
load test_helper

setup() {
    setup_test_environment
}

run_content_matching_switcher() {
    local preview="${1:-false}" refresh="${2:-false}" footer="${3:-false}" output="${4:-}"
    local field_separator=$'\037'
    export FZF_STUB_OUTPUT="${output:-%1${field_separator}pane}"

    run_select_pane \
        "${preview}" 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command' \
        one-row plain \
        'pane_title pane_current_command' \
        'session_name window_name' '│' '' '' '' '' \
        "${footer}" false "${refresh}" visible \
        session_name 'window_index window_name' \
        'pane_index pane_title pane_current_command' '' '' '' true
}

@test "content matching requires the fzf 0.73 background-reload fix" {
    export FZF_STUB_VERSION='0.72.0'

    run_content_matching_switcher false false

    assert_status 1
    refute_path_exists "${FZF_STUB_INPUT}"
    assert_file_contains "${TMUX_STUB_LOG}" \
        '@fzf_pane_switch_preview-pane-match requires fzf 0\.73\.0 or later'
}

@test "content matching advertises refresh in the footer" {
    local expected_footer=$'--footer=  \033[1m[Enter]\033[0m \033[2mSwitch\033[0m  \033[2m·\033[0m  \033[1m[Ctrl-R]\033[0m \033[2mRefresh\033[0m  \033[2m·\033[0m  \033[1m[Ctrl-/]\033[0m \033[2mPreview\033[0m  '

    run_content_matching_switcher true true true

    assert_status 0
    assert_file_has_line "${FZF_STUB_ARGS}" "${expected_footer}"
}

@test "content matching uses hidden canonical records without requiring the preview" {
    local field_separator=$'\037'
    local expected="${CASE_DIR}/expected-input"
    printf '%%1%spane%s%%1 work editor Title nvim \0' \
        "${field_separator}" "${field_separator}" > "${expected}"

    run_content_matching_switcher false false

    assert_status 0
    assert_files_equal_bytes "${expected}" "${FZF_STUB_INPUT}"
    assert_file_has_line "${FZF_STUB_ARGS}" '--no-sort'
    assert_file_has_line "${FZF_STUB_ARGS}" '--raw'
    refute_file_contains "${FZF_STUB_ARGS}" '^--disabled$'
    assert_file_has_line "${FZF_STUB_ARGS}" '--color=nomatch:-1:regular'
    assert_file_has_line "${FZF_STUB_ARGS}" '--read0'
    assert_file_has_line "${FZF_STUB_ARGS}" '--with-nth=3'
    assert_file_contains "${FZF_STUB_ARGS}" '^--accept-nth=\{1\}.*\{2\}$'
    assert_file_contains "${FZF_STUB_ARGS}" '^--bind=change:reload-sync\['
    assert_file_contains "${FZF_STUB_ARGS}" '^--bind=start:bg-transform\['
    assert_file_contains "${FZF_STUB_ARGS}" '^--bind=enter:transform\['
    assert_file_contains "${FZF_STUB_ARGS}" \
        '^--bind=focus,result:transform-list-label\[.*--match-label.*\]$'
    refute_file_contains "${FZF_STUB_ARGS}" '^--preview$|^--preview-window='
    assert_file_contains "${TMUX_STUB_LOG}" 'switch-client -t %1'
}

@test "pane preview and content matching share the dynamic capture depth" {
    run_content_matching_switcher true false

    assert_status 0
    assert_file_contains "${FZF_STUB_ARGS}" \
        'capture-pane -ep -S -\$\(\( \$\{FZF_PREVIEW_LINES:-30\}'
    assert_file_contains "${FZF_STUB_ARGS}" \
        '--match-index .*\$\{FZF_PREVIEW_LINES:-30\}'
}

@test "narrowing preserves configured ANSI styling in selector records" {
    local field_separator=$'\037' match_dir expected
    export TMPDIR="${CASE_DIR}"
    match_dir="$(mktemp -d "${TMPDIR}/fzf-pane-switch.XXXXXX")"
    expected="${CASE_DIR}/expected-styled"
    printf '%%1%spane%s\033[31mred target\033[0m\0' \
        "${field_separator}" "${field_separator}" > "${match_dir}/metadata.1"
    printf '%%1%spane%sred target%s\033[31mred target\033[0m\0' \
        "${field_separator}" "${field_separator}" "${field_separator}" > "${match_dir}/metadata-search.1"
    command cp "${match_dir}/metadata.1" "${expected}"
    printf 'ready\n' > "${match_dir}/state.1"
    printf '1\n' > "${match_dir}/generation"

    run bash -c 'bash "$1/select_pane.sh" --match-filter "$2" red > "$3/styled"' \
        _ "${REPO_DIR}" "${match_dir}" "${CASE_DIR}"

    assert_status 0
    assert_files_equal_bytes "${expected}" "${CASE_DIR}/styled"
}

@test "content matching refreshes records, snapshots, and an enabled preview" {
    run_content_matching_switcher true true

    assert_status 0
    assert_file_contains "${FZF_STUB_ARGS}" \
        '^--bind=ctrl-r:track-current\+execute-silent\[.*--match-refresh.*\]\+transform-list-label\[.*--match-label.*\]\+bg-transform\[.*--match-index.*\]\+refresh-preview$'
    refute_file_contains "${FZF_STUB_ARGS}" '^--bind=ctrl-r:.*reload-sync'
}

@test "content matching preserves multiline presentation in canonical records" {
    local field_separator=$'\037' record_separator=$'\036' expected="${CASE_DIR}/expected-input"
    export TMUX_STUB_LIST_OUTPUT="%1${field_separator}Title │ nvim
work │ editor${record_separator}
"
    export FZF_STUB_OUTPUT="%1${field_separator}pane"
    printf '%%1%spane%sTitle │ nvim\nwork │ editor\0' \
        "${field_separator}" "${field_separator}" > "${expected}"

    run_select_pane \
        false 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command' \
        two-row plain 'pane_title pane_current_command' \
        'session_name window_name' '│' '' '' '' '' \
        false false false visible \
        session_name 'window_index window_name' \
        'pane_index pane_title pane_current_command' '' '' '' true

    assert_status 0
    assert_files_equal_bytes "${expected}" "${FZF_STUB_INPUT}"
    assert_file_has_line "${FZF_STUB_ARGS}" '--multi-line'
    assert_file_has_line "${FZF_STUB_ARGS}" '--highlight-line'
}

@test "content matching keeps tree target types hidden and renders ANSI presentation" {
    local field_separator=$'\037'
    # Literal tmux IDs intentionally use '$'.
    # shellcheck disable=SC2016
    export TMUX_STUB_SESSIONS_OUTPUT="session${field_separator}\$1${field_separator}Work${field_separator}Work"$'\n'
    export TMUX_STUB_WINDOWS_OUTPUT="window${field_separator}\$1${field_separator}@1${field_separator}Editor${field_separator}0 │ Editor"$'\n'
    export TMUX_STUB_LIST_OUTPUT="pane${field_separator}@1${field_separator}%1${field_separator}0 │ nvim │ nvim"$'\n'
    export TMUX_STUB_EXPAND_FORMAT='false'
    export FZF_STUB_OUTPUT="%1${field_separator}pane"

    run_select_pane \
        false 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command' \
        tree plain 'pane_title pane_current_command' \
        'session_name window_name' '│' '' '' '' '' \
        false false false visible \
        session_name 'window_index window_name' \
        'pane_index pane_title pane_current_command' '' '' '' true

    assert_status 0
    assert_file_has_line "${FZF_STUB_ARGS}" '--with-nth=3'
    assert_file_has_line "${FZF_STUB_ARGS}" '--ansi'
    assert_file_contains "${FZF_STUB_INPUT}" 'session.*Work'
    assert_file_contains "${FZF_STUB_INPUT}" 'window.*Editor'
    assert_file_contains "${FZF_STUB_INPUT}" 'pane.*nvim'
}

@test "content index filters metadata first, deduplicates, and excludes captured text from output" {
    local field_separator=$'\037' match_dir expected
    export TMPDIR="${CASE_DIR}"
    match_dir="$(mktemp -d "${TMPDIR}/fzf-pane-switch.XXXXXX")"
    printf '%%1%spane%salpha\0%%2%spane%sbeta\0' \
        "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" > "${match_dir}/metadata.1"
    printf '%%1%spane%salpha%salpha\0%%2%spane%sbeta%sbeta\0' \
        "${field_separator}" "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" "${field_separator}" > "${match_dir}/metadata-search.1"
    printf '1\n' > "${match_dir}/generation"
    printf 'refreshing\n' > "${match_dir}/state.1"
    export TMUX_STUB_CAPTURE_OUTPUT=$'old line\nalpha secret\nlast visible\n   \n'
    export FZF_PANE_SWITCH_LAYOUT='one-row'

    run bash "${REPO_DIR}/select_pane.sh" --match-index "${match_dir}" 2

    assert_status 0
    assert_value_equal 'ready' "$(command cat "${match_dir}/state.1")"
    assert_output_contains 'transform-list-label'
    assert_output_contains '--match-label'
    if [[ "${output}" == *'Content ready'* ]]; then
        printf 'expected the completed index to restore the normal list label\n' >&2
        return 1
    fi
    assert_output_contains '--match-filter'
    assert_output_contains '{q}'
    if [[ "${output}" == *'\{q\}'* ]]; then
        printf 'expected the published reload action to leave {q} expandable\n' >&2
        return 1
    fi
    assert_file_contains "${match_dir}/index.1" 'alpha secret'
    assert_file_contains "${match_dir}/index.1" 'last visible'
    refute_file_contains "${match_dir}/index.1" 'alpha secret last visible'
    refute_file_contains "${match_dir}/index.1" 'old line'

    run bash -c 'bash "$1/select_pane.sh" --match-filter "$2" alpha > "$3/filtered"' \
        _ "${REPO_DIR}" "${match_dir}" "${CASE_DIR}"

    assert_status 0
    expected="${CASE_DIR}/expected-filtered"
    printf '%%1%spane%salpha\0%%2%spane%sbeta\0' \
        "${field_separator}" "${field_separator}" \
        "${field_separator}" "${field_separator}" > "${expected}"
    assert_files_equal_bytes "${expected}" "${CASE_DIR}/filtered"
    refute_file_contains "${CASE_DIR}/filtered" 'secret|last visible'
}

@test "content matching does not fuzzy-match across captured line boundaries" {
    local field_separator=$'\037' match_dir capture='' query
    export TMPDIR="${CASE_DIR}"
    match_dir="$(mktemp -d "${TMPDIR}/fzf-pane-switch.XXXXXX")"
    printf '%%1%spane%sxyz\0' \
        "${field_separator}" "${field_separator}" > "${match_dir}/metadata.1"
    printf '%%1%spane%sxyz%sxyz\0' \
        "${field_separator}" "${field_separator}" "${field_separator}" > "${match_dir}/metadata-search.1"
    printf '1\n' > "${match_dir}/generation"
    printf 'indexing\n' > "${match_dir}/state.1"
    for _ in {1..23}; do
        capture+=$'a\n'
    done
    export TMUX_STUB_CAPTURE_OUTPUT="${capture}"
    export FZF_STUB_FUZZY_SUBSEQUENCE=true
    query='aaaaaaaaaaaaaaaaaaaaaaa'

    run bash "${REPO_DIR}/select_pane.sh" --match-index "${match_dir}" 30
    assert_status 0
    run bash "${REPO_DIR}/select_pane.sh" --match-filter "${match_dir}" "${query}"

    assert_status 0
    assert_value_equal '' "${output}"
    FZF_RAW=0 FZF_TOTAL_COUNT=0 FZF_MATCH_COUNT=0 \
        run bash "${REPO_DIR}/select_pane.sh" --match-enter "${match_dir}"
    assert_value_equal 'accept-or-print-query' "${output}"
}

@test "pane capture failure publishes a metadata-only fallback" {
    local field_separator=$'\037' match_dir
    export TMPDIR="${CASE_DIR}"
    match_dir="$(mktemp -d "${TMPDIR}/fzf-pane-switch.XXXXXX")"
    printf '%%1%spane%salpha\0' \
        "${field_separator}" "${field_separator}" > "${match_dir}/metadata.1"
    printf '%%1%spane%salpha%salpha\0' \
        "${field_separator}" "${field_separator}" "${field_separator}" > "${match_dir}/metadata-search.1"
    printf '1\n' > "${match_dir}/generation"
    printf 'indexing\n' > "${match_dir}/state.1"
    export TMUX_STUB_CAPTURE_STATUS=1

    run bash "${REPO_DIR}/select_pane.sh" --match-index "${match_dir}" 30

    assert_status 0
    assert_value_equal 'fallback' "$(command cat "${match_dir}/state.1")"
    refute_path_exists "${match_dir}/index.1"
    assert_output_contains 'reload-sync'
    assert_output_contains '--match-label'
}

@test "fallback remains observable when atomic state publication fails" {
    local field_separator=$'\037' match_dir
    export TMPDIR="${CASE_DIR}"
    match_dir="$(mktemp -d "${TMPDIR}/fzf-pane-switch.XXXXXX")"
    printf '%%1%spane%salpha\0' \
        "${field_separator}" "${field_separator}" > "${match_dir}/metadata.1"
    printf '%%1%spane%salpha%salpha\0' \
        "${field_separator}" "${field_separator}" "${field_separator}" > "${match_dir}/metadata-search.1"
    printf '1\n' > "${match_dir}/generation"
    printf 'indexing\n' > "${match_dir}/state.1"
    export TMUX_STUB_CAPTURE_STATUS=1
    mktemp() {
        case "$*" in
            *state.1.XXXXXX) return 1 ;;
            *) command mktemp "$@" ;;
        esac
    }
    export -f mktemp

    run bash "${REPO_DIR}/select_pane.sh" --match-index "${match_dir}" 30

    assert_status 0
    refute_path_exists "${match_dir}/state.1"
    run bash "${REPO_DIR}/select_pane.sh" --match-label "${match_dir}"
    assert_value_equal 'Panes · Content unavailable' "${output}"
}

@test "a completed index is ready even when ready-state publication fails" {
    local field_separator=$'\037' match_dir
    export TMPDIR="${CASE_DIR}"
    match_dir="$(mktemp -d "${TMPDIR}/fzf-pane-switch.XXXXXX")"
    printf '%%1%spane%salpha\0' \
        "${field_separator}" "${field_separator}" > "${match_dir}/metadata.1"
    printf '%%1%spane%salpha%salpha\0' \
        "${field_separator}" "${field_separator}" "${field_separator}" > "${match_dir}/metadata-search.1"
    printf '1\n' > "${match_dir}/generation"
    printf 'indexing\n' > "${match_dir}/state.1"
    export TMUX_STUB_CAPTURE_OUTPUT='searchable content'
    mktemp() {
        case "$*" in
            *state.1.XXXXXX) return 1 ;;
            *) command mktemp "$@" ;;
        esac
    }
    export -f mktemp

    run bash "${REPO_DIR}/select_pane.sh" --match-index "${match_dir}" 30

    assert_status 0
    assert_file_contains "${match_dir}/index.1" 'searchable content'
    run bash "${REPO_DIR}/select_pane.sh" --match-label "${match_dir}"
    assert_value_equal 'Panes' "${output}"
}

@test "failed refresh drops the previous content snapshot and reloads metadata" {
    local field_separator=$'\037' match_dir
    export TMPDIR="${CASE_DIR}"
    export FZF_PANE_SWITCH_LAYOUT='one-row'
    export FZF_PANE_SWITCH_PANE_FORMAT='#{pane_id} #{pane_title}'
    match_dir="$(mktemp -d "${TMPDIR}/fzf-pane-switch.XXXXXX")"
    printf '%%1%spane%salpha\0' \
        "${field_separator}" "${field_separator}" > "${match_dir}/metadata.1"
    printf '%%1%spane%salpha%salpha\0' \
        "${field_separator}" "${field_separator}" "${field_separator}" > "${match_dir}/metadata-search.1"
    printf '%%1%spane%salpha%sold-secret%salpha\0' \
        "${field_separator}" "${field_separator}" "${field_separator}" "${field_separator}" > "${match_dir}/index.1"
    printf '1\n' > "${match_dir}/generation"
    printf 'ready\n' > "${match_dir}/state.1"

    bash "${REPO_DIR}/select_pane.sh" --match-refresh "${match_dir}"
    TMUX_STUB_CAPTURE_STATUS=1 run \
        bash "${REPO_DIR}/select_pane.sh" --match-index "${match_dir}" 30

    assert_status 0
    assert_value_equal 'fallback' "$(command cat "${match_dir}/state.2")"
    assert_output_contains 'reload-sync'

    run bash "${REPO_DIR}/select_pane.sh" --match-filter "${match_dir}" old-secret
    assert_status 0
    assert_value_equal '' "${output}"
}

@test "a superseded indexer cannot overwrite the latest refresh snapshot" {
    local field_separator=$'\037' match_dir old_pid
    export TMPDIR="${CASE_DIR}"
    export FZF_PANE_SWITCH_LAYOUT='one-row'
    export FZF_PANE_SWITCH_PANE_FORMAT='#{pane_id} #{pane_title}'
    match_dir="$(mktemp -d "${TMPDIR}/fzf-pane-switch.XXXXXX")"
    printf '%%1%spane%salpha\0' \
        "${field_separator}" "${field_separator}" > "${match_dir}/metadata.1"
    printf '%%1%spane%salpha%salpha\0' \
        "${field_separator}" "${field_separator}" "${field_separator}" > "${match_dir}/metadata-search.1"
    printf '1\n' > "${match_dir}/generation"
    printf 'refreshing\n' > "${match_dir}/state.1"

    MV_STUB_BLOCK_DESTINATION="${match_dir}/index.1" \
        MV_STUB_STARTED="${CASE_DIR}/old-index-started" \
        MV_STUB_RELEASE="${CASE_DIR}/release-old-index" \
        TMUX_STUB_CAPTURE_OUTPUT='old snapshot' \
        bash "${REPO_DIR}/select_pane.sh" --match-index "${match_dir}" 2 \
        > "${CASE_DIR}/old-actions" &
    old_pid=$!
    while [[ ! -e "${CASE_DIR}/old-index-started" ]]; do
        kill -0 "${old_pid}" 2>/dev/null || {
            wait "${old_pid}"
            return 1
        }
        sleep 0.01
    done

    TMUX_STUB_CAPTURE_OUTPUT='new snapshot' \
        bash "${REPO_DIR}/select_pane.sh" --match-refresh "${match_dir}"
    TMUX_STUB_CAPTURE_OUTPUT='new snapshot' \
        bash "${REPO_DIR}/select_pane.sh" --match-index "${match_dir}" 2 \
        > "${CASE_DIR}/new-actions"
    : > "${CASE_DIR}/release-old-index"
    wait "${old_pid}"

    assert_value_equal '2' "$(command cat "${match_dir}/generation")"
    assert_value_equal 'ready' "$(command cat "${match_dir}/state.2")"
    assert_file_contains "${match_dir}/index.2" 'new snapshot'
    refute_file_contains "${match_dir}/index.2" 'old snapshot'
}

@test "query filtering streams results without per-query temporary files" {
    local field_separator=$'\037' match_dir expected
    export TMPDIR="${CASE_DIR}"
    match_dir="$(mktemp -d "${TMPDIR}/fzf-pane-switch.XXXXXX")"
    printf '%%1%spane%salpha\0' \
        "${field_separator}" "${field_separator}" > "${match_dir}/metadata.1"
    printf '%%1%spane%salpha%salpha\0' \
        "${field_separator}" "${field_separator}" "${field_separator}" > "${match_dir}/metadata-search.1"
    printf '%%1%spane%salpha%ssecret content%salpha\0' \
        "${field_separator}" "${field_separator}" "${field_separator}" "${field_separator}" > "${match_dir}/index.1"
    printf '1\n' > "${match_dir}/generation"
    printf 'ready\n' > "${match_dir}/state.1"
    expected="${CASE_DIR}/expected-streamed"
    command cp "${match_dir}/metadata.1" "${expected}"

    mktemp() {
        case "${1:-}" in
            *metadata-matches* | *content-matches*) return 97 ;;
            *) command mktemp "$@" ;;
        esac
    }
    export -f mktemp

    run bash -c 'bash "$1/select_pane.sh" --match-filter "$2" secret > "$3/streamed"' \
        _ "${REPO_DIR}" "${match_dir}" "${CASE_DIR}"

    assert_status 0
    assert_files_equal_bytes "${expected}" "${CASE_DIR}/streamed"
}

@test "a new content-matching invocation removes only abandoned snapshots" {
    local stale_dir active_dir
    export TMPDIR="${CASE_DIR}"
    stale_dir="$(mktemp -d "${TMPDIR}/fzf-pane-switch.XXXXXX")"
    active_dir="$(mktemp -d "${TMPDIR}/fzf-pane-switch.XXXXXX")"
    printf 'fzf-pane-switch-v1\n99999999\n' > "${stale_dir}/owner"
    printf 'fzf-pane-switch-v1\n%s\n' "$$" > "${active_dir}/owner"

    run_content_matching_switcher false false

    assert_status 0
    refute_path_exists "${stale_dir}"
    [[ -d "${active_dir}" ]]
}

@test "snapshot initialization failure falls back to the ordinary switcher" {
    mktemp() {
        case "$*" in
            *fzf-pane-switch.XXXXXX) return 1 ;;
            *) command mktemp "$@" ;;
        esac
    }
    export -f mktemp

    run_content_matching_switcher false true true '%1'

    assert_status 0
    assert_file_contains "${TMUX_STUB_LOG}" \
        'Pane-content matching unavailable; using pane details only'
    refute_file_contains "${FZF_STUB_ARGS}" '^--raw$|--match-index|--match-filter'
    assert_file_contains "${FZF_STUB_ARGS}" '^--bind=ctrl-r:track-current\+reload-sync'
    assert_file_contains "${TMUX_STUB_LOG}" 'switch-client -t %1'
}

@test "metadata generation failure falls back instead of publishing an empty snapshot" {
    export TMUX_STUB_LIST_STATUS=1

    run_content_matching_switcher false true true '%1'

    assert_status 0
    assert_file_contains "${TMUX_STUB_LOG}" \
        'Pane-content matching unavailable; using pane details only'
    refute_file_contains "${FZF_STUB_ARGS}" '^--raw$|--match-index|--match-filter'
}

@test "metadata generation failure leaves the current refresh generation intact" {
    local field_separator=$'\037' match_dir
    local -a unfinished=()
    export TMPDIR="${CASE_DIR}"
    export FZF_PANE_SWITCH_LAYOUT='one-row'
    export FZF_PANE_SWITCH_PANE_FORMAT='#{pane_id} #{pane_title}'
    match_dir="$(mktemp -d "${TMPDIR}/fzf-pane-switch.XXXXXX")"
    printf '%%1%spane%salpha\0' \
        "${field_separator}" "${field_separator}" > "${match_dir}/metadata.1"
    printf '%%1%spane%salpha%salpha\0' \
        "${field_separator}" "${field_separator}" "${field_separator}" > "${match_dir}/metadata-search.1"
    printf '1\n' > "${match_dir}/generation"
    printf 'ready\n' > "${match_dir}/state.1"
    export TMUX_STUB_LIST_STATUS=1

    run bash "${REPO_DIR}/select_pane.sh" --match-refresh "${match_dir}"

    assert_status 1
    assert_value_equal '1' "$(command cat "${match_dir}/generation")"
    assert_value_equal 'ready' "$(command cat "${match_dir}/state.1")"
    shopt -s nullglob
    unfinished=("${match_dir}"/metadata.2* "${match_dir}"/metadata-search.2* "${match_dir}"/state.2*)
    [[ ${#unfinished[@]} -eq 0 ]]
}

@test "list label identifies a focused pane-content match after indexing" {
    local match_dir
    export TMPDIR="${CASE_DIR}"
    export FZF_PANE_SWITCH_LAYOUT='tree'
    match_dir="$(mktemp -d "${TMPDIR}/fzf-pane-switch.XXXXXX")"
    printf '1\n' > "${match_dir}/generation"

    printf 'indexing\n' > "${match_dir}/state.1"
    FZF_RAW=0 FZF_TOTAL_COUNT=1 run bash "${REPO_DIR}/select_pane.sh" --match-label "${match_dir}"
    assert_value_equal 'Targets · Indexing content…' "${output}"

    printf 'fallback\n' > "${match_dir}/state.1"
    FZF_RAW=0 FZF_TOTAL_COUNT=1 run bash "${REPO_DIR}/select_pane.sh" --match-label "${match_dir}"
    assert_value_equal 'Targets · Content unavailable' "${output}"

    printf 'ready\n' > "${match_dir}/state.1"
    FZF_RAW=0 FZF_TOTAL_COUNT=1 run bash "${REPO_DIR}/select_pane.sh" --match-label "${match_dir}"
    assert_value_equal 'Targets · Pane content match' "${output}"

    FZF_RAW=1 FZF_TOTAL_COUNT=1 run bash "${REPO_DIR}/select_pane.sh" --match-label "${match_dir}"
    assert_value_equal 'Targets' "${output}"
}

@test "Enter blocks a zero-result query until content indexing settles" {
    local match_dir
    export TMPDIR="${CASE_DIR}"
    match_dir="$(mktemp -d "${TMPDIR}/fzf-pane-switch.XXXXXX")"
    printf '1\n' > "${match_dir}/generation"
    printf 'indexing\n' > "${match_dir}/state.1"

    FZF_RAW=0 FZF_TOTAL_COUNT=1 run bash "${REPO_DIR}/select_pane.sh" --match-enter "${match_dir}"
    assert_status 0
    assert_output_contains 'bell+change-list-label'

    printf 'refreshing\n' > "${match_dir}/state.1"
    FZF_RAW=0 FZF_TOTAL_COUNT=0 run bash "${REPO_DIR}/select_pane.sh" --match-enter "${match_dir}"
    assert_status 0
    assert_output_contains 'bell+change-list-label'

    printf 'ready\n' > "${match_dir}/state.1"
    FZF_RAW=0 FZF_TOTAL_COUNT=0 run bash "${REPO_DIR}/select_pane.sh" --match-enter "${match_dir}"
    assert_value_equal 'accept-or-print-query' "${output}"

    printf 'indexing\n' > "${match_dir}/state.1"
    FZF_RAW=1 FZF_TOTAL_COUNT=1 run bash "${REPO_DIR}/select_pane.sh" --match-enter "${match_dir}"
    assert_value_equal 'accept' "${output}"

    printf 'ready\n' > "${match_dir}/state.1"
    FZF_RAW=0 FZF_TOTAL_COUNT=1 run bash "${REPO_DIR}/select_pane.sh" --match-enter "${match_dir}"
    assert_value_equal 'accept' "${output}"
}

@test "rejects an invalid pane-content matching boolean" {
    run_select_pane \
        false 'center,70%,80%' 'right,,,nowrap' \
        'pane_id session_name window_name pane_title pane_current_command' \
        one-row plain 'pane_title pane_current_command' \
        'session_name window_name' '│' '' '' '' '' \
        false false false visible \
        session_name 'window_index window_name' \
        'pane_index pane_title pane_current_command' '' '' '' sometimes

    assert_status 1
    refute_path_exists "${FZF_STUB_INPUT}"
    assert_file_contains "${TMUX_STUB_LOG}" \
        '@fzf_pane_switch_preview-pane-match must be true or false'
}
