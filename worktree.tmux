#!/usr/bin/env bash
# tmux-worktree — TPM plugin entry point
# Each worktree gets its own tmux session (repo/branch) with 3 windows: opencode, neovim, zsh.
#
# Keybindings:
#   prefix + W — create/open a worktree session
#   prefix + X — remove a worktree session (cleanup)
#   prefix + R — restore all worktree sessions after reboot
#   prefix + O — cycle windows within current session (opencode → neovim → zsh)
#   prefix + S — fzf session switcher (switch between worktree sessions)

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create worktree: default prefix + W
key_create=$(tmux show-option -gqv @worktree-key)
key_create="${key_create:-W}"

# Cleanup worktree: default prefix + X
key_cleanup=$(tmux show-option -gqv @worktree-cleanup-key)
key_cleanup="${key_cleanup:-X}"

# Restore worktrees: default prefix + R
key_restore=$(tmux show-option -gqv @worktree-restore-key)
key_restore="${key_restore:-R}"

# Toggle windows: default prefix + O
key_toggle=$(tmux show-option -gqv @worktree-toggle-key)
key_toggle="${key_toggle:-O}"

# Switch session: default prefix + S
key_switch=$(tmux show-option -gqv @worktree-switch-key)
key_switch="${key_switch:-S}"

tmux bind-key "$key_create"  display-popup -E -w 80% -h 80% "$CURRENT_DIR/scripts/worktree.sh"
tmux bind-key "$key_cleanup" display-popup -E -w 80% -h 80% "$CURRENT_DIR/scripts/cleanup.sh"
tmux bind-key "$key_restore" run-shell "$CURRENT_DIR/scripts/restore.sh"
tmux bind-key "$key_toggle"  run-shell "$CURRENT_DIR/scripts/toggle.sh"
tmux bind-key "$key_switch"  display-popup -E -w 90% -h 80% "$CURRENT_DIR/scripts/switch-window.sh"
