#!/usr/bin/env bash
set -euo pipefail

# tmux-worktree workspace: pick a remote workspace (k8s pod or EC2 GPU instance)
# and open it in a dedicated tmux session.

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
FZF_BIN=$(tmux show-option -gqv @worktree-fzf-bin 2>/dev/null || true)
if [ -z "$FZF_BIN" ]; then
  FZF_BIN=$(command -v fzf 2>/dev/null \
    || { [ -x /opt/homebrew/bin/fzf ] && echo /opt/homebrew/bin/fzf; } \
    || { [ -x /usr/local/bin/fzf ] && echo /usr/local/bin/fzf; } \
    || true)
fi

KUBECTL_BIN=$(command -v kubectl 2>/dev/null || true)

die() { printf 'tmux-worktree: %s\n' "$*" >&2; exit 1; }

[ -z "$FZF_BIN" ] || [ ! -x "$FZF_BIN" ] && die "fzf not found"

# ---------------------------------------------------------------------------
# Step 1: Build list of workspaces
# ---------------------------------------------------------------------------
entries=""

# EC2 GPU instance via ssh.
entries="ec2-gpu-instance  (ssh work)"

# Kubernetes workspace pods.
if [ -n "$KUBECTL_BIN" ] && [ -x "$KUBECTL_BIN" ]; then
  pods=$("$KUBECTL_BIN" get pods -n workspace -o name 2>/dev/null \
    | grep 'ksteensig-workspace' \
    | sed 's|^pod/||' || true)

  while IFS= read -r pod; do
    [ -z "$pod" ] && continue
    entries="$entries"$'\n'"$pod  (kubectl exec)"
  done <<< "$pods"
fi

[ -z "$entries" ] && die "No workspaces found"

# ---------------------------------------------------------------------------
# Step 2: Pick a workspace
# ---------------------------------------------------------------------------
selected=$(printf '%s\n' "$entries" | "$FZF_BIN" \
  --prompt="workspace > " \
  --header="Connect to remote workspace" \
  --reverse) || exit 0

[ -z "$selected" ] && exit 0

# ---------------------------------------------------------------------------
# Step 3: Determine command and session name
# ---------------------------------------------------------------------------
name=$(printf '%s' "$selected" | sed 's/  (.*//')

if [ "$name" = "ec2-gpu-instance" ]; then
  session_name="workspace/ec2-gpu"
  cmd="ssh work"
else
  session_name="workspace/${name}"
  cmd="kubectl exec -n workspace -it ${name} -- bash"
fi

# ---------------------------------------------------------------------------
# Step 4: Create or switch to session
# ---------------------------------------------------------------------------
if tmux has-session -t "=$session_name" 2>/dev/null; then
  tmux switch-client -t "=$session_name"
else
  tmux new-session -d -s "$session_name" -n "$name" "$cmd"
  tmux set-option -t "=${session_name}:${name}" automatic-rename off 2>/dev/null || true
  tmux switch-client -t "=$session_name"
fi
