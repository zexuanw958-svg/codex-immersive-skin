#!/bin/bash

set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd -P)/common-macos.sh"

START_CONFIG_ROLLBACK=""
START_CONFIG_TRANSACTION="false"
START_BACKUP_PREEXISTED="false"
record_start_error() {
  local code="$1"
  local line="$2"
  ensure_state_root
  printf '%s exit=%s line=%s\n' "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')" "$code" "$line" >> "$START_ERROR_LOG"
  printf 'Codex Immersive Skin: start failed at line %s (exit %s). See %s\n' "$line" "$code" "$START_ERROR_LOG" >&2
}
rollback_start_config_on_exit() {
  local code="$?"
  trap - EXIT
  if [ "$code" -ne 0 ] && [ "$START_CONFIG_TRANSACTION" = "true" ] && [ -f "$START_CONFIG_ROLLBACK" ]; then
    /bin/cp -p "$START_CONFIG_ROLLBACK" "$CONFIG_PATH" 2>/dev/null || true
    [ "$START_BACKUP_PREEXISTED" = "false" ] && /bin/rm -f "$THEME_BACKUP_PATH"
    /bin/rm -f "$START_CONFIG_ROLLBACK"
    START_CONFIG_TRANSACTION="false"
  fi
  exit "$code"
}
trap 'code=$?; record_start_error "$code" "$LINENO"' ERR
trap rollback_start_config_on_exit EXIT

PORT=9341
PORT_EXPLICIT="false"
RESTART_EXISTING="false"
PROMPT_RESTART="false"
FOREGROUND_INJECTOR="false"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --port) PORT="${2:-}"; PORT_EXPLICIT="true"; shift 2 ;;
    --restart-existing) RESTART_EXISTING="true"; shift ;;
    --prompt-restart) PROMPT_RESTART="true"; shift ;;
    --foreground-injector) FOREGROUND_INJECTOR="true"; shift ;;
    *) fail "Unknown start argument: $1" ;;
  esac
done

discover_codex_app
require_macos_runtime
ensure_state_root

if [ "$PORT_EXPLICIT" = "false" ]; then
  if [ -f "$STATE_PATH" ]; then
    saved_port="$(state_field port)" || fail "Could not read the existing state port."
    [ -n "$saved_port" ] && PORT="$saved_port"
  elif [ -f "$PREFERRED_PORT_PATH" ]; then
    preferred_port="$(/usr/bin/tr -d '[:space:]' < "$PREFERRED_PORT_PATH")"
    [ -n "$preferred_port" ] && PORT="$preferred_port"
  fi
fi
case "$PORT" in ''|*[!0-9]*) fail "Invalid port: $PORT" ;; esac
[ "$PORT" -ge 1024 ] && [ "$PORT" -le 65535 ] || fail "Port must be between 1024 and 65535."

DEBUG_READY="false"
if verified_cdp_endpoint "$PORT"; then DEBUG_READY="true"; fi

if codex_is_running && [ "$DEBUG_READY" = "false" ]; then
  if [ "$PROMPT_RESTART" = "true" ] && [ "$RESTART_EXISTING" = "false" ]; then
    /usr/bin/osascript -e 'display dialog "Codex 需要重启一次才能启用 Immersive Skin。" buttons {"取消", "重启并应用"} default button "重启并应用" with title "Codex Immersive Skin"' >/dev/null \
      || fail "Theme launch was cancelled."
    RESTART_EXISTING="true"
  fi
  [ "$RESTART_EXISTING" = "true" ] || fail "Codex is already running without the verified skin CDP endpoint. Close it first or pass --restart-existing."
  stop_codex true
fi

THEME_APPEARANCE="$("$NODE" "$INJECTOR" --check-payload --theme-dir "$THEME_DIR" \
  | "$NODE" -e '
      let input = "";
      process.stdin.setEncoding("utf8");
      process.stdin.on("data", (chunk) => { input += chunk; });
      process.stdin.on("end", () => {
        const payload = JSON.parse(input);
        process.stdout.write(payload.appearance === "light" ? "light" : "dark");
      });
    ')"
START_CONFIG_ROLLBACK="$STATE_ROOT/config-before-start.$$"
[ -f "$THEME_BACKUP_PATH" ] && START_BACKUP_PREEXISTED="true"
/bin/cp -p "$CONFIG_PATH" "$START_CONFIG_ROLLBACK"
START_CONFIG_TRANSACTION="true"
"$NODE" "$SCRIPT_DIR/theme-config.mjs" install "$CONFIG_PATH" "$THEME_BACKUP_PATH" \
  --appearance "$THEME_APPEARANCE" >/dev/null

if [ "$DEBUG_READY" = "false" ]; then
  PORT="$(select_available_port "$PORT")"
  launch_codex_with_cdp "$PORT"
  wait_for_cdp "$PORT" || fail "Codex did not expose a verified loopback CDP endpoint on port $PORT within 35 seconds. See $APP_LOG"
fi

if [ -f "$STATE_PATH" ]; then
  stop_recorded_injector
  /bin/rm -f "$STATE_PATH"
fi

commit_start_transaction() {
  local preferred_tmp="$PREFERRED_PORT_PATH.$$.tmp"
  /usr/bin/printf '%s\n' "$PORT" > "$preferred_tmp"
  /bin/chmod 600 "$preferred_tmp"
  /bin/mv -f "$preferred_tmp" "$PREFERRED_PORT_PATH"
  /bin/rm -f "$START_CONFIG_ROLLBACK"
  START_CONFIG_TRANSACTION="false"
}

if [ "$FOREGROUND_INJECTOR" = "true" ]; then
  commit_start_transaction
  trap - EXIT
  exec "$NODE" "$INJECTOR" --watch --port "$PORT" --theme-dir "$THEME_DIR"
fi

INJECTOR_PID="$(launch_injector_daemon "$PORT")"
/bin/sleep 0.8
/bin/kill -0 "$INJECTOR_PID" 2>/dev/null || fail "The injector exited during startup. See $INJECTOR_ERROR_LOG"
INJECTOR_STARTED_AT="$(process_started_at "$INJECTOR_PID")"
[ -n "$INJECTOR_STARTED_AT" ] || fail "Could not record the injector process start time."
CODEX_PID="$(codex_main_pids | /usr/bin/head -n 1)"
write_state "$PORT" "$INJECTOR_PID" "$INJECTOR_STARTED_AT" "$CODEX_PID"

if ! "$NODE" "$INJECTOR" --verify --port "$PORT" --theme-dir "$THEME_DIR" --timeout-ms 30000 >/dev/null; then
  /bin/launchctl remove "$INJECTOR_JOB_LABEL" >/dev/null 2>&1 || /bin/kill -TERM "$INJECTOR_PID" 2>/dev/null || true
  /bin/rm -f "$STATE_PATH"
  fail "Injection verification failed. The injector was stopped; see $INJECTOR_ERROR_LOG"
fi

commit_start_transaction
trap - EXIT
printf 'Codex Immersive Skin %s is active on loopback port %s.\n' "$SKIN_VERSION" "$PORT"
