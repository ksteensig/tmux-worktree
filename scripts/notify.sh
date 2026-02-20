#!/usr/bin/env bash
set -euo pipefail

# tmux-worktree notification daemon
# Polls status files and sends macOS notifications + sounds on state transitions.
# Designed to run as a background process, started once by worktree.tmux.

STATUS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/tmux-worktree/status"
POLL_INTERVAL=2

# macOS system sounds per event type.
SOUND_PERMISSION="/System/Library/Sounds/Funk.aiff"
SOUND_DONE="/System/Library/Sounds/Glass.aiff"
SOUND_ERROR="/System/Library/Sounds/Sosumi.aiff"

# Associative array to track previous status per file.
declare -A prev_status

send_notification() {
  local title="$1" message="$2" sound="$3"
  osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null &
  afplay "$sound" 2>/dev/null
}

# Resolve a status file hash back to a session name by checking active sessions.
session_label_for_hash() {
  local target_hash="$1"
  while IFS= read -r session_name; do
    [[ "$session_name" != */* ]] && continue
    local pane_path
    pane_path=$(tmux display-message -t "=${session_name}:opencode" -p '#{pane_current_path}' 2>/dev/null || true)
    [ -z "$pane_path" ] && continue
    local hash
    hash=$(printf '%s' "$pane_path" | md5 -q 2>/dev/null || printf '%s' "$pane_path" | md5sum 2>/dev/null | cut -d' ' -f1)
    hash="${hash:0:12}"
    if [ "$hash" = "$target_hash" ]; then
      printf '%s' "$session_name"
      return
    fi
  done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)
  # Fallback: just use the hash.
  printf '%s' "$target_hash"
}

while true; do
  if [ -d "$STATUS_DIR" ]; then
    for file in "$STATUS_DIR"/*; do
      [ -f "$file" ] || continue
      hash=$(basename "$file")
      status=$(cat "$file" 2>/dev/null || true)
      [ -z "$status" ] && continue

      prev="${prev_status[$hash]:-unknown}"

      if [ "$status" != "$prev" ]; then
        case "$status" in
          permission)
            label=$(session_label_for_hash "$hash")
            send_notification "OpenCode — Permission" "$label needs approval" "$SOUND_PERMISSION"
            ;;
          idle)
            if [ "$prev" = "busy" ]; then
              label=$(session_label_for_hash "$hash")
              send_notification "OpenCode — Done" "$label is waiting for input" "$SOUND_DONE"
            fi
            ;;
          error)
            label=$(session_label_for_hash "$hash")
            send_notification "OpenCode — Error" "$label encountered an error" "$SOUND_ERROR"
            ;;
        esac
        prev_status[$hash]="$status"
      fi
    done

    # Clean up tracked entries for files that no longer exist.
    for hash in "${!prev_status[@]}"; do
      if [ ! -f "$STATUS_DIR/$hash" ]; then
        unset "prev_status[$hash]"
      fi
    done
  fi

  sleep "$POLL_INTERVAL"
done
