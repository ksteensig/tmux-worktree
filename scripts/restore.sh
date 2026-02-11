#!/usr/bin/env bash
set -euo pipefail

# tmux-worktree restore: re-create sessions from the persisted state file.
# Each worktree gets its own session with 3 windows: opencode, neovim, zsh.
# Run this after a reboot.

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
OPENCODE_BIN=$(tmux show-option -gqv @worktree-opencode-bin 2>/dev/null || true)
OPENCODE_BIN="${OPENCODE_BIN:-opencode}"

NVIM_BIN=$(tmux show-option -gqv @worktree-nvim-bin 2>/dev/null || true)
NVIM_BIN="${NVIM_BIN:-nvim}"

STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/tmux-worktree"
STATE_FILE="$STATE_DIR/worktrees.tsv"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
create_session() {
  local session_name="$1" dir="$2"
  # Create session with first window: opencode
  tmux new-session -d -s "$session_name" -n "opencode" -c "$dir" "$OPENCODE_BIN"
  tmux set-option -t "=${session_name}:opencode" automatic-rename off 2>/dev/null || true

  # Second window: neovim
  tmux new-window -t "=$session_name" -n "neovim" -c "$dir" "$NVIM_BIN"
  tmux set-option -t "=${session_name}:neovim" automatic-rename off 2>/dev/null || true

  # Third window: zsh
  tmux new-window -t "=$session_name" -n "zsh" -c "$dir"
  tmux set-option -t "=${session_name}:zsh" automatic-rename off 2>/dev/null || true

  # Select the opencode window by default.
  tmux select-window -t "=${session_name}:opencode"
}

# ---------------------------------------------------------------------------
# Restore
# ---------------------------------------------------------------------------
if [ ! -f "$STATE_FILE" ] || [ ! -s "$STATE_FILE" ]; then
  printf 'tmux-worktree: nothing to restore\n'
  exit 0
fi

count=0
while IFS=$'\t' read -r repo_path branch safe_branch worktree_path; do
  [ -z "$repo_path" ] && continue

  # Skip entries whose worktree directory no longer exists.
  if [ ! -d "$worktree_path" ]; then
    continue
  fi

  # Build session name (same logic as worktree.sh).
  repo=$(basename "$repo_path")
  session_name="${repo}:${safe_branch}"

  # Skip if the session already exists.
  if tmux has-session -t "=$session_name" 2>/dev/null; then
    continue
  fi

  create_session "$session_name" "$worktree_path"
  count=$((count + 1))

done < "$STATE_FILE"

printf 'tmux-worktree: restored %d worktree(s)\n' "$count"
