#!/usr/bin/env bash
set -euo pipefail

# tmux-worktree workspace: pick a remote workspace (SSH host or k8s pod)
# and open it in a dedicated tmux session.
#
# SSH hosts are read from ~/.ssh/config.
# Kubernetes pods are listed via kubectl with a configurable filter.
#
# Configuration (tmux options):
#   @worktree-k8s-namespace   — kubectl namespace (default: "default")
#   @worktree-k8s-pod-filter  — grep pattern to filter pod names (default: "" = all pods)
#   @worktree-fzf-bin         — path to fzf binary

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

K8S_NAMESPACE=$(tmux show-option -gqv @worktree-k8s-namespace 2>/dev/null || true)
K8S_NAMESPACE="${K8S_NAMESPACE:-default}"

K8S_POD_FILTER=$(tmux show-option -gqv @worktree-k8s-pod-filter 2>/dev/null || true)

SSH_CONFIG="${SSH_CONFIG:-$HOME/.ssh/config}"

die() { printf 'tmux-worktree: %s\n' "$*" >&2; exit 1; }

[ -z "$FZF_BIN" ] || [ ! -x "$FZF_BIN" ] && die "fzf not found"

# ---------------------------------------------------------------------------
# Step 1: Build list of workspaces
# ---------------------------------------------------------------------------
entries=""

# SSH hosts from ~/.ssh/config (skip wildcards like * and ?)
if [ -f "$SSH_CONFIG" ]; then
  while IFS= read -r line; do
    host=$(printf '%s' "$line" | awk '{print $2}')
    [ -z "$host" ] && continue
    [[ "$host" == *"*"* || "$host" == *"?"* ]] && continue
    entry="$host  (ssh)"
    if [ -z "$entries" ]; then
      entries="$entry"
    else
      entries="$entries"$'\n'"$entry"
    fi
  done < <(grep -i '^Host ' "$SSH_CONFIG" 2>/dev/null || true)
fi

# Kubernetes pods.
if [ -n "$KUBECTL_BIN" ] && [ -x "$KUBECTL_BIN" ]; then
  pod_list=$("$KUBECTL_BIN" get pods -n "$K8S_NAMESPACE" -o name 2>/dev/null \
    | sed 's|^pod/||' || true)

  # Apply filter if configured.
  if [ -n "$K8S_POD_FILTER" ] && [ -n "$pod_list" ]; then
    pod_list=$(printf '%s\n' "$pod_list" | grep -E "$K8S_POD_FILTER" || true)
  fi

  while IFS= read -r pod; do
    [ -z "$pod" ] && continue
    entry="$pod  (kubectl exec)"
    if [ -z "$entries" ]; then
      entries="$entry"
    else
      entries="$entries"$'\n'"$entry"
    fi
  done <<< "$pod_list"
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
kind=$(printf '%s' "$selected" | sed 's/.*(\(.*\))/\1/')

if [ "$kind" = "ssh" ]; then
  session_name="workspace/${name}"
  cmd="ssh ${name}"
else
  session_name="workspace/${name}"
  cmd="kubectl exec -n ${K8S_NAMESPACE} -it ${name} -- bash"
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
