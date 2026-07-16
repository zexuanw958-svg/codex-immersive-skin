#!/bin/bash

set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd -P)/common-macos.sh"

PORT=9341
CREATE_LAUNCHERS="true"
LAUNCH_AFTER_INSTALL="true"
IN_PLACE="false"
PREVIOUS_INSTALL="${CODEX_IMMERSIVE_PREVIOUS_INSTALL:-}"
DEPLOY_TRANSACTION_ACTIVE="${CODEX_IMMERSIVE_DEPLOY_TRANSACTION:-false}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --port) PORT="${2:-}"; shift 2 ;;
    --no-launchers) CREATE_LAUNCHERS="false"; shift ;;
    --no-launch) LAUNCH_AFTER_INSTALL="false"; shift ;;
    --in-place) IN_PLACE="true"; shift ;;
    *) fail "Unknown installer argument: $1" ;;
  esac
done
case "$PORT" in ''|*[!0-9]*) fail "Invalid port: $PORT" ;; esac
[ "$PORT" -ge 1024 ] && [ "$PORT" -le 65535 ] || fail "Port must be between 1024 and 65535."

deploy_project() {
  local temporary="$INSTALL_ROOT.installing.$$"
  local previous="$INSTALL_ROOT.previous.$$"
  /bin/rm -rf "$temporary"
  /bin/mkdir -p "$temporary"
  /usr/bin/rsync -a \
    --exclude '.git/' \
    --exclude '.DS_Store' \
    --exclude 'release/' \
    --exclude 'runtime/' \
    "$PROJECT_ROOT/" "$temporary/"
  /bin/chmod 700 "$temporary"/*.command "$temporary"/scripts/*.sh 2>/dev/null || true
  if [ -e "$INSTALL_ROOT" ]; then
    /bin/mv "$INSTALL_ROOT" "$previous"
    PREVIOUS_INSTALL="$previous"
  fi
  if ! /bin/mv "$temporary" "$INSTALL_ROOT"; then
    [ -e "$previous" ] && /bin/mv "$previous" "$INSTALL_ROOT"
    fail "Could not install the project at $INSTALL_ROOT"
  fi
}

rollback_deployed_install_on_exit() {
  local code="$?"
  local failed_install
  trap - EXIT
  if [ "$code" -eq 0 ] || [ "$DEPLOY_TRANSACTION_ACTIVE" != "true" ]; then return; fi
  failed_install="$INSTALL_ROOT.failed.$$"
  if [ -e "$INSTALL_ROOT" ]; then /bin/mv "$INSTALL_ROOT" "$failed_install" 2>/dev/null || true; fi
  if [ -n "$PREVIOUS_INSTALL" ] && [ -d "$PREVIOUS_INSTALL" ]; then
    /bin/mv "$PREVIOUS_INSTALL" "$INSTALL_ROOT" 2>/dev/null || true
  fi
  /bin/rm -rf "$failed_install"
  exit "$code"
}

if [ "$IN_PLACE" = "false" ] && [ "$PROJECT_ROOT" != "$INSTALL_ROOT" ]; then
  /bin/mkdir -p "$(dirname "$INSTALL_ROOT")"
  deploy_project
  DEPLOY_TRANSACTION_ACTIVE="true"
  trap rollback_deployed_install_on_exit EXIT
  install_args=(--in-place --port "$PORT")
  [ "$CREATE_LAUNCHERS" = "true" ] || install_args+=(--no-launchers)
  [ "$LAUNCH_AFTER_INSTALL" = "true" ] || install_args+=(--no-launch)
  CODEX_IMMERSIVE_PREVIOUS_INSTALL="$PREVIOUS_INSTALL" CODEX_IMMERSIVE_DEPLOY_TRANSACTION="true" \
    exec "$INSTALL_ROOT/scripts/install-dream-skin-macos.sh" "${install_args[@]}"
fi

if [ "$DEPLOY_TRANSACTION_ACTIVE" = "true" ]; then
  trap rollback_deployed_install_on_exit EXIT
fi

discover_codex_app
require_macos_runtime
ensure_state_root
[ -f "$CONFIG_PATH" ] || fail "Codex config not found: $CONFIG_PATH. Launch Codex once, close it, and rerun the installer."
PAYLOAD_JSON="$("$NODE" "$INJECTOR" --check-payload --theme-dir "$THEME_DIR")"
INSTALL_APPEARANCE="$("$NODE" -e '
  const payload = JSON.parse(process.argv[1]);
  process.stdout.write(payload.appearance === "light" ? "light" : "dark");
' "$PAYLOAD_JSON")"

LAUNCHERS=(
  "$HOME/Desktop/Codex Immersive Skin.command"
  "$HOME/Desktop/Codex Immersive Skin - Customize.command"
  "$HOME/Desktop/Codex Immersive Skin - Verify.command"
  "$HOME/Desktop/Codex Immersive Skin - Restore.command"
)
ROLLBACK_DIR="$STATE_ROOT/install-rollback.$$"
INSTALL_TRANSACTION_ACTIVE="true"
BACKUP_PREEXISTED="false"
[ -f "$THEME_BACKUP_PATH" ] && BACKUP_PREEXISTED="true"
/bin/rm -rf "$ROLLBACK_DIR"
/bin/mkdir -p "$ROLLBACK_DIR/launchers"
/bin/chmod 700 "$ROLLBACK_DIR" "$ROLLBACK_DIR/launchers"
/bin/cp -p "$CONFIG_PATH" "$ROLLBACK_DIR/config.toml"
for launcher in "${LAUNCHERS[@]}"; do
  if [ -e "$launcher" ]; then
    /bin/cp -p "$launcher" "$ROLLBACK_DIR/launchers/$(/usr/bin/basename "$launcher")"
  fi
done

rollback_install() {
  local code="$?"
  local launcher backup failed_install
  trap - EXIT
  if [ "$code" -eq 0 ] || [ "$INSTALL_TRANSACTION_ACTIVE" != "true" ]; then return; fi
  if [ -f "$ROLLBACK_DIR/config.toml" ]; then
    /bin/cp -p "$ROLLBACK_DIR/config.toml" "$CONFIG_PATH" 2>/dev/null || true
  fi
  if [ "$BACKUP_PREEXISTED" = "false" ]; then /bin/rm -f "$THEME_BACKUP_PATH"; fi
  for launcher in "${LAUNCHERS[@]}"; do
    backup="$ROLLBACK_DIR/launchers/$(/usr/bin/basename "$launcher")"
    /bin/rm -f "$launcher"
    [ -f "$backup" ] && /bin/cp -p "$backup" "$launcher"
  done
  if [ -n "$PREVIOUS_INSTALL" ] && [ -d "$PREVIOUS_INSTALL" ]; then
    failed_install="$INSTALL_ROOT.failed.$$"
    /bin/mv "$INSTALL_ROOT" "$failed_install" 2>/dev/null || true
    /bin/mv "$PREVIOUS_INSTALL" "$INSTALL_ROOT" 2>/dev/null || true
    /bin/rm -rf "$failed_install"
  elif [ "$PROJECT_ROOT" = "$INSTALL_ROOT" ]; then
    /bin/rm -rf "$INSTALL_ROOT"
  fi
  /bin/rm -rf "$ROLLBACK_DIR"
  exit "$code"
}
trap rollback_install EXIT

"$NODE" "$SCRIPT_DIR/theme-config.mjs" install "$CONFIG_PATH" "$THEME_BACKUP_PATH" \
  --appearance "$INSTALL_APPEARANCE"

shell_quote() {
  "$NODE" -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"
}

write_launcher() {
  local target="$1"
  local command="$2"
  if [ -e "$target" ] && ! /usr/bin/grep -q '^# CodexImmersiveSkin launcher$' "$target" 2>/dev/null; then
    fail "Refusing to overwrite an unrelated Desktop file: $target"
  fi
  /usr/bin/printf '%s\n' \
    '#!/bin/bash' \
    '# CodexImmersiveSkin launcher' \
    'set -e' \
    "$command" > "$target"
  /bin/chmod 700 "$target"
}

if [ "$CREATE_LAUNCHERS" = "true" ]; then
  /bin/mkdir -p "$HOME/Desktop"
  start_script="$(shell_quote "$SCRIPT_DIR/start-dream-skin-macos.sh")"
  customize_script="$(shell_quote "$SCRIPT_DIR/customize-theme-macos.sh")"
  verify_script="$(shell_quote "$SCRIPT_DIR/verify-dream-skin-macos.sh")"
  restore_script="$(shell_quote "$SCRIPT_DIR/restore-dream-skin-macos.sh")"
  screenshot="$(shell_quote "$HOME/Desktop/Codex Immersive Skin Verification.png")"
  write_launcher "${LAUNCHERS[0]}" "exec $start_script --prompt-restart"
  write_launcher "${LAUNCHERS[1]}" "exec $customize_script"
  write_launcher "${LAUNCHERS[2]}" "$verify_script --screenshot $screenshot && /usr/bin/open $screenshot"
  write_launcher "${LAUNCHERS[3]}" "exec $restore_script --restore-base-theme --restart-codex"
fi

if [ "$LAUNCH_AFTER_INSTALL" = "true" ]; then
  "$SCRIPT_DIR/start-dream-skin-macos.sh" --port "$PORT" --prompt-restart
else
  preferred_tmp="$PREFERRED_PORT_PATH.$$.tmp"
  /usr/bin/printf '%s\n' "$PORT" > "$preferred_tmp"
  /bin/chmod 600 "$preferred_tmp"
  /bin/mv -f "$preferred_tmp" "$PREFERRED_PORT_PATH"
fi

/bin/rm -rf "$ROLLBACK_DIR"
[ -n "$PREVIOUS_INSTALL" ] && /bin/rm -rf "$PREVIOUS_INSTALL"
INSTALL_TRANSACTION_ACTIVE="false"
trap - EXIT
printf 'Codex Immersive Skin %s installed at %s for Codex %s using its signed Node.js %s.\n' \
  "$SKIN_VERSION" "$PROJECT_ROOT" "$CODEX_VERSION" "$NODE_VERSION"
printf 'Use the Desktop launchers to customize, start, verify, or restore the original appearance.\n'
