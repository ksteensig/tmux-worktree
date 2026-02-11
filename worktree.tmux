#!/usr/bin/env bash
# tmux-worktree — TPM plugin entry point
# Keybindings:
#   prefix + W       — create a new worktree (opencode + neovim)
#   prefix + X       — remove a worktree (cleanup both sessions)
#   prefix + R       — restore all worktrees after reboot

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

tmux bind-key "$key_create"  display-popup -E -w 80% -h 80% "$CURRENT_DIR/scripts/worktree.sh"
tmux bind-key "$key_cleanup" display-popup -E -w 80% -h 80% "$CURRENT_DIR/scripts/cleanup.sh"
tmux bind-key "$key_restore" run-shell "$CURRENT_DIR/scripts/restore.sh"
