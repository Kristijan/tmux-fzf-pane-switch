# Configuration

Set options in `tmux.conf` before loading the plugin. Reload the tmux
configuration after making changes:

```bash
tmux source-file ~/.tmux.conf
```

Boolean settings accept `true` or `false`. Invalid layout, style, row,
separator, boolean, or colour settings display an option-specific tmux message
and do not open the switcher.

## General

### `@fzf_pane_switch_bind-key`

Sets the tmux key that opens the pane switcher. The default is `s`, producing
the binding `prefix + s`. This replaces tmux's default session-selection
binding for that key.

```bash
set -g @fzf_pane_switch_bind-key "s"
```

### `@fzf_pane_switch_window-position`

Sets the size and position of the fzf tmux popup. The default is
`center,70%,80%`.

```bash
set -g @fzf_pane_switch_window-position "center,70%,80%"
```

See fzf's [`--tmux` documentation](https://man.archlinux.org/man/fzf.1.en#tmux)
for accepted values.

### `@fzf_pane_switch_preview-pane`

Controls whether the highlighted pane is shown in a preview window. The
default is `true`. Press `Ctrl-/` to close or reopen an enabled preview.

```bash
set -g @fzf_pane_switch_preview-pane "true"
```

### `@fzf_pane_switch_preview-pane-position`

Sets the preview size and position when `@fzf_pane_switch_preview-pane` is
`true`. The default is `right,,,nowrap`.

```bash
set -g @fzf_pane_switch_preview-pane-position "right,,,nowrap"
```

See fzf's [`--preview-window` documentation](https://man.archlinux.org/man/fzf.1.en#preview~3)
for accepted values.

### `@fzf_pane_switch_footer`

Controls whether fzf displays a footer containing the enabled actions and
their keys. The default is `false`.

```bash
set -g @fzf_pane_switch_footer "true"
```

Disabled actions are omitted. Keys are shown in bold brackets and action
descriptions are dimmed, with both inheriting colours from the active fzf
theme.

### `@fzf_pane_switch_jump-labels`

Enables direct selection of visible panes using fzf jump labels. The default
is `false`.

```bash
set -g @fzf_pane_switch_jump-labels "true"
```

Press `Alt-J` to display the labels, then press a label to switch immediately.
Multiline entries show the same label on both rows because they represent one
pane. When the footer is enabled, it includes `[Alt-J] Jump`.

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

| Setting     | Options                | Default   |
| ----------- | ---------------------- | --------- |
| Pane layout | `one-row`, `two-row`   | `one-row` |

```bash
set -g @fzf_pane_switch_layout "two-row"
```

The default two-row representation is:

```text
pane_title │ pane_current_command
session_name │ window_name
```

The internal pane ID remains hidden and unsearchable in the two-row layout.
Add `pane_id` to a row format when it should also be displayed and searchable.
A horizontal rule separates two-row entries; the one-row layout adds no gaps
or rules.

### `@fzf_pane_switch_list-panes-format`

| Setting        | Options                               | Default                                                                  |
| -------------- | ------------------------------------- | ------------------------------------------------------------------------ |
| One-row fields | Whitespace-separated tmux formats     | `pane_id session_name window_name pane_title pane_current_command`       |

Fields are displayed and searched in the order given:

```bash
set -g @fzf_pane_switch_list-panes-format "pane_id session_name window_name pane_title pane_current_command"
```

Values use whitespace-separated [tmux format](https://www.man7.org/linux/man-pages/man1/tmux.1.html#FORMATS)
names without the surrounding `#{}`. tmux string modifiers are also supported.
For example, this removes the leading percent sign from the displayed pane ID:

```bash
set -g @fzf_pane_switch_list-panes-format "s/%//:pane_id session_name window_name pane_title pane_current_command"
```

### `@fzf_pane_switch_two-row-style`

| Setting              | Options                           | Default |
| -------------------- | --------------------------------- | ------- |
| Two-row presentation | `plain`, `indented`, `connected`  | `plain` |

```bash
set -g @fzf_pane_switch_two-row-style "connected"
```

Accepted values are:

- `plain` — two unadorned rows
- `indented` — a pane marker on the first row and an indented context row
- `connected` — `╭─` and `╰─` rails connecting the rows

### `@fzf_pane_switch_row-1-format`

Sets the whitespace-separated tmux formats displayed on the first row. The
default is:

```bash
set -g @fzf_pane_switch_row-1-format "pane_title pane_current_command"
```

At least one value is required.

### `@fzf_pane_switch_row-2-format`

Sets the whitespace-separated tmux formats displayed on the second row. The
default is:

```bash
set -g @fzf_pane_switch_row-2-format "session_name window_name"
```

At least one value is required. tmux string modifiers can be used as positional
values, including path substitutions:

```bash
set -g @fzf_pane_switch_row-2-format "session_name window_name s|/Users/[^/]*|~|:pane_current_path"
```

### `@fzf_pane_switch_separator`

Sets the literal separator placed between values in both rows. The default is
`│`.

```bash
set -g @fzf_pane_switch_separator "·"
```

The separator must be non-empty, single-line text without reserved control
characters.

For example, a complete connected layout can be configured with:

```bash
set -g @fzf_pane_switch_layout "two-row"
set -g @fzf_pane_switch_two-row-style "connected"
set -g @fzf_pane_switch_row-1-format "pane_title pane_current_command pane_pid"
set -g @fzf_pane_switch_row-2-format "session_name window_name pane_current_path"
set -g @fzf_pane_switch_separator "·"
```

## Colours

Colours are opt-in and positional. Each colour maps to the format value in the
same position, and the number of entries must exactly match the corresponding
format. When colour settings are absent, the plugin emits no ANSI colour codes
and `FZF_DEFAULT_OPTS` continues to control the appearance.

### `@fzf_pane_switch_list-panes-colours`

Sets positional colours for `@fzf_pane_switch_list-panes-format` in the one-row
layout. The default is unset.

```bash
set -g @fzf_pane_switch_list-panes-colours "none #f9e2af green #89b4fa #a6e3a1"
```

### `@fzf_pane_switch_row-1-colours`

Sets positional colours for `@fzf_pane_switch_row-1-format`. The default is
unset.

```bash
set -g @fzf_pane_switch_row-1-colours "#89b4fa #a6e3a1"
```

### `@fzf_pane_switch_row-2-colours`

Sets positional colours for `@fzf_pane_switch_row-2-format`. The default is
unset.

```bash
set -g @fzf_pane_switch_row-2-colours "#f9e2af #cba6f7"
```

Complex tmux expressions are one position and can be coloured like any other
value:

```bash
set -g @fzf_pane_switch_row-2-format "session_name window_name s|/Users/[^/]*|~|:pane_current_path"
set -g @fzf_pane_switch_row-2-colours "#f9e2af #cba6f7 #89b4fa"
```

### `@fzf_pane_switch_colour-separator`

| Setting          | Options                                                    | Default |
| ---------------- | ---------------------------------------------------------- | ------- |
| Separator colour | Supported named colour or six-digit hexadecimal colour     | Unset   |

```bash
set -g @fzf_pane_switch_colour-separator "#6c7086"
```

Unlike positional colour settings, the separator accepts a colour without
text attributes.

### Supported colour values and attributes

Colour values may be six-digit hexadecimal values or one of these foreground
names:

```text
black red green yellow blue magenta cyan white
bright-black bright-red bright-green bright-yellow
bright-blue bright-magenta bright-cyan bright-white
gray grey
```

Use `none` to leave a position uncoloured:

```bash
set -g @fzf_pane_switch_row-1-colours "blue magenta"
set -g @fzf_pane_switch_row-2-colours "#f9e2af none #89b4fa"
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

`none` must be used by itself. Three-digit hexadecimal values, numeric palette
indices, `-1`, backgrounds, unsupported attributes, and complete fzf `--color`
fragments are rejected.

fzf themes can override input foreground colours. To keep configured input
colours visible in normal, selected, and matched text, set the relevant theme
foregrounds to `-1` in `FZF_DEFAULT_OPTS`.
