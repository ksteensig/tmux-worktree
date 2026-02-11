#!/usr/bin/env bash
set -euo pipefail

# tmux-worktree cleanup: pick a worktree to tear down.
# Kills matching windows in both "opencode" and "neovim" sessions,
# optionally removes the git worktree, and removes the state entry.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS_SCRIPT="$SCRIPT_DIR/status.sh"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
FZF_BIN=$(tmux show-option -gqv @worktree-fzf-bin)
if [ -z "$FZF_BIN" ]; then
  FZF_BIN=$(command -v fzf 2>/dev/null \
    || { [ -x /opt/homebrew/bin/fzf ] && echo /opt/homebrew/bin/fzf; } \
    || { [ -x /usr/local/bin/fzf ] && echo /usr/local/bin/fzf; } \
    || true)
fi

STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/tmux-worktree"
STATE_FILE="$STATE_DIR/worktrees.tsv"

die() { printf 'tmux-worktree: %s\n' "$*" >&2; exit 1; }

[ -z "$FZF_BIN" ] || [ ! -x "$FZF_BIN" ] && die "fzf not found"

# ---------------------------------------------------------------------------
# Step 1: Build list from actual tmux windows (not just state file)
# ---------------------------------------------------------------------------
entries=""
declare -A seen=()

# Scan opencode session windows.
while IFS=$'\t' read -r idx wname pane_path; do
  [ -z "$wname" ] && continue
  # Skip duplicates.
  [ -n "${seen[$wname]:-}" ] && continue
  seen["$wname"]=1

  # Get status indicator.
  st=$("$STATUS_SCRIPT" --raw "$pane_path" 2>/dev/null || true)
  case "$st" in
    idle)       line=$(printf '%s  \033[32m● idle\033[0m' "$wname") ;;
    busy)       line=$(printf '%s  \033[33m● busy\033[0m' "$wname") ;;
    error)      line=$(printf '%s  \033[31m● error\033[0m' "$wname") ;;
    permission) line=$(printf '%s  \033[34m● permission\033[0m' "$wname") ;;
    *)          line=$(printf '%s  \033[90m○ stopped\033[0m' "$wname") ;;
  esac

  if [ -z "$entries" ]; then
    entries="$line"
  else
    entries="$entries"$'\n'"$line"
  fi
done < <(tmux list-windows -t opencode -F '#{window_index}	#{window_name}	#{pane_current_path}' 2>/dev/null || true)

[ -z "$entries" ] && die "No active worktrees"

# ---------------------------------------------------------------------------
# Step 2: Pick which worktree(s) to remove
# ---------------------------------------------------------------------------
selected=$(printf '%b\n' "$entries" | "$FZF_BIN" \
  --prompt="remove > " \
  --header="Select worktree to close (opencode + neovim windows)" \
  --reverse \
  --ansi \
  --multi) || exit 0

[ -z "$selected" ] && exit 0

# Strip ANSI annotations from selection (fzf --ansi strips them already).
clean_selected=$(printf '%s\n' "$selected" | sed 's/  [●○] [a-z]*$//')

# ---------------------------------------------------------------------------
# Step 3: Also delete git worktree?
# ---------------------------------------------------------------------------
delete_worktree=false
wt_choice=$(printf '%s\n' "Keep git worktree (close windows only)" "Also delete git worktree" "Cancel" | "$FZF_BIN" \
  --prompt="option > " \
  --header="Close opencode + neovim windows. Delete the git worktree too?" \
  --reverse --no-multi) || exit 0

case "$wt_choice" in
  "Also delete"*) delete_worktree=true ;;
  "Keep"*) delete_worktree=false ;;
  *) exit 0 ;;
esac

# ---------------------------------------------------------------------------
# Step 4: For each selected entry, tear down
# ---------------------------------------------------------------------------
while IFS= read -r window_name; do
  [ -z "$window_name" ] && continue

  # Kill windows in both sessions.
  # Match exact name OR truncated names (ending with ...).
  for session in opencode neovim; do
    win_target=""
    while IFS=$'\t' read -r idx wname; do
      if [ "$wname" = "$window_name" ]; then
        win_target="$idx"
        break
      fi
      truncated="${wname%...}"
      if [ "$truncated" != "$wname" ] && [ "${window_name#"$truncated"}" != "$window_name" ]; then
        win_target="$idx"
        break
      fi
    done < <(tmux list-windows -t "$session" -F $'#{window_index}\t#{window_name}' 2>/dev/null || true)
    if [ -n "$win_target" ]; then
      tmux kill-window -t "${session}:${win_target}" 2>/dev/null || true
    fi
  done

  # Remove git worktree if requested. Find worktree path from state file.
  if [ "$delete_worktree" = true ] && [ -f "$STATE_FILE" ]; then
    match=$(awk -F'\t' -v wn="$window_name" '{
      repo = $1; sub(/.*\//, "", repo)
      key = repo ":" $3
      if (key == wn) print
    }' "$STATE_FILE" | head -1) || true

    if [ -n "$match" ]; then
      repo_path=$(printf '%s' "$match" | cut -f1)
      worktree_path=$(printf '%s' "$match" | cut -f4)
      if [ -d "$worktree_path" ]; then
        git -C "$repo_path" worktree remove --force "$worktree_path" 2>/dev/null || true
      fi
    fi
  fi

  # Remove from state file if present.
  if [ -f "$STATE_FILE" ]; then
    awk -F'\t' -v wn="$window_name" '{
      repo = $1; sub(/.*\//, "", repo)
      key = repo ":" $3
      if (key != wn) print
    }' "$STATE_FILE" > "$STATE_FILE.tmp" 2>/dev/null || true
    mv "$STATE_FILE.tmp" "$STATE_FILE"
  fi

done <<< "$clean_selected"

# Clean up empty sessions.
for session in opencode neovim; do
  if tmux has-session -t "$session" 2>/dev/null; then
    window_count=$(tmux list-windows -t "$session" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$window_count" -eq 0 ]; then
      tmux kill-session -t "$session" 2>/dev/null || true
    fi
  fi
done

# Clean up empty state file.
if [ -f "$STATE_FILE" ] && [ ! -s "$STATE_FILE" ]; then
  rm -f "$STATE_FILE"
fi
