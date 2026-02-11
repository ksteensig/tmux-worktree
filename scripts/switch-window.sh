#!/usr/bin/env bash
set -euo pipefail

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

# List windows in the opencode session with status indicators.
windows=""
while IFS=$'\t' read -r idx wname pane_path; do
  [ -z "$idx" ] && continue
  status=$("$STATUS_SCRIPT" --raw "$pane_path" 2>/dev/null)
  case "$status" in
    idle)       indicator='\033[32m●\033[0m' ;;
    busy)       indicator='\033[33m●\033[0m' ;;
    error)      indicator='\033[31m●\033[0m' ;;
    permission) indicator='\033[34m●\033[0m' ;;
    *)          indicator='\033[90m○\033[0m' ;;
  esac
  line=$(printf "${indicator} opencode:%s: %s  (%s)" "$idx" "$wname" "$pane_path")
  if [ -z "$windows" ]; then
    windows="$line"
  else
    windows="$windows"$'\n'"$line"
  fi
done < <(tmux list-windows -t opencode -F '#{window_index}	#{window_name}	#{pane_current_path}' 2>/dev/null)

[ -z "$windows" ] && exit 0

legend=$(printf '\033[32m● idle\033[0m  \033[33m● busy\033[0m  \033[31m● error\033[0m  \033[34m● permission\033[0m  \033[90m○ stopped\033[0m')

selected=$(printf '%b\n' "$legend" "$windows" | "$FZF_BIN" \
  --prompt="window > " \
  --header="Switch to window" \
  --header-lines=1 \
  --reverse \
  --ansi) || exit 0

# Strip the leading status indicator (fzf --ansi already strips ANSI codes).
clean=$(printf '%s' "$selected" | sed 's/^[●○] //')
target_session=$(printf '%s' "$clean" | cut -d: -f1)
target_index=$(printf '%s' "$clean" | cut -d: -f2)
window_name=$(printf '%s' "$clean" | cut -d: -f3- | sed 's/^ *//;s/  (.*//')

# Move selected window to index 1 in its session.
if [ "$target_index" != "1" ]; then
  tmux swap-window -s "${target_session}:${target_index}" -t "${target_session}:1" 2>/dev/null \
    || tmux move-window -s "${target_session}:${target_index}" -t "${target_session}:1" 2>/dev/null || true
fi

# Also move the matching window in the neovim session to index 1.
if [ -n "$window_name" ]; then
  pair_idx=$(tmux list-windows -t neovim -F '#{window_index}:#{window_name}' 2>/dev/null \
    | grep -F ":${window_name}" | head -1 | cut -d: -f1) || true
  if [ -n "$pair_idx" ] && [ "$pair_idx" != "1" ]; then
    tmux swap-window -s "neovim:${pair_idx}" -t "neovim:1" 2>/dev/null \
      || tmux move-window -s "neovim:${pair_idx}" -t "neovim:1" 2>/dev/null || true
  fi
fi

tmux switch-client -t "$target_session"
tmux select-window -t "${target_session}:1"
