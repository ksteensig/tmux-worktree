#!/usr/bin/env bash
set -euo pipefail

# tmux-worktree toggle: cycle between windows within the current session.
# Order: opencode → neovim → zsh → opencode
# If the current window is not one of the three, jump to opencode.

NVIM_BIN=$(tmux show-option -gqv @worktree-nvim-bin 2>/dev/null || true)
NVIM_BIN="${NVIM_BIN:-nvim}"

OPENCODE_BIN=$(tmux show-option -gqv @worktree-opencode-bin 2>/dev/null || true)
OPENCODE_BIN="${OPENCODE_BIN:-opencode}"

current_session=$(tmux display-message -p '#{session_name}')
current_window=$(tmux display-message -p '#{window_name}')
current_path=$(tmux display-message -p '#{pane_current_path}')

# Define the cycle order.
case "$current_window" in
  opencode) next_window="neovim" ;;
  neovim)   next_window="zsh" ;;
  zsh)      next_window="opencode" ;;
  *)        next_window="opencode" ;;
esac

# Check if the target window exists in the current session.
existing=$(tmux list-windows -t "=$current_session" -F '#{window_name}' 2>/dev/null \
  | grep -xF "$next_window" || true)

if [ -n "$existing" ]; then
  # Window exists, select it.
  tmux select-window -t "=${current_session}:${next_window}"
else
  # Window was closed — recreate it.
  case "$next_window" in
    opencode) cmd="$OPENCODE_BIN" ;;
    neovim)   cmd="$NVIM_BIN" ;;
    zsh)      cmd="" ;;
  esac

  if [ -n "${cmd:-}" ]; then
    tmux new-window -t "=$current_session" -n "$next_window" -c "$current_path" "$cmd"
  else
    tmux new-window -t "=$current_session" -n "$next_window" -c "$current_path"
  fi
  tmux set-option -t "=${current_session}:${next_window}" automatic-rename off 2>/dev/null || true
fi
