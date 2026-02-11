#!/usr/bin/env bash
set -euo pipefail

# tmux-worktree restore: re-create opencode + neovim sessions/windows
# from the persisted state file. Run this after a reboot.

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
ensure_session() {
  local session="$1" window="$2" dir="$3" cmd="$4"
  if tmux has-session -t "$session" 2>/dev/null; then
    tmux new-window -t "$session" -n "$window" -c "$dir" "$cmd"
  else
    tmux new-session -d -s "$session" -n "$window" -c "$dir" "$cmd"
  fi
  local win_idx
  win_idx=$(tmux list-windows -t "$session" -F '#{window_index}:#{window_name}' 2>/dev/null \
    | grep -F ":${window}" | head -1 | cut -d: -f1) || true
  if [ -n "$win_idx" ]; then
    tmux set-option -t "${session}:${win_idx}" automatic-rename off 2>/dev/null || true
  fi
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

  # Build window name (same logic as worktree.sh).
  repo=$(basename "$repo_path")
  window_name="${repo}:${safe_branch}"

  # Skip if the window already exists in the session.
  if tmux has-session -t "opencode" 2>/dev/null; then
    existing=$(tmux list-windows -t "opencode" -F '#{window_name}' 2>/dev/null | grep -xF "$window_name" || true)
    if [ -n "$existing" ]; then
      continue
    fi
  fi

  ensure_session "opencode" "$window_name" "$worktree_path" "$OPENCODE_BIN"
  ensure_session "neovim"   "$window_name" "$worktree_path" "$NVIM_BIN"
  count=$((count + 1))

done < "$STATE_FILE"

printf 'tmux-worktree: restored %d worktree(s)\n' "$count"
