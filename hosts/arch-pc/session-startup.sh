#!/usr/bin/env bash
set -euo pipefail

exec 9>"$XDG_RUNTIME_DIR/arch-pc-session-startup.lock"
flock -n 9 || exit 0

find_window() {
  niri msg --json windows | jq -r --arg app_id "$1" --arg title "$2" '
    [.[] | select(.app_id == $app_id and ($title == "" or .title == $title))]
    | min_by(.id) | .id // empty
  '
}

next_workspace() {
  # Select the trailing empty workspace without focusing it or reserving a name.
  workspace_id=$(niri msg --json workspaces | jq -er --arg output "$output_name" '
    [.[] | select(.output == $output)] | max_by(.idx) | .id
  ')
}

workspace_index() {
  niri msg --json workspaces | jq -er --argjson id "$workspace_id" '
    .[] | select(.id == $id) | .idx
  '
}

restore_app() {
  local width=$1 app_id=$2 title=$3
  shift 3
  local window_id attempt target_index

  window_id=$(find_window "$app_id" "$title") || return 1
  if [[ -z "$window_id" ]]; then
    # Spawn through the compositor to retain the configured user-profile wrappers.
    niri msg action spawn -- "$@" >/dev/null || return 1
  fi

  for ((attempt = 0; attempt < 100; attempt++)); do
    window_id=$(find_window "$app_id" "$title") || return 1
    if [[ -n "$window_id" ]]; then
      # Feishu has an empty app ID; wait for its title before placing the window.
      # Track workspace IDs because dynamic workspace indices can change mid-startup.
      if ! target_index=$(workspace_index); then
        next_workspace || return 1
        target_index=$(workspace_index) || return 1
      fi
      niri msg action move-window-to-workspace --window-id "$window_id" --focus false "$target_index" >/dev/null || return 1
      niri msg action set-window-width --id "$window_id" "$width" >/dev/null || return 1
      return 0
    fi
    sleep 0.2
  done

  echo "Timed out waiting for $1" >&2
  return 1
}

terminal_directory="$HOME/dev/tool/vehicleApiMock"
if [[ ! -d "$terminal_directory" ]]; then
  terminal_directory=$HOME
fi

# Continue restoring the remaining applications if one fails to open.
workspaces=$(niri msg --json workspaces)
output_name=$(jq -er '.[] | select(.is_focused) | .output' <<<"$workspaces")
workspace_id=$(jq -er --arg output "$output_name" '
  [.[] | select(.output == $output)] | min_by(.idx) | .id
' <<<"$workspaces")
restore_app 50% '' '飞书' bytedance-feishu || echo 'Could not restore Feishu' >&2
restore_app 50% chromium-browser '' chromium --restore-last-session || echo 'Could not restore Chromium' >&2
next_workspace
restore_app 50% kitty '' kitty --directory "$terminal_directory" || echo 'Could not restore Kitty' >&2
restore_app 100% brave-browser '' brave --restore-last-session || echo 'Could not restore Brave' >&2
next_workspace
restore_app 50% chatgpt '' chatgpt-desktop || echo 'Could not restore ChatGPT' >&2
restore_app 50% org.telegram.desktop '' Telegram || echo 'Could not restore Telegram' >&2
