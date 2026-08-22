# Configuration

Set options in `tmux.conf` before loading the plugin. Reload the tmux configuration after making changes:

```bash
tmux source-file ~/.tmux.conf
```

Boolean settings accept `true` or `false`. Invalid layout, style, row, separator, boolean, or colour settings display an option-specific tmux message and do not open the switcher.

To check the plugin options in a running tmux server, run:

```bash
./tests/check_tmux_config.sh
```

The checker reports every configured `@fzf_pane_switch` option as `PASS` or `FAIL` and provides fixes for invalid option names, predefined values, and positional colour counts.

## General

### `@fzf_pane_switch_bind-key`

| Setting          | Options            | Default |
| ---------------- | ------------------ | ------- |
| tmux key binding | Any valid tmux key | `s`     |

The default produces the binding `prefix + s` and replaces tmux's default session-selection binding for that key.

```bash
set -g @fzf_pane_switch_bind-key "s"
```

### `@fzf_pane_switch_bind-key-mode`

| Setting          | Options          | Default  |
| ---------------- | ---------------- | -------- |
| Key binding mode | `prefix`, `root` | `prefix` |

Prefix mode requires the tmux prefix before the configured key. Root mode binds the key in tmux's root key table, allowing it to open the pane switcher without the prefix.

```bash
set -g @fzf_pane_switch_bind-key "C-s"
set -g @fzf_pane_switch_bind-key-mode "root"
```

### `@fzf_pane_switch_window-position`

| Setting                 | Options                            | Default          |
| ----------------------- | ---------------------------------- | ---------------- |
| Popup size and position | Any value accepted by fzf `--tmux` | `center,70%,80%` |

```bash
set -g @fzf_pane_switch_window-position "center,70%,80%"
```

See fzf's [`--tmux` documentation](https://man.archlinux.org/man/fzf.1.en#tmux) for accepted values.

### `@fzf_pane_switch_preview-pane`

| Setting      | Options         | Default |
| ------------ | --------------- | ------- |
| Preview pane | `true`, `false` | `true`  |

Press `Ctrl-/` to close or reopen an enabled preview of the highlighted pane.

```bash
set -g @fzf_pane_switch_preview-pane "true"
```

### `@fzf_pane_switch_preview-pane-start`

| Setting                    | Options             | Default   |
| -------------------------- | ------------------- | --------- |
| Initial preview visibility | `visible`, `hidden` | `visible` |

A hidden preview remains available and can be opened with `Ctrl-/`.

```bash
set -g @fzf_pane_switch_preview-pane-start "hidden"
```

This setting has no effect when `@fzf_pane_switch_preview-pane` is `false`.

### `@fzf_pane_switch_preview-pane-match`

| Setting                       | Options         | Default |
| ----------------------------- | --------------- | ------- |
| Match captured pane content   | `true`, `false` | `false` |

When enabled, searches can match the visible pane-content that the preview captures, even when the preview itself is disabled or starts hidden. Pane details rank before content-only matches, and captured content remains hidden from the selector rows.

This option requires fzf 0.73.0 or later because indexing relies on its fix for reload actions returned by background transforms. The ordinary switcher supports fzf 0.71.0 when this option is disabled.

```bash
set -g @fzf_pane_switch_preview-pane-match "true"
```

Content is captured after the switcher opens using four bounded workers and one batched normalization pass. Until the invocation snapshot is ready, the switcher remains immediately usable for pane-detail matches and shows its indexing state in the list label. `Ctrl-R`, when enabled, refreshes both the pane details and the content snapshot. Overlapping refreshes are generation-isolated, so an older capture cannot replace a newer snapshot.

### `@fzf_pane_switch_preview-pane-position`

| Setting                   | Options                                      | Default          |
| ------------------------- | -------------------------------------------- | ---------------- |
| Preview size and position | Any value accepted by fzf `--preview-window` | `right,,,nowrap` |

This setting applies when `@fzf_pane_switch_preview-pane` is `true`.

```bash
set -g @fzf_pane_switch_preview-pane-position "right,,,nowrap"
```

See fzf's [`--preview-window` documentation](https://man.archlinux.org/man/fzf.1.en#preview~3) for accepted values.

### `@fzf_pane_switch_footer`

| Setting       | Options         | Default |
| ------------- | --------------- | ------- |
| Action footer | `true`, `false` | `false` |

The footer contains the enabled actions and their keys.

```bash
set -g @fzf_pane_switch_footer "true"
```

Disabled actions are omitted. Keys are shown in bold brackets and action descriptions are dimmed, with both inheriting colours from the active fzf theme.

### `@fzf_pane_switch_jump-labels`

| Setting     | Options         | Default |
| ----------- | --------------- | ------- |
| Jump labels | `true`, `false` | `false` |

```bash
set -g @fzf_pane_switch_jump-labels "true"
```

Press `Alt-J` to display the labels, then press a label to switch immediately. Multiline entries show the same label on both rows because they represent one pane. When the footer is enabled, it includes `[Alt-J] Jump`.

### `@fzf_pane_switch_refresh`

| Setting           | Options         | Default |
| ----------------- | --------------- | ------- |
| Pane-list refresh | `true`, `false` | `false` |

When enabled, `Ctrl-R` refreshes the pane list.

```bash
set -g @fzf_pane_switch_refresh "true"
```

## Pane presentation

### `@fzf_pane_switch_layout`

| Setting     | Options                      | Default   |
| ----------- | ---------------------------- | --------- |
| Pane layout | `one-row`, `two-row`, `tree` | `one-row` |

```bash
set -g @fzf_pane_switch_layout "two-row"
```

The default two-row representation is:

```text
pane_title │ pane_current_command
session_name │ window_name
```

The internal pane ID remains hidden and unsearchable in the two-row layout. Add `pane_id` to a row format when it should also be displayed and searchable. A horizontal rule separates two-row entries; the one-row layout adds no gaps or rules.

The opt-in `tree` layout shows a permanently expanded Session > Window > Pane hierarchy. Every row is actionable: selecting a session switches to its active pane, selecting a window switches to its active pane, and selecting a pane switches to that exact pane. Window and pane rows include dim ancestry breadcrumbs that remain searchable when FZF filters away their ancestors.

### `@fzf_pane_switch_list-panes-format`

| Setting        | Options                           | Default                                                            |
| -------------- | --------------------------------- | ------------------------------------------------------------------ |
| One-row fields | Whitespace-separated tmux formats | `pane_id session_name window_name pane_title pane_current_command` |

Fields are displayed and searched in the order given:

```bash
set -g @fzf_pane_switch_list-panes-format "pane_id session_name window_name pane_title pane_current_command"
```

Values use whitespace-separated [tmux format](https://www.man7.org/linux/man-pages/man1/tmux.1.html#FORMATS) names without the surrounding `#{}`. tmux string modifiers are also supported. For example, this removes the leading percent sign from the displayed pane ID:

```bash
set -g @fzf_pane_switch_list-panes-format "s/%//:pane_id session_name window_name pane_title pane_current_command"
```

### `@fzf_pane_switch_two-row-style`

| Setting              | Options                          | Default |
| -------------------- | -------------------------------- | ------- |
| Two-row presentation | `plain`, `indented`, `connected` | `plain` |

```bash
set -g @fzf_pane_switch_two-row-style "connected"
```

Accepted values are:

- `plain` — two unadorned rows
- `indented` — a pane marker on the first row and an indented context row
- `connected` — `╭─` and `╰─` rails connecting the rows

### `@fzf_pane_switch_row-1-format`

| Setting          | Options                                       | Default                           |
| ---------------- | --------------------------------------------- | --------------------------------- |
| First-row fields | One or more whitespace-separated tmux formats | `pane_title pane_current_command` |

The default configuration is:

```bash
set -g @fzf_pane_switch_row-1-format "pane_title pane_current_command"
```

At least one value is required.

### `@fzf_pane_switch_row-2-format`

| Setting           | Options                                       | Default                    |
| ----------------- | --------------------------------------------- | -------------------------- |
| Second-row fields | One or more whitespace-separated tmux formats | `session_name window_name` |

The default configuration is:

```bash
set -g @fzf_pane_switch_row-2-format "session_name window_name"
```

At least one value is required. tmux string modifiers can be used as positional values, including path substitutions:

```bash
set -g @fzf_pane_switch_row-2-format "session_name window_name s|/Users/[^/]*|~|:pane_current_path"
```

### `@fzf_pane_switch_separator`

| Setting         | Options                                                         | Default |
| --------------- | --------------------------------------------------------------- | ------- |
| Field separator | Non-empty, single-line text without reserved control characters | `│`     |

The separator is placed between values in both rows.

```bash
set -g @fzf_pane_switch_separator "·"
```

The separator must be non-empty, single-line text without reserved control characters.

For example, a complete connected layout can be configured with:

```bash
set -g @fzf_pane_switch_layout "two-row"
set -g @fzf_pane_switch_two-row-style "connected"
set -g @fzf_pane_switch_row-1-format "pane_title pane_current_command pane_pid"
set -g @fzf_pane_switch_row-2-format "session_name window_name pane_current_path"
set -g @fzf_pane_switch_separator "·"
```

## Tree presentation

Tree-specific settings apply only when `@fzf_pane_switch_layout` is `tree`. Tree mode ignores the one-row and two-row format, style, separator, and colour settings. Conversely, the one-row and two-row layouts ignore all `tree-*` settings.

### `@fzf_pane_switch_tree-session-format`

| Setting        | Options                           | Default        |
| -------------- | --------------------------------- | -------------- |
| Session fields | Whitespace-separated tmux formats | `session_name` |

```bash
set -g @fzf_pane_switch_tree-session-format "session_name"
```

### `@fzf_pane_switch_tree-window-format`

| Setting       | Options                           | Default                    |
| ------------- | --------------------------------- | -------------------------- |
| Window fields | Whitespace-separated tmux formats | `window_index window_name` |

```bash
set -g @fzf_pane_switch_tree-window-format "window_index window_name"
```

### `@fzf_pane_switch_tree-pane-format`

| Setting     | Options                           | Default                                      |
| ----------- | --------------------------------- | -------------------------------------------- |
| Pane fields | Whitespace-separated tmux formats | `pane_index pane_title pane_current_command` |

```bash
set -g @fzf_pane_switch_tree-pane-format "pane_index pane_title pane_current_command"
```

These options use the same token syntax as the other layout formats. Session, window, and pane formats are evaluated by their corresponding tmux list command. Stable IDs used for hierarchy, preview, refresh, and switching are always added internally.

### Tree positional colours

The following options assign one positional style per configured field, using the same values and validation rules as the existing positional colour options:

- `@fzf_pane_switch_tree-session-colours`
- `@fzf_pane_switch_tree-window-colours`
- `@fzf_pane_switch_tree-pane-colours`

All default to empty (no explicit field colours). Tree connectors are plugin-controlled, and ancestry breadcrumbs are always dimmed.

```bash
set -g @fzf_pane_switch_tree-session-colours "blue:bold"
set -g @fzf_pane_switch_tree-window-colours "yellow cyan"
set -g @fzf_pane_switch_tree-pane-colours "none magenta green"
```

## Colours

Colours are opt-in and positional. Each colour maps to the format value in the same position, and the number of entries must exactly match the corresponding format. When colour settings are absent, the plugin emits no ANSI colour codes and `FZF_DEFAULT_OPTS` continues to control the appearance.

### `@fzf_pane_switch_list-panes-colours`

| Setting               | Options                                                                   | Default |
| --------------------- | ------------------------------------------------------------------------- | ------- |
| One-row field colours | One supported colour or `none` per format field, with optional attributes | Unset   |

Colours map by position to `@fzf_pane_switch_list-panes-format`.

```bash
set -g @fzf_pane_switch_list-panes-colours "none #f9e2af green #89b4fa #a6e3a1"
```

### `@fzf_pane_switch_row-1-colours`

| Setting                 | Options                                                                   | Default |
| ----------------------- | ------------------------------------------------------------------------- | ------- |
| First-row field colours | One supported colour or `none` per format field, with optional attributes | Unset   |

Colours map by position to `@fzf_pane_switch_row-1-format`.

```bash
set -g @fzf_pane_switch_row-1-colours "#89b4fa #a6e3a1"
```

### `@fzf_pane_switch_row-2-colours`

| Setting                  | Options                                                                   | Default |
| ------------------------ | ------------------------------------------------------------------------- | ------- |
| Second-row field colours | One supported colour or `none` per format field, with optional attributes | Unset   |

Colours map by position to `@fzf_pane_switch_row-2-format`.

```bash
set -g @fzf_pane_switch_row-2-colours "#f9e2af #cba6f7"
```

Complex tmux expressions are one position and can be coloured like any other value:

```bash
set -g @fzf_pane_switch_row-2-format "session_name window_name s|/Users/[^/]*|~|:pane_current_path"
set -g @fzf_pane_switch_row-2-colours "#f9e2af #cba6f7 #89b4fa"
```

### `@fzf_pane_switch_colour-separator`

| Setting          | Options                                                | Default |
| ---------------- | ------------------------------------------------------ | ------- |
| Separator colour | Supported named colour or six-digit hexadecimal colour | Unset   |

```bash
set -g @fzf_pane_switch_colour-separator "#6c7086"
```

Unlike positional colour settings, the separator accepts a colour without text attributes.

### Supported colour values and attributes

Colour values may be six-digit hexadecimal values or one of these foreground names:

```text
black red green yellow blue magenta cyan white
bright-black bright-red bright-green bright-yellow
bright-blue bright-magenta bright-cyan bright-white
gray grey
```

Use `none` to leave a position uncoloured:

```bash
set -g @fzf_pane_switch_row-1-colours "blue magenta"
set -g @fzf_pane_switch_row-2-colours "#f9e2af none"
```

Add one or more ANSI attributes after a colour using colon-separated values:

```bash
set -g @fzf_pane_switch_row-1-colours "gray:dim green:italic"
set -g @fzf_pane_switch_row-2-colours "#f9e2af:bold:underline none #89b4fa"
```

Supported attributes are:

```text
bold dim italic underline reverse strikethrough
```

`none` must be used by itself. Three-digit hexadecimal values, numeric palette indices, `-1`, backgrounds, unsupported attributes, and complete fzf `--color` fragments are rejected.

fzf themes can override input foreground colours. To keep configured input colours visible in normal, selected, and matched text, set the relevant theme foregrounds to `-1` in `FZF_DEFAULT_OPTS`.
