#!/usr/bin/env bash
set -euo pipefail

# tmux-worktree: pick a repo, pick/create a branch, create a git worktree,
# open matching windows in "opencode" and "neovim" sessions.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Configuration (overridable via tmux options)
# ---------------------------------------------------------------------------
BASE_DIR=$(tmux show-option -gqv @worktree-base-dir)
BASE_DIR="${BASE_DIR:-$HOME/Workspace}"

OPENCODE_BIN=$(tmux show-option -gqv @worktree-opencode-bin)
OPENCODE_BIN="${OPENCODE_BIN:-opencode}"

NVIM_BIN=$(tmux show-option -gqv @worktree-nvim-bin)
NVIM_BIN="${NVIM_BIN:-nvim}"

FZF_BIN=$(tmux show-option -gqv @worktree-fzf-bin)
if [ -z "$FZF_BIN" ]; then
  FZF_BIN=$(command -v fzf 2>/dev/null \
    || { [ -x /opt/homebrew/bin/fzf ] && echo /opt/homebrew/bin/fzf; } \
    || { [ -x /usr/local/bin/fzf ] && echo /usr/local/bin/fzf; } \
    || true)
fi

STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/tmux-worktree"
STATE_FILE="$STATE_DIR/worktrees.tsv"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die() { printf 'tmux-worktree: %s\n' "$*" >&2; exit 1; }

[ -z "$FZF_BIN" ] || [ ! -x "$FZF_BIN" ] && die "fzf not found. Install it (brew install fzf) or set @worktree-fzf-bin"

is_git_repo() {
  [ -d "$1/.git" ] || [ -f "$1/HEAD" ]
}

ensure_session() {
  local session="$1" window="$2" dir="$3" cmd="$4"
  if tmux has-session -t "$session" 2>/dev/null; then
    tmux new-window -t "$session" -n "$window" -c "$dir" "$cmd"
  else
    tmux new-session -d -s "$session" -n "$window" -c "$dir" "$cmd"
  fi
  # Disable automatic-rename so tmux doesn't overwrite our window name.
  local win_idx
  win_idx=$(tmux list-windows -t "$session" -F '#{window_index}:#{window_name}' 2>/dev/null \
    | grep -F ":${window}" | head -1 | cut -d: -f1) || true
  if [ -n "$win_idx" ]; then
    tmux set-option -t "${session}:${win_idx}" automatic-rename off 2>/dev/null || true
  fi
}

save_state() {
  mkdir -p "$STATE_DIR"
  # Append entry: repo_path \t branch \t safe_branch \t worktree_path
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$STATE_FILE"
  # Deduplicate
  sort -u -o "$STATE_FILE" "$STATE_FILE"
}

# ---------------------------------------------------------------------------
# Step 1: Pick a repo
# ---------------------------------------------------------------------------
repos=()
for d in "$BASE_DIR"/*/; do
  [ -d "$d" ] || continue
  is_git_repo "$d" && repos+=("$(basename "$d")")
done

[ ${#repos[@]} -eq 0 ] && die "No git repos found in $BASE_DIR"

repo=$(printf '%s\n' "${repos[@]}" | "$FZF_BIN" \
  --prompt="repo > " \
  --header="Select a repository" \
  --reverse) || exit 0

repo_path="$BASE_DIR/$repo"

# ---------------------------------------------------------------------------
# Step 2: Pick a branch (or create new)
# ---------------------------------------------------------------------------
# Fetch in background so we don't block the UI. Branches show from local cache
# immediately; new remote branches appear next time.
git -C "$repo_path" fetch --all --prune --quiet 2>/dev/null &

local_branches=$(git -C "$repo_path" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null || true)
remote_branches=$(git -C "$repo_path" for-each-ref --format='%(refname:short)' refs/remotes/ 2>/dev/null \
  | sed 's|^[^/]*/||' | { grep -v '^HEAD$' || true; } | sort -u)

all_branches=$(printf '%s\n' "$local_branches" "$remote_branches" | awk 'NF && !seen[$0]++')

existing_wts=$(git -C "$repo_path" worktree list --porcelain 2>/dev/null \
  | awk '/^branch refs\/heads\//{sub("branch refs/heads/", ""); print}' || true)

# Pre-compute status for all existing worktrees in one pass (avoids per-branch subprocesses).
STATUS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/tmux-worktree/status"
declare -A wt_set=()
while IFS= read -r w; do
  [ -z "$w" ] && continue
  wt_set["$w"]=1
  safe="${w//\//-}"
  hash=$(printf '%s' "$repo_path/$safe" | md5 -q 2>/dev/null || printf '%s' "$repo_path/$safe" | md5sum 2>/dev/null | cut -d' ' -f1)
  hash="${hash:0:12}"
  if [ -f "$STATUS_DIR/$hash" ]; then
    wt_set["$w"]=$(cat "$STATUS_DIR/$hash")
  else
    wt_set["$w"]="stopped"
  fi
done <<< "$existing_wts"

annotated=$(echo "$all_branches" | while IFS= read -r b; do
  [ -z "$b" ] && continue
  status="${wt_set[$b]:-}"
  if [ -n "$status" ]; then
    case "$status" in
      idle)       printf '%s  \033[32m● idle\033[0m\n' "$b" ;;
      busy)       printf '%s  \033[33m● busy\033[0m\n' "$b" ;;
      error)      printf '%s  \033[31m● error\033[0m\n' "$b" ;;
      permission) printf '%s  \033[34m● permission\033[0m\n' "$b" ;;
      *)          printf '%s  \033[90m○ stopped\033[0m\n' "$b" ;;
    esac
  else
    printf '%s\n' "$b"
  fi
done)

branch=$(printf '%s\n' "[+ new branch]" "$annotated" | "$FZF_BIN" \
  --prompt="branch > " \
  --header="Select branch for $repo (or create new)" \
  --reverse \
  --ansi) || exit 0

# Strip annotation (fzf --ansi strips ANSI codes from output, so match plain text).
branch=$(printf '%s' "$branch" | sed 's/  [●○] [a-z]*$//')

if [ "$branch" = "[+ new branch]" ]; then
  branch=$(printf '' | "$FZF_BIN" \
    --prompt="new branch name > " \
    --header="Type a new branch name and press Enter" \
    --print-query --reverse 2>/dev/null | head -1) || true
  [ -z "$branch" ] && exit 0
  new_branch=true
else
  new_branch=false
fi

# ---------------------------------------------------------------------------
# Step 3: Create / reuse the worktree
# ---------------------------------------------------------------------------
safe_branch="${branch//\//-}"
worktree_path="$repo_path/$safe_branch"

if [ -d "$worktree_path" ]; then
  :
elif [ "$new_branch" = true ]; then
  git -C "$repo_path" worktree add -b "$branch" "$worktree_path" \
    || die "Failed to create worktree for new branch '$branch'"
else
  if git -C "$repo_path" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    git -C "$repo_path" worktree add "$worktree_path" "$branch" \
      || die "Failed to create worktree for branch '$branch'"
  else
    git -C "$repo_path" worktree add -b "$branch" "$worktree_path" "origin/$branch" \
      || git -C "$repo_path" worktree add "$worktree_path" "$branch" \
      || die "Failed to create worktree for branch '$branch'"
  fi
fi

# ---------------------------------------------------------------------------
# Step 4: Open windows in both sessions (or focus existing ones)
# ---------------------------------------------------------------------------
window_name="${repo}:${safe_branch}"

# Helper: find existing window index by name in a session.
# Matches exact name OR truncated names (ending with ...).
find_window() {
  local session="$1" name="$2"
  tmux list-windows -t "$session" -F '#{window_index}:#{window_name}' 2>/dev/null | while IFS=: read -r idx wname; do
    if [ "$wname" = "$name" ]; then
      echo "$idx"
      return
    fi
    # Match truncated names: "foo..." matches "foobar"
    truncated="${wname%...}"
    if [ "$truncated" != "$wname" ] && [ "${name#"$truncated"}" != "$name" ]; then
      echo "$idx"
      return
    fi
  done
}

# Only create windows if they don't already exist.
existing_oc=$(find_window "opencode" "$window_name") || true
existing_nv=$(find_window "neovim" "$window_name") || true

[ -z "$existing_oc" ] && ensure_session "opencode" "$window_name" "$worktree_path" "$OPENCODE_BIN"
[ -z "$existing_nv" ] && ensure_session "neovim"   "$window_name" "$worktree_path" "$NVIM_BIN"

# Move windows to index 1 in both sessions.
for s in opencode neovim; do
  win_idx=$(find_window "$s" "$window_name") || true
  if [ -n "$win_idx" ] && [ "$win_idx" != "1" ]; then
    tmux swap-window -s "${s}:${win_idx}" -t "${s}:1" 2>/dev/null \
      || tmux move-window -s "${s}:${win_idx}" -t "${s}:1" 2>/dev/null || true
  fi
  tmux select-window -t "${s}:1" 2>/dev/null || true
done

# Persist for restore after reboot.
save_state "$repo_path" "$branch" "$safe_branch" "$worktree_path"

# Switch to the opencode session.
tmux switch-client -t "opencode"
