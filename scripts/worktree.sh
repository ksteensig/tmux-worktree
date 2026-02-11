#!/usr/bin/env bash
set -euo pipefail

# tmux-worktree: pick a repo, pick/create a branch, create a git worktree,
# open a new tmux window with opencode in that worktree.

# ---------------------------------------------------------------------------
# Configuration (overridable via tmux options)
# ---------------------------------------------------------------------------
BASE_DIR=$(tmux show-option -gqv @worktree-base-dir)
BASE_DIR="${BASE_DIR:-$HOME/Workspace}"

OPENCODE_BIN=$(tmux show-option -gqv @worktree-opencode-bin)
OPENCODE_BIN="${OPENCODE_BIN:-opencode}"

FZF_BIN=$(tmux show-option -gqv @worktree-fzf-bin)
if [ -z "$FZF_BIN" ]; then
  FZF_BIN=$(command -v fzf 2>/dev/null || echo "/opt/homebrew/opt/fzf/bin/fzf")
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die() { printf 'tmux-worktree: %s\n' "$*" >&2; exit 1; }

is_git_repo() {
  local dir="$1"
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1
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
# Fetch latest refs so remote branches are up to date.
git -C "$repo_path" fetch --all --prune --quiet 2>/dev/null || true

# Build list: local branches first, then remote-only branches.
local_branches=$(git -C "$repo_path" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null || true)
remote_branches=$(git -C "$repo_path" for-each-ref --format='%(refname:short)' refs/remotes/ 2>/dev/null \
  | sed 's|^[^/]*/||' | grep -v '^HEAD$' | sort -u || true)

# Deduplicate: remote branches that already exist locally are excluded.
all_branches=$(printf '%s\n' "$local_branches" "$remote_branches" | awk 'NF && !seen[$0]++')

# Existing worktrees — mark them so the user knows.
existing_wts=$(git -C "$repo_path" worktree list --porcelain 2>/dev/null \
  | awk '/^branch refs\/heads\//{sub("branch refs/heads/", ""); print}' || true)

# Annotate branches that already have worktrees.
annotated=$(echo "$all_branches" | while IFS= read -r b; do
  [ -z "$b" ] && continue
  if echo "$existing_wts" | grep -qxF "$b"; then
    printf '%s  [worktree exists]\n' "$b"
  else
    printf '%s\n' "$b"
  fi
done)

branch=$(printf '%s\n' "[+ new branch]" "$annotated" | "$FZF_BIN" \
  --prompt="branch > " \
  --header="Select branch for $repo (or create new)" \
  --reverse) || exit 0

# Strip the annotation if present.
branch="${branch%%  \[worktree exists\]}"

if [ "$branch" = "[+ new branch]" ]; then
  # Use fzf --print-query to get free-form input.
  branch=$(printf '' | "$FZF_BIN" \
    --prompt="new branch name > " \
    --header="Type a new branch name and press Enter" \
    --print-query --reverse | head -1) || exit 0
  [ -z "$branch" ] && die "No branch name provided"
  new_branch=true
else
  new_branch=false
fi

# ---------------------------------------------------------------------------
# Step 3: Create / reuse the worktree
# ---------------------------------------------------------------------------
# For the directory name, replace slashes with dashes (e.g. feature/foo -> feature-foo)
safe_branch="${branch//\//-}"
worktree_path="$repo_path/$safe_branch"

if [ -d "$worktree_path" ]; then
  # Worktree already exists, just reuse it.
  :
elif [ "$new_branch" = true ]; then
  git -C "$repo_path" worktree add -b "$branch" "$worktree_path" \
    || die "Failed to create worktree for new branch '$branch'"
else
  # Existing branch — check if it's local or remote-only.
  if git -C "$repo_path" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    git -C "$repo_path" worktree add "$worktree_path" "$branch" \
      || die "Failed to create worktree for branch '$branch'"
  else
    # Remote-only: create a local tracking branch.
    git -C "$repo_path" worktree add -b "$branch" "$worktree_path" "origin/$branch" \
      || git -C "$repo_path" worktree add "$worktree_path" "$branch" \
      || die "Failed to create worktree for branch '$branch'"
  fi
fi

# ---------------------------------------------------------------------------
# Step 4: Open a new tmux window and launch opencode
# ---------------------------------------------------------------------------
window_name="${repo}:${safe_branch}"

# Truncate window name if it's too long for the status bar.
if [ ${#window_name} -gt 40 ]; then
  window_name="${window_name:0:37}..."
fi

tmux new-window -n "$window_name" -c "$worktree_path" "$OPENCODE_BIN"
