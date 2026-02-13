#!/usr/bin/env bash
set -euo pipefail

# tmux-worktree: pick a repo, pick/create a branch, create a git worktree,
# open a dedicated tmux session with opencode, neovim, and zsh windows.

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

save_state() {
  mkdir -p "$STATE_DIR"
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$STATE_FILE"
  sort -u -o "$STATE_FILE" "$STATE_FILE"
}

create_session() {
  local session_name="$1" dir="$2"
  # Create session with first window: opencode
  tmux new-session -d -s "$session_name" -n "opencode" -c "$dir" "$OPENCODE_BIN"
  tmux set-option -t "=${session_name}:opencode" automatic-rename off 2>/dev/null || true

  # Second window: neovim
  tmux new-window -t "=$session_name" -n "neovim" -c "$dir" "$NVIM_BIN"
  tmux set-option -t "=${session_name}:neovim" automatic-rename off 2>/dev/null || true

  # Third window: zsh
  tmux new-window -t "=$session_name" -n "zsh" -c "$dir"
  tmux set-option -t "=${session_name}:zsh" automatic-rename off 2>/dev/null || true

  # Select the opencode window by default.
  tmux select-window -t "=${session_name}:opencode"
}

# ---------------------------------------------------------------------------
# Step 1: Pick a repo
# ---------------------------------------------------------------------------
repos=()
for d in "$BASE_DIR"/*/; do
  [ -d "$d" ] || continue
  is_git_repo "$d" && repos+=("$(basename "$d")")
done

repo=$(printf '%s\n' "[+ new repo]" ${repos[@]+"${repos[@]}"} | "$FZF_BIN" \
  --prompt="repo > " \
  --header="Select a repository" \
  --reverse) || exit 0

if [ "$repo" = "[+ new repo]" ]; then
  repo=$(printf '' | "$FZF_BIN" \
    --prompt="new repo name > " \
    --header="Type a name for the new repository and press Enter" \
    --print-query --reverse 2>/dev/null | head -1) || true
  [ -z "$repo" ] && exit 0

  # Validate: only allow simple names (alphanumeric, dot, hyphen, underscore).
  [[ "$repo" =~ ^[a-zA-Z0-9._-]+$ ]] || die "Invalid repo name: '$repo'"

  repo_path="$BASE_DIR/$repo"
  [ -d "$repo_path" ] && die "Directory '$repo_path' already exists"

  # Create a bare git repo for worktree-based workflows.
  # The bare repo holds git internals; all work happens in worktree subdirectories.
  git init --bare "$repo_path" --initial-branch=main \
    || { rm -rf "$repo_path"; die "Failed to initialise bare repository at '$repo_path'"; }

  # Fresh repo — skip branch picker and use the initial branch directly.
  branch="main"
  new_branch=true
else
  repo_path="$BASE_DIR/$repo"
fi

# ---------------------------------------------------------------------------
# Step 2: Pick a branch (or create new) — skipped for brand-new repos
# ---------------------------------------------------------------------------
if [ -z "${branch:-}" ]; then
  git -C "$repo_path" fetch --all --prune --quiet 2>/dev/null &

  local_branches=$(git -C "$repo_path" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null || true)
  remote_branches=$(git -C "$repo_path" for-each-ref --format='%(refname:short)' refs/remotes/ 2>/dev/null \
    | sed 's|^[^/]*/||' | { grep -v '^HEAD$' || true; } | sort -u)

  all_branches=$(printf '%s\n' "$local_branches" "$remote_branches" | awk 'NF && !seen[$0]++')

  existing_wts=$(git -C "$repo_path" worktree list --porcelain 2>/dev/null \
    | awk '/^branch refs\/heads\//{sub("branch refs/heads/", ""); print}' || true)

  # Pre-compute status for existing worktrees.
  STATUS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/tmux-worktree/status"
  declare -A wt_set=()
  while IFS= read -r w; do
    [ -z "$w" ] && continue
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
    st="${wt_set[$b]:-}"
    if [ -n "$st" ]; then
      case "$st" in
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

  if [ -n "$annotated" ]; then
    branch_list=$(printf '%s\n' "[+ new branch]" "$annotated")
  else
    branch_list="[+ new branch]"
  fi

  branch=$(printf '%s\n' "$branch_list" | "$FZF_BIN" \
    --prompt="branch > " \
    --header="Select branch for $repo (or create new)" \
    --reverse \
    --ansi) || exit 0

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
    || git -C "$repo_path" worktree add --orphan -b "$branch" "$worktree_path" \
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
# Step 4: Create or switch to session
# ---------------------------------------------------------------------------
session_name="${repo}/${safe_branch}"

if tmux has-session -t "=$session_name" 2>/dev/null; then
  # Session already exists, just switch to it.
  tmux switch-client -t "=$session_name"
else
  create_session "$session_name" "$worktree_path"
  save_state "$repo_path" "$branch" "$safe_branch" "$worktree_path"
  tmux switch-client -t "=$session_name"
fi
