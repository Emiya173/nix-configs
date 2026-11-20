#!/usr/bin/env bash
set -euo pipefail

exec 9>"$XDG_RUNTIME_DIR/arch-pc-session-startup.lock"
flock -n 9 || exit 0

has_window() {
  umbriel windows --json | jq -e --arg app_id "$1" --arg title "$2" '
    any(.[]; .app_id == $app_id and ($title == "" or .title == $title))
  ' >/dev/null
}

restore_app() {
  local app_id=$1 title=$2 attempt
  shift 2
  has_window "$app_id" "$title" && return 0
  # A long-lived application must not inherit the startup lock.
  "$@" 9>&- &
  for ((attempt = 0; attempt < 40; attempt++)); do
    has_window "$app_id" "$title" && return 0
    sleep 0.2
  done
  echo "Timed out waiting for $1" >&2
  return 1
}

# Continue restoring the remaining applications if one fails to open.
restore_app '' '飞书' bytedance-feishu || echo 'Could not restore Feishu' >&2
restore_app chromium-browser '' chromium --restore-last-session || echo 'Could not restore Chromium' >&2
