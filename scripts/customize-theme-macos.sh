#!/bin/bash

set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd -P)/common-macos.sh"

IMAGE=""
THEME_NAME=""
TAGLINE=""
QUOTE=""
ACCENT=""
SECONDARY=""
HIGHLIGHT=""
APPEARANCE=""
APPLY_NOW="true"
RESET_DEMO="false"

require_option_value() {
  [ "$#" -ge 2 ] && [ -n "$2" ] || fail "Option $1 requires a non-empty value."
  case "$2" in --*) fail "Option $1 requires a non-empty value." ;; esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --image) require_option_value "$@"; IMAGE="$2"; shift 2 ;;
    --name) require_option_value "$@"; THEME_NAME="$2"; shift 2 ;;
    --tagline) require_option_value "$@"; TAGLINE="$2"; shift 2 ;;
    --quote) require_option_value "$@"; QUOTE="$2"; shift 2 ;;
    --accent) require_option_value "$@"; ACCENT="$2"; shift 2 ;;
    --secondary) require_option_value "$@"; SECONDARY="$2"; shift 2 ;;
    --highlight) require_option_value "$@"; HIGHLIGHT="$2"; shift 2 ;;
    --appearance) require_option_value "$@"; APPEARANCE="$2"; shift 2 ;;
    --no-apply) APPLY_NOW="false"; shift ;;
    --reset-demo) RESET_DEMO="true"; shift ;;
    *) fail "Unknown customize argument: $1" ;;
  esac
done

if [ -n "$APPEARANCE" ]; then
  [ "$APPEARANCE" = "light" ] || [ "$APPEARANCE" = "dark" ] \
    || fail "Appearance must be light or dark."
fi

discover_codex_app
require_macos_runtime
ensure_state_root

if [ "$RESET_DEMO" = "true" ]; then
  "$NODE" "$SCRIPT_DIR/write-theme.mjs" reset-demo --output-dir "$THEME_DIR"
else
  if [ -z "$IMAGE" ]; then
    IMAGE="$(/usr/bin/osascript -e 'POSIX path of (choose file with prompt "选择一张主题图片（建议横向、宽度 2000px 以上）" of type {"public.image"})')" \
      || fail "Image selection was cancelled."
  fi
  [ -f "$IMAGE" ] || fail "Selected image does not exist: $IMAGE"
  SOURCE_BYTES="$(/usr/bin/stat -f '%z' "$IMAGE")"
  [ "$SOURCE_BYTES" -le 52428800 ] || fail "Selected image is larger than 50 MB. Choose a smaller file."

  if [ -z "$THEME_NAME" ]; then
    THEME_NAME="$(/usr/bin/osascript -e 'text returned of (display dialog "给这套主题起个名字" default answer "我的 Codex 主题" buttons {"取消", "继续"} default button "继续")')" \
      || fail "Theme setup was cancelled."
  fi
  if [ -z "$TAGLINE" ]; then TAGLINE="把喜欢的画面变成可交互的 Codex 工作台。"; fi
  if [ -z "$QUOTE" ]; then QUOTE="MAKE SOMETHING WONDERFUL"; fi

  /bin/mkdir -p "$THEME_DIR"
  /bin/chmod 700 "$THEME_DIR"
  image_name="background-$(/bin/date '+%Y%m%d-%H%M%S')-$$.jpg"
  temporary="$THEME_DIR/.${image_name}.tmp.jpg"
  prepared="$THEME_DIR/$image_name"
  theme_write_committed="false"
  cleanup_temporary() {
    /bin/rm -f "$temporary"
    [ "$theme_write_committed" = "true" ] || /bin/rm -f "$prepared"
  }
  trap cleanup_temporary EXIT
  /usr/bin/sips -s format jpeg -s formatOptions 84 -Z 3200 "$IMAGE" --out "$temporary" >/dev/null \
    || fail "macOS could not convert the selected image. Use PNG, JPEG, HEIC, TIFF, or WebP."
  [ -s "$temporary" ] || fail "The converted image is empty."
  PREPARED_BYTES="$(/usr/bin/stat -f '%z' "$temporary")"
  [ "$PREPARED_BYTES" -le 16777216 ] || fail "The prepared image is larger than 16 MB. Choose a simpler or smaller image."
  /bin/mv -f "$temporary" "$prepared"
  /bin/chmod 600 "$prepared"

  style_args=(--image "$prepared" --format tsv)
  [ -z "$APPEARANCE" ] || style_args+=(--appearance "$APPEARANCE")
  [ -z "$ACCENT" ] || style_args+=(--accent "$ACCENT")
  [ -z "$SECONDARY" ] || style_args+=(--secondary "$SECONDARY")
  [ -z "$HIGHLIGHT" ] || style_args+=(--highlight "$HIGHLIGHT")
  if ! resolved_output="$(
    "$NODE" "$SCRIPT_DIR/analyze-image.mjs" "${style_args[@]}"
    analyzer_status=$?
    printf '\034'
    exit "$analyzer_status"
  )"; then
    fail "Automatic theme color analysis could not start."
  fi
  case "$resolved_output" in
    *$'\034') ;;
    *) fail "Automatic theme color analysis returned invalid output." ;;
  esac
  resolved_output="${resolved_output%$'\034'}"
  case "$resolved_output" in
    *$'\n') resolved_style="${resolved_output%$'\n'}" ;;
    *) fail "Automatic theme color analysis returned invalid output." ;;
  esac
  case "$resolved_style" in
    *$'\n'*|*$'\r'*) fail "Automatic theme color analysis returned invalid output." ;;
  esac
  style_without_tabs="${resolved_style//$'\t'/}"
  [ "$(( ${#resolved_style} - ${#style_without_tabs} ))" -eq 3 ] \
    || fail "Automatic theme color analysis returned invalid output."
  IFS=$'\t' read -r APPEARANCE ACCENT SECONDARY HIGHLIGHT <<EOF
$resolved_style
EOF
  [ -n "$APPEARANCE" ] && [ -n "$ACCENT" ] && [ -n "$SECONDARY" ] && [ -n "$HIGHLIGHT" ] \
    || fail "Automatic theme color analysis returned incomplete output."

  "$NODE" "$SCRIPT_DIR/write-theme.mjs" custom \
    --output-dir "$THEME_DIR" --image "$image_name" \
    --name "$THEME_NAME" --tagline "$TAGLINE" --quote "$QUOTE" --appearance "$APPEARANCE" \
    --accent "$ACCENT" --secondary "$SECONDARY" --highlight "$HIGHLIGHT"
  theme_write_committed="true"
  /usr/bin/find "$THEME_DIR" -maxdepth 1 -type f -name 'background-*' ! -name "$image_name" -delete
  trap - EXIT
fi

if [ "$APPLY_NOW" = "true" ]; then
  "$SCRIPT_DIR/start-dream-skin-macos.sh" --prompt-restart
fi

printf 'Codex Immersive Skin theme is ready.\n'
