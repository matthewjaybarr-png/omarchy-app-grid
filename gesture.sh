#!/usr/bin/env bash
# Install (or remove) the 3-finger swipe gesture.
#
#   ./gesture.sh on    copy the snippet in and reload Hyprland
#   ./gesture.sh off   remove it and reload
#
# Omarchy's toggle loader sources every *.lua in the toggles directory on
# each Hyprland reload, so the snippet is COPIED rather than symlinked --
# the loader uses `find -type f`, which skips symlinks. Nothing under
# ~/.config/hypr is touched.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
toggles="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/toggles/hypr"
target="$toggles/omarchy-app-grid.lua"

case "${1:-on}" in
  on)  mkdir -p "$toggles"; cp "$here/hypr/launcher-gesture.lua" "$target" ;;
  off) rm -f "$target" ;;
  *)   echo "usage: $0 [on|off]" >&2; exit 2 ;;
esac

hyprctl reload >/dev/null
errors=$(hyprctl configerrors)
if [[ -n ${errors//[[:space:]]/} ]]; then
  echo "Hyprland config errors:" >&2
  echo "$errors" >&2
  exit 1
fi
echo "gesture ${1:-on}"
