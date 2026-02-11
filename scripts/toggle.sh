#!/usr/bin/env bash
set -euo pipefail

NVIM_BIN=$(tmux show-option -gqv @worktree-nvim-bin 2>/dev/null || true)
NVIM_BIN="${NVIM_BIN:-nvim}"

OPENCODE_BIN=$(tmux show-option -gqv @worktree-opencode-bin 2>/dev/null || true)
OPENCODE_BIN="${OPENCODE_BIN:-opencode}"

current_session=$(tmux display-message -p '#{session_name}')
current_window=$(tmux display-message -p '#{window_name}')
current_path=$(tmux display-message -p '#{pane_current_path}')

if [ "$current_session" = "opencode" ]; then
  target_session="neovim"
  target_cmd="$NVIM_BIN"
elif [ "$current_session" = "neovim" ]; then
  target_session="opencode"
  target_cmd="$OPENCODE_BIN"
else
  target_session="opencode"
  target_cmd="$OPENCODE_BIN"
fi

# Ensure the target session exists.
if ! tmux has-session -t "$target_session" 2>/dev/null; then
  tmux new-session -d -s "$target_session" -n "$current_window" -c "$current_path" "$target_cmd"
  tmux switch-client -t "$target_session"
  exit 0
fi

# Check if a window with the same name exists in the target session.
target_window=$(tmux list-windows -t "$target_session" -F '#{window_name}' 2>/dev/null \
  | grep -xF "$current_window" || true)

if [ -z "$target_window" ]; then
  # Window was closed -- recreate it.
  tmux new-window -t "$target_session" -n "$current_window" -c "$current_path" "$target_cmd"
  # Disable automatic-rename so tmux keeps our window name.
  new_idx=$(tmux list-windows -t "$target_session" -F '#{window_index}:#{window_name}' 2>/dev/null \
    | grep -F ":${current_window}" | head -1 | cut -d: -f1) || true
  if [ -n "$new_idx" ]; then
    tmux set-option -t "${target_session}:${new_idx}" automatic-rename off 2>/dev/null || true
  fi
fi

# Move the target window to index 1.
win_idx=$(tmux list-windows -t "$target_session" -F '#{window_index}:#{window_name}' 2>/dev/null \
  | grep -F ":${current_window}" | head -1 | cut -d: -f1) || true
if [ -n "$win_idx" ] && [ "$win_idx" != "1" ]; then
  tmux swap-window -s "${target_session}:${win_idx}" -t "${target_session}:1" 2>/dev/null \
    || tmux move-window -s "${target_session}:${win_idx}" -t "${target_session}:1" 2>/dev/null || true
fi

# Also move the current window to index 1 in the source session.
cur_idx=$(tmux list-windows -t "$current_session" -F '#{window_index}:#{window_name}' 2>/dev/null \
  | grep -F ":${current_window}" | head -1 | cut -d: -f1) || true
if [ -n "$cur_idx" ] && [ "$cur_idx" != "1" ]; then
  tmux swap-window -s "${current_session}:${cur_idx}" -t "${current_session}:1" 2>/dev/null \
    || tmux move-window -s "${current_session}:${cur_idx}" -t "${current_session}:1" 2>/dev/null || true
fi

tmux switch-client -t "$target_session"
tmux select-window -t "${target_session}:1"
