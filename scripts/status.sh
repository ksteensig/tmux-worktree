#!/usr/bin/env bash
# tmux-worktree status helper
# Usage: status.sh <worktree_path>
# Returns a colored status indicator for the given worktree.
# Usage: status.sh --all
# Returns status for all tracked worktrees (for fzf display).

STATUS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/tmux-worktree/status"

get_status() {
  local dir="$1"
  local hash
  hash=$(printf '%s' "$dir" | md5 -q 2>/dev/null || printf '%s' "$dir" | md5sum 2>/dev/null | cut -d' ' -f1)
  hash="${hash:0:12}"
  local file="$STATUS_DIR/$hash"
  if [ -f "$file" ]; then
    cat "$file"
  else
    echo "unknown"
  fi
}

status_indicator() {
  local status="$1"
  case "$status" in
    idle)       printf '\033[32m●\033[0m' ;;  # green
    busy)       printf '\033[33m●\033[0m' ;;  # yellow
    error)      printf '\033[31m●\033[0m' ;;  # red
    permission) printf '\033[34m●\033[0m' ;;  # blue
    *)          printf '\033[90m○\033[0m' ;;  # gray (no opencode running)
  esac
}

# For tmux status bar (no ANSI, use tmux color syntax).
status_indicator_tmux() {
  local status="$1"
  case "$status" in
    idle)       printf '#[fg=green]●#[default]' ;;
    busy)       printf '#[fg=yellow]●#[default]' ;;
    error)      printf '#[fg=red]●#[default]' ;;
    permission) printf '#[fg=blue]●#[default]' ;;
    *)          printf '#[fg=colour240]○#[default]' ;;
  esac
}

if [ "${1:-}" = "--tmux" ]; then
  # Called from tmux status bar with a worktree path.
  status=$(get_status "$2")
  status_indicator_tmux "$status"
elif [ "${1:-}" = "--indicator" ]; then
  # Called with a worktree path, return ANSI colored indicator.
  status=$(get_status "$2")
  status_indicator "$status"
elif [ "${1:-}" = "--raw" ]; then
  # Return raw status string.
  get_status "$2"
else
  # Default: return ANSI indicator for the given path.
  status=$(get_status "$1")
  status_indicator "$status"
fi
