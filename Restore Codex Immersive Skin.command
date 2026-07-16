#!/bin/bash
set -euo pipefail
INSTALLED="$HOME/.codex/codex-immersive-skin/scripts/restore-dream-skin-macos.sh"
if [ ! -x "$INSTALLED" ]; then
  /usr/bin/osascript -e 'display alert "没有找到已安装的 Codex Immersive Skin。" as warning' >/dev/null
  exit 1
fi
exec "$INSTALLED" --restore-base-theme --restart-codex
