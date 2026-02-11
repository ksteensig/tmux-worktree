#!/usr/bin/env bash
# tmux-worktree — TPM plugin entry point
# Creates a keybinding to launch the worktree picker.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default keybinding: prefix + W (capital W)
default_key="W"
key=$(tmux show-option -gqv @worktree-key)
key="${key:-$default_key}"

tmux bind-key "$key" display-popup -E -w 80% -h 80% "$CURRENT_DIR/scripts/worktree.sh"
