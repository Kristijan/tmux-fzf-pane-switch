# https://github.com/charmbracelet/vhs

# GIF output file
Output tmux-fzf-pane-switch-demo.gif

# Terminal setup
Set Theme "Catppuccin Mocha"
Set FontFamily "MonaspiceAr Nerd Font Mono"
Set FontSize 12
Set Padding 0
Set Framerate 60
Set Width 1000
Set Height 600

# Shell setup
Set Shell zsh

# Require programs
Require tmux
Require fzf

# Attach tmux (hidden in GIF)
Hide
Type "tmux attach" Enter
Sleep 2s
Show

# Start tmux-fzf-pane-switch for first search
Sleep 1
Ctrl+p
Sleep 500ms
Type "s"
Sleep 500ms

# Type search query
Type@500ms "code"
Sleep 500ms
Enter

# Start tmux-fzf-pane-switch for second search
Sleep 1
Ctrl+p
Sleep 500ms
Type "s"
Sleep 500ms

# Type search query
Type@500ms "main wt"
Sleep 500ms
Enter

# Commentary
Type `"This works across all your sessions, windows, and panes!"`

# Admire the output for a bit.
Sleep 3s
