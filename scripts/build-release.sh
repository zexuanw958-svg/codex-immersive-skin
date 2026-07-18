#!/bin/bash

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
VERSION="$(/usr/bin/tr -d '[:space:]' < "$ROOT/VERSION")"
RELEASE_DIR="$ROOT/release"
ARCHIVE="$RELEASE_DIR/codex-immersive-skin-v$VERSION.zip"
TMP="$(/usr/bin/mktemp -d /tmp/codex-immersive-skin-release.XXXXXX)"
PACKAGE_ROOT="$TMP/codex-immersive-skin"
trap '/bin/rm -rf "$TMP"' EXIT

if [ "${1:-}" != "--skip-tests" ]; then "$ROOT/tests/run-tests.sh"; fi

FILES=(
  ".gitignore"
  "CHANGELOG.md"
  "Customize Codex Immersive Skin.command"
  "Customize Codex Immersive Skin.cmd"
  "Install Codex Immersive Skin.command"
  "Install Codex Immersive Skin.cmd"
  "LICENSE"
  "NOTICE.md"
  "README.md"
  "Restore Codex Immersive Skin.command"
  "Restore Codex Immersive Skin.cmd"
  "SKILL.md"
  "Start Codex Immersive Skin.command"
  "Start Codex Immersive Skin.cmd"
  "VERSION"
  "Verify Codex Immersive Skin.command"
  "Verify Codex Immersive Skin.cmd"
  "package.json"
  "agents/openai.yaml"
  "assets/dream-skin.css"
  "assets/morning-mist.png"
  "assets/renderer-inject.js"
  "assets/theme.json"
  "docs/windows/README.md"
  "docs/windows/适配报告.md"
  "docs/windows/观众部署提示词.md"
  "examples/warm-sand/background.png"
  "examples/warm-sand/theme.json"
  "references/asset-provenance.md"
  "references/generated-assets/morning-mist.svg"
  "references/generated-assets/warm-sand.svg"
  "references/qa-inventory.md"
  "references/runtime-notes.md"
  "scripts/analyze-image.mjs"
  "scripts/build-release.sh"
  "scripts/common-macos.sh"
  "scripts/common-windows.ps1"
  "scripts/customize-theme-macos.sh"
  "scripts/customize-theme-windows.ps1"
  "scripts/doctor-macos.sh"
  "scripts/doctor-windows.ps1"
  "scripts/injector.mjs"
  "scripts/install-dream-skin-macos.sh"
  "scripts/install-dream-skin-windows.ps1"
  "scripts/lifecycle-windows.ps1"
  "scripts/normalize-image-windows.ps1"
  "scripts/restore-dream-skin-macos.sh"
  "scripts/restore-dream-skin-windows.ps1"
  "scripts/run-tests.mjs"
  "scripts/start-dream-skin-macos.sh"
  "scripts/start-dream-skin-windows.ps1"
  "scripts/theme-config.mjs"
  "scripts/verify-dream-skin-macos.sh"
  "scripts/verify-dream-skin-windows.ps1"
  "scripts/write-theme.mjs"
  "tests/adaptive-theme.test.mjs"
  "tests/auto-palette.test.mjs"
  "tests/run-tests.sh"
  "tests/run-tests-windows.ps1"
  "tests/windows-customize.test.mjs"
  "tests/windows-entrypoints.test.mjs"
  "tests/windows-image.test.mjs"
  "tests/windows-install.test.mjs"
  "tests/windows-lifecycle.test.mjs"
  "tests/windows-regressions.test.mjs"
  "tests/windows-runtime.test.mjs"
  "tests/write-theme-safety.test.mjs"
)

/bin/mkdir -p "$PACKAGE_ROOT" "$RELEASE_DIR"
for relative in "${FILES[@]}"; do
  [ -f "$ROOT/$relative" ] || { printf 'Required release file is missing: %s\n' "$relative" >&2; exit 1; }
  destination="$PACKAGE_ROOT/$relative"
  /bin/mkdir -p "$(/usr/bin/dirname "$destination")"
  /bin/cp -p "$ROOT/$relative" "$destination"
done

/bin/chmod 755 "$PACKAGE_ROOT"/*.command
/bin/chmod 755 "$PACKAGE_ROOT"/scripts/*.sh "$PACKAGE_ROOT"/tests/*.sh
/bin/rm -f "$ARCHIVE"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr -c -k --keepParent \
  "$PACKAGE_ROOT" "$ARCHIVE"

if /usr/bin/unzip -Z1 "$ARCHIVE" | /usr/bin/grep -Eiq \
  '(^|/)(\._|\.DS_Store$|__MACOSX(/|$)|\.git(/|$)|\.env($|\.)|\.npmrc$|id_(rsa|ed25519)$|[^/]*private[^/]*key[^/]*$|[^/]*\.(pem|p12|mobileprovision)$)'; then
  printf 'Release archive contains a forbidden metadata or credential-like filename.\n' >&2
  exit 1
fi

SHA256="$(/usr/bin/shasum -a 256 "$ARCHIVE" | /usr/bin/awk '{print $1}')"
/usr/bin/printf '%s  %s\n' "$SHA256" "$(basename "$ARCHIVE")" > "$RELEASE_DIR/SHA256SUMS.txt"
/usr/bin/printf 'Created %s\nSHA-256 %s\n' "$ARCHIVE" "$SHA256"
