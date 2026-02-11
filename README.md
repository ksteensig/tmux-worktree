# tmux-worktree

A tmux plugin for managing git worktrees with paired [OpenCode](https://opencode.ai) + Neovim sessions. Pick a repo, pick a branch, and get a worktree with both an OpenCode and Neovim window ready to go.

## Dependencies

- [tmux](https://github.com/tmux/tmux) >= 3.2 (uses `display-popup`)
- [fzf](https://github.com/junegunn/fzf)
- [git](https://git-scm.com)
- [OpenCode](https://opencode.ai) (optional, for the AI coding assistant windows)
- [Neovim](https://neovim.io) (optional, for the editor windows)
- bash >= 4.0 (uses associative arrays)

## Install

### Clone the repo

```sh
git clone https://github.com/ksteensig/tmux-worktree.git ~/Workspace/tmux-worktree
```

### Add keybindings to your tmux config

Add the following to your `tmux.conf` (or `.tmux.conf.local` if using [Oh My Tmux](https://github.com/gpakosz/.tmux)):

```tmux
# tmux-worktree
bind-key W display-popup -E -w 80% -h 80% "$HOME/Workspace/tmux-worktree/scripts/worktree.sh"
bind-key X display-popup -E -w 80% -h 80% "$HOME/Workspace/tmux-worktree/scripts/cleanup.sh"
bind-key R run-shell "$HOME/Workspace/tmux-worktree/scripts/restore.sh"
bind-key O run-shell "$HOME/Workspace/tmux-worktree/scripts/toggle.sh"
bind-key S display-popup -E -w 60% -h 60% "$HOME/Workspace/tmux-worktree/scripts/switch-window.sh"
```

If you're using Oh My Tmux, append `#!important` to each line so bindings survive config reloads.

### Reload tmux

```
prefix + r
```

Or restart tmux.

## Keybindings

| Key | Action |
|-----|--------|
| `prefix + W` | **Create/open worktree** -- pick a repo, pick/create a branch, opens windows in both `opencode` and `neovim` sessions |
| `prefix + X` | **Close worktree** -- pick windows to close, optionally delete the git worktree |
| `prefix + S` | **Switch window** -- fzf picker for opencode windows with status indicators |
| `prefix + O` | **Toggle session** -- switch between `opencode` and `neovim` sessions for the current worktree |
| `prefix + R` | **Restore** -- recreate all sessions/windows from saved state after a reboot |

## How it works

### Dual-session workflow

When you create a worktree (`prefix + W`), the plugin:

1. Scans a base directory (default `~/Workspace`) for git repos
2. Lets you pick a branch via fzf (local + remote branches, with option to create new)
3. Creates a git worktree if one doesn't already exist
4. Opens a window in the `opencode` tmux session running OpenCode
5. Opens a matching window in the `neovim` tmux session running Neovim
6. Moves both windows to position 1 and switches to the `opencode` session

If the worktree already has windows open, it focuses them instead of creating duplicates.

### Session toggle

`prefix + O` toggles between the `opencode` and `neovim` sessions. If you're in `opencode`, it switches to `neovim` (and vice versa), landing on the matching window. If a window was closed, it recreates it.

### Cleanup

`prefix + X` shows an fzf picker of all open worktree windows. After selecting, you choose whether to:

- **Keep git worktree** -- only closes the tmux windows
- **Also delete git worktree** -- closes windows AND removes the worktree from disk

### Restore after reboot

Active worktrees are persisted to `~/.local/share/tmux-worktree/worktrees.tsv`. After a reboot, `prefix + R` recreates all the `opencode` and `neovim` sessions with their windows.

## Status indicators

Branches and windows show colored status indicators when the OpenCode status plugin is installed:

| Indicator | Meaning |
|-----------|---------|
| `● idle` (green) | OpenCode is idle |
| `● busy` (yellow) | Model is generating |
| `● error` (red) | An error occurred |
| `● permission` (blue) | Waiting for user permission |
| `○ stopped` (gray) | Worktree exists but OpenCode is not running |

### OpenCode plugin setup

Copy the status plugin to your OpenCode plugins directory:

```sh
mkdir -p ~/.config/opencode/plugins
cp extras/tmux-status.ts ~/.config/opencode/plugins/
```

Make sure the `@opencode-ai/plugin` types are available:

```sh
# In ~/.config/opencode/
cat > package.json << 'EOF'
{
  "dependencies": {
    "@opencode-ai/plugin": "latest"
  }
}
EOF
```

OpenCode will install the dependency automatically on next launch.

### tmux status bar

To show the OpenCode status in your tmux status bar, add a custom variable. For Oh My Tmux, add this function in the custom variables section (between `# EOF` and `# "$@"`):

```sh
# # usage: #{opencode_status}
# opencode_status() {
#   status_dir="${XDG_DATA_HOME:-$HOME/.local/share}/tmux-worktree/status"
#   pane_path=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null)
#   if [ -z "$pane_path" ]; then
#     return
#   fi
#   hash=$(printf '%s' "$pane_path" | md5 -q 2>/dev/null || printf '%s' "$pane_path" | md5sum 2>/dev/null | cut -d' ' -f1)
#   hash=$(printf '%s' "$hash" | cut -c1-12)
#   file="$status_dir/$hash"
#   if [ -f "$file" ]; then
#     status=$(cat "$file")
#   else
#     return
#   fi
#   case "$status" in
#     idle)       printf '✔' ;;
#     busy)       printf '⟳' ;;
#     error)      printf '✘' ;;
#     permission) printf '?' ;;
#   esac
# }
```

Then add `#{opencode_status}` to your `tmux_conf_theme_status_right`.

## Configuration

All options are set via tmux global options. Defaults work out of the box.

| Option | Default | Description |
|--------|---------|-------------|
| `@worktree-base-dir` | `$HOME/Workspace` | Directory to scan for git repos |
| `@worktree-opencode-bin` | `opencode` | Path to the OpenCode binary |
| `@worktree-nvim-bin` | `nvim` | Path to the Neovim binary |
| `@worktree-fzf-bin` | auto-detected | Path to the fzf binary |

Set them in your tmux config:

```tmux
set -g @worktree-base-dir "$HOME/Projects"
set -g @worktree-nvim-bin "/usr/local/bin/nvim"
```

## Data storage

| Path | Purpose |
|------|---------|
| `~/.local/share/tmux-worktree/worktrees.tsv` | Persisted worktree state for restore |
| `~/.local/share/tmux-worktree/status/` | OpenCode status files (one per worktree) |

## License

MIT
