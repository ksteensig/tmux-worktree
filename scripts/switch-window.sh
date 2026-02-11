#!/usr/bin/env bash
set -euo pipefail

# tmux-worktree session switcher: pick a worktree session to switch to.
# Lists all worktree sessions (named "repo:branch") with status indicators.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS_SCRIPT="$SCRIPT_DIR/status.sh"

FZF_BIN=$(tmux show-option -gqv @worktree-fzf-bin 2>/dev/null || true)
if [ -z "$FZF_BIN" ]; then
  FZF_BIN=$(command -v fzf 2>/dev/null \
    || { [ -x /opt/homebrew/bin/fzf ] && echo /opt/homebrew/bin/fzf; } \
    || { [ -x /usr/local/bin/fzf ] && echo /usr/local/bin/fzf; } \
    || true)
fi
[ -z "$FZF_BIN" ] || [ ! -x "$FZF_BIN" ] && { echo "fzf not found" >&2; exit 1; }

current_session=$(tmux display-message -p '#{session_name}')

# Build list of worktree sessions with status indicators.
entries=""
while IFS=$'\t' read -r session_name; do
  [ -z "$session_name" ] && continue
  # Only include sessions that look like worktree sessions (contain a colon).
  [[ "$session_name" != *:* ]] && continue

  # Get the pane path from the opencode window to determine status.
  pane_path=$(tmux display-message -t "=${session_name}:opencode" -p '#{pane_current_path}' 2>/dev/null || true)

  # Get status indicator.
  st=""
  if [ -n "$pane_path" ]; then
    st=$("$STATUS_SCRIPT" --raw "$pane_path" 2>/dev/null || true)
  fi

  case "$st" in
    idle)       indicator='\033[32m●\033[0m' ;;
    busy)       indicator='\033[33m●\033[0m' ;;
    error)      indicator='\033[31m●\033[0m' ;;
    permission) indicator='\033[34m●\033[0m' ;;
    *)          indicator='\033[90m○\033[0m' ;;
  esac

  # Mark the current session.
  if [ "$session_name" = "$current_session" ]; then
    line=$(printf '%b %s  (attached)' "$indicator" "$session_name")
  else
    line=$(printf '%b %s' "$indicator" "$session_name")
  fi

  if [ -z "$entries" ]; then
    entries="$line"
  else
    entries="$entries"$'\n'"$line"
  fi
done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)

[ -z "$entries" ] && exit 0

legend=$(printf '\033[32m● idle\033[0m  \033[33m● busy\033[0m  \033[31m● error\033[0m  \033[34m● permission\033[0m  \033[90m○ stopped\033[0m')

selected=$(printf '%b\n' "$legend" "$entries" | "$FZF_BIN" \
  --prompt="session > " \
  --header="Switch to worktree session" \
  --header-lines=1 \
  --reverse \
  --ansi) || exit 0

[ -z "$selected" ] && exit 0

# Strip the leading status indicator (fzf --ansi already strips ANSI codes).
# Format after ANSI stripping: "● session_name" or "● session_name  (attached)"
clean=$(printf '%s' "$selected" | sed 's/^[●○] //;s/  (attached)$//')

# Switch to the selected session.
tmux switch-client -t "=$clean"
