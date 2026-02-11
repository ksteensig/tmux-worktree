#!/usr/bin/env bash
set -euo pipefail

# tmux-worktree cleanup: pick a worktree session to tear down.
# Kills the entire session (opencode + neovim + zsh windows),
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
STATUS_DIR="$STATE_DIR/status"

die() { printf 'tmux-worktree: %s\n' "$*" >&2; exit 1; }

[ -z "$FZF_BIN" ] || [ ! -x "$FZF_BIN" ] && die "fzf not found"

# ---------------------------------------------------------------------------
# Step 1: Build list of worktree sessions
# ---------------------------------------------------------------------------
# Worktree sessions are named "repo/branch". List all sessions that contain
# a slash (to exclude non-worktree sessions).
entries=""
while IFS=$'\t' read -r session_name; do
  [ -z "$session_name" ] && continue
  # Only include sessions that look like worktree sessions (contain a slash).
  [[ "$session_name" != */* ]] && continue

  # Get the pane path from the opencode window to determine status.
  pane_path=$(tmux display-message -t "=${session_name}:opencode" -p '#{pane_current_path}' 2>/dev/null || true)

  # Get status indicator.
  st=""
  if [ -n "$pane_path" ]; then
    st=$("$STATUS_SCRIPT" --raw "$pane_path" 2>/dev/null || true)
  fi

  case "$st" in
    idle)       line=$(printf '%s  \033[32m● idle\033[0m' "$session_name") ;;
    busy)       line=$(printf '%s  \033[33m● busy\033[0m' "$session_name") ;;
    error)      line=$(printf '%s  \033[31m● error\033[0m' "$session_name") ;;
    permission) line=$(printf '%s  \033[34m● permission\033[0m' "$session_name") ;;
    *)          line=$(printf '%s  \033[90m○ stopped\033[0m' "$session_name") ;;
  esac

  if [ -z "$entries" ]; then
    entries="$line"
  else
    entries="$entries"$'\n'"$line"
  fi
done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)

[ -z "$entries" ] && die "No active worktree sessions"

# ---------------------------------------------------------------------------
# Step 2: Pick which session(s) to remove
# ---------------------------------------------------------------------------
selected=$(printf '%b\n' "$entries" | "$FZF_BIN" \
  --prompt="remove > " \
  --header="Select worktree session to close" \
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
wt_choice=$(printf '%s\n' "Keep git worktree (close session only)" "Also delete git worktree" "Cancel" | "$FZF_BIN" \
  --prompt="option > " \
  --header="Close session. Delete the git worktree too?" \
  --reverse --no-multi) || exit 0

case "$wt_choice" in
  "Also delete"*) delete_worktree=true ;;
  "Keep"*) delete_worktree=false ;;
  *) exit 0 ;;
esac

# ---------------------------------------------------------------------------
# Step 4: For each selected session, tear down
# ---------------------------------------------------------------------------
while IFS= read -r session_name; do
  [ -z "$session_name" ] && continue

  # Kill the entire session.
  tmux kill-session -t "=$session_name" 2>/dev/null || true

  # Remove git worktree if requested. Find worktree path from state file.
  if [ "$delete_worktree" = true ] && [ -f "$STATE_FILE" ]; then
    match=$(awk -F'\t' -v sn="$session_name" '{
      repo = $1; sub(/.*\//, "", repo)
      key = repo "/" $3
      if (key == sn) print
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
    awk -F'\t' -v sn="$session_name" '{
      repo = $1; sub(/.*\//, "", repo)
      key = repo "/" $3
      if (key != sn) print
    }' "$STATE_FILE" > "$STATE_FILE.tmp" 2>/dev/null || true
    mv "$STATE_FILE.tmp" "$STATE_FILE"
  fi

  # Clean up status file for this worktree.
  if [ -f "$STATE_FILE" ] || [ "$delete_worktree" = true ]; then
    # Try to find the worktree path to clean up status file.
    # The session name is "repo/safe_branch", worktree path is BASE_DIR/repo/safe_branch.
    repo_part="${session_name%%/*}"
    branch_part="${session_name#*/}"
    BASE_DIR=$(tmux show-option -gqv @worktree-base-dir 2>/dev/null || true)
    BASE_DIR="${BASE_DIR:-$HOME/Workspace}"
    wt_dir="$BASE_DIR/$repo_part/$branch_part"
    hash=$(printf '%s' "$wt_dir" | md5 -q 2>/dev/null || printf '%s' "$wt_dir" | md5sum 2>/dev/null | cut -d' ' -f1)
    hash="${hash:0:12}"
    rm -f "$STATUS_DIR/$hash" 2>/dev/null || true
  fi

done <<< "$clean_selected"

# Clean up empty state file.
if [ -f "$STATE_FILE" ] && [ ! -s "$STATE_FILE" ]; then
  rm -f "$STATE_FILE"
fi
