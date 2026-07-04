#!/usr/bin/env bash
# This script uses fzf to display a list of panes and allows you to select one.
#
# If you press ENTER, it switches to the selected pane.
# If you press ENTER on an empty line, it creates a new window in the current session.
function select_pane() {
    local border_styling="" fzf_version_comparison
    local current_pane pane pane_id preview

    # Save the currently active pane ID
    current_pane=$(tmux display-message -p '#{pane_id}')

    # Setup border styling
    # Specific fzf releases have added additional styling options.
    fzf_version=$(fzf --version | awk '{print $1}')
    # - 0.58.0 or later, we can enable border styling
    vercomp '0.58.0' "${fzf_version}"
    fzf_version_comparison=$?
    if [[ ${fzf_version_comparison} -ne 1 ]]; then
        border_styling+=" --input-border --input-label=' Search ' --info=inline-right"
        border_styling+=" --list-border --list-label=' Panes '"
        border_styling+=" --preview-border --preview-label=' Preview '"
    fi
    # - 0.61.0 or later, we can enable ghost text
    vercomp '0.61.0' "${fzf_version}"
    fzf_version_comparison=$?
    if [[ ${fzf_version_comparison} -ne 1 ]]; then
        border_styling+=" --ghost 'type to search...'"
    fi
    # Fallback to old border styling used in tmux-fzf-pane-switch release v1.1.2 if $border_styling is not set
    if [[ -z ${border_styling+x} ]]; then
        border_styling="--preview-label='pane preview'"
    fi

    # Check if we're using the fzf preview pane
    if [[ "${1}" = 'true' ]]; then
        preview="--preview '"
        preview+="tmux capture-pane -ep -S -\$(( \${FZF_PREVIEW_LINES:-30} )) -t {1} | "
        # The awk below removes trailing empty/whitespace-only lines by finding the last non-empty line and printing up to that point
        preview+="awk \"{a[NR]=\\\$0} END{for(i=NR;i>0;i--) if(a[i]~/[^ \\t]/){for(j=1;j<=i;j++) print a[j]; exit}}\" | "
        preview+="tail -n \$(( \${FZF_PREVIEW_LINES:-30} ))"
        preview+="' --preview-window=${3}"
    fi

    # fzf runs the preview command through $SHELL, and the preview uses POSIX
    # syntax that shells like fish can't parse, so point it at a POSIX shell.
    local fzf_shell
    fzf_shell="$(command -v bash || command -v sh)"

    # Launch switcher
    pane=$(
        export SHELL="${fzf_shell}"
        tmux list-panes -aF "${4}" |
            eval fzf --exit-0 --print-query --reverse --tmux "${2}" --with-nth=2.. "${border_styling}" "${preview}" |
            tail -1
    )

    # Set pane_id to first part of fzf output
    pane_id=$(echo "${pane}" | awk '{print $1}')

    # If pane_id is empty, exit without changing pane
    if [[ -z "${pane_id}" ]]; then
        tmux switch-client -t "${current_pane}"
    # Check if pane exists
    elif tmux has-session -t "${pane_id}" >/dev/null 2>&1; then
        # Found it! Let's switch.
        tmux switch-client -t "${pane_id}"
    else
        # Pane not found, let's create it.
        tmux command-prompt -b -p "Press ENTER to create a new window in the current session [${pane}]" "new-window -n \"${pane}\""
    fi
}

function vercomp() {
  local v1="$1"
  local v2="$2"

  # Split each version string into arrays using '.' as the delimiter
  IFS='.' read -r -a ver1 <<< "$v1"
  IFS='.' read -r -a ver2 <<< "$v2"

  # Compare major, minor, and patch components one by one
  for i in 0 1 2; do
    # Default to 0 if a component is missing (e.g., "1.2" becomes "1.2.0")
    local num1="${ver1[i]:-0}"
    local num2="${ver2[i]:-0}"

    # Compare the numeric values of the current component
    if (( num1 > num2 )); then
      return 1  # First version is newer
    elif (( num1 < num2 )); then
      return 2  # First version is older
    fi
  done

  return 0  # Versions are equal
}

# Check for required commands
command -v tmux >/dev/null 2>&1 || { echo "tmux not found"; exit 1; }
command -v fzf >/dev/null 2>&1 || { echo "fzf not found"; exit 1; }

# Pane preview
preview_pane="${1}"
# FZF window position
fzf_window_position="${2}"
# FZF previe window position
fzf_preview_window_position="${3}"
# TMUX list-panes format
read -r -a list_panes_format_overrides <<< "${4}"
list_panes_formatted_overrides=$(printf '#{%s} ' "${list_panes_format_overrides[@]}")

select_pane "${preview_pane}" "${fzf_window_position}" "${fzf_preview_window_position}" "#{pane_id} ${list_panes_formatted_overrides}"
