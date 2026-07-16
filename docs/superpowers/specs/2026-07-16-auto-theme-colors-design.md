# Automatic Theme Colors Design

**Date:** 2026-07-16
**Status:** Approach A approved
**Release state:** The GitHub repository must remain Private

## Goal

Make theme colors follow the selected background without requiring a vision-capable model. When the user omits color or appearance flags, the local macOS installer will derive a readable palette and light/dark appearance from the image using only tools already available to the project.

## Non-negotiable constraints

- No npm packages, ImageMagick, network APIs, or model vision.
- Use only macOS `sips` and the signed Node.js runtime already discovered by the project.
- Every explicit `--accent`, `--secondary`, `--highlight`, or `--appearance` value wins independently and is not silently adjusted.
- Automatically selected colors must reach a WCAG contrast ratio of at least `4.5:1` against every relevant theme surface.
- Analysis failure falls back to the current defaults and prints one human-readable warning.
- `LICENSE` and the original `NOTICE.md` must be byte-identical to the clean open-source baseline in the final commit.
- No public-visibility operation is allowed in this feature.
- Do not add personal paths, credentials, real email addresses, third-party IP assets, or prohibited marketing claims.

## Architecture

### Image normalization

Add `scripts/analyze-image.mjs`. It invokes `/usr/bin/sips` to make a temporary, aspect-preserving BMP preview with a maximum dimension of 64 pixels. BMP is selected because the Node.js standard library can parse its pixel buffer without an image-decoding dependency.

The analyzer supports the 24-bit and 32-bit BMP forms produced by `sips`, including top-down row order and row padding. Temporary files are created under the system temporary directory and removed in a `finally` block.

### Appearance detection

The analyzer computes WCAG relative luminance for every visible sampled pixel and uses the mean luminance to select `light` or `dark`. A deterministic threshold will be fixed by tests using clearly light and clearly dark synthetic images.

If the caller supplies `--appearance`, the analyzer keeps that value and uses it as the contrast-adjustment direction. It may still analyze missing colors, but it never replaces the explicit appearance.

### Palette extraction

Pixels are grouped into deterministic quantized RGB buckets. Each bucket records count, average RGB value, saturation, and luminance. Buckets are ranked by a combination of frequency and saturation, then three visually distinct candidates are selected for:

1. `accent`;
2. `secondary`;
3. `highlight`.

If the image does not contain three sufficiently distinct chromatic groups, the analyzer fills missing slots with deterministic tonal variants rather than adding a random color.

### Contrast enforcement

Only automatically selected colors are adjusted. For `light` appearance, their HSL lightness moves toward black; for `dark` appearance, it moves toward white. A bounded search finds the smallest lightness change that reaches at least `4.5:1` against all three existing surfaces:

- `background`;
- `panel`;
- `panelAlt`.

Explicit user colors remain byte-for-byte equivalent after normal hex normalization, even if the user deliberately chooses lower contrast.

### Override resolution

`scripts/customize-theme-macos.sh` will no longer initialize user options directly to defaults. It records which flags were actually supplied, prepares the selected image as before, and calls the analyzer once with only the explicit overrides.

The analyzer returns the final appearance and three final colors as a tab-separated record suitable for Bash 3.2. Missing fields are automatic; explicit fields pass through unchanged. Partial overrides are supported: for example, an explicit `--accent` preserves that color while `secondary` and `highlight` are still derived locally.

### Failure behavior

If `sips` cannot create the analysis preview, the BMP is unsupported, or no visible pixels are available, the analyzer returns:

- appearance: `dark`, unless explicitly supplied;
- accent: `#7cff46`, unless explicitly supplied;
- secondary: `#36d7e8`, unless explicitly supplied;
- highlight: `#642a8c`, unless explicitly supplied.

It also prints one concise warning such as `无法从图片自动取色，已使用默认配色。` to standard error. A selected image that cannot be converted into the actual theme background still fails through the existing image-preparation error because there is no usable background to install.

## Test design

Add `tests/auto-palette.test.mjs` and connect it to `tests/run-tests.sh`. Tests must be written first and observed failing before production code is created.

Required behavioral cases:

1. a synthetic light image resolves to `light`;
2. a synthetic dark image resolves to `dark`;
3. explicit appearance and each explicit color override the automatic result independently;
4. a missing or malformed analysis input returns existing defaults and a human-readable warning;
5. all automatically selected colors reach `4.5:1` against background, panel, and panelAlt;
6. partial overrides preserve supplied fields and derive the rest;
7. the customizer passes only explicit flags and consumes the analyzer result;
8. all existing adaptive-theme tests continue to pass.

Synthetic test images are created under the system temporary directory. No generated test asset is committed.

## Product and documentation changes

- `scripts/analyze-image.mjs`: new dependency-free analyzer and override resolver.
- `scripts/customize-theme-macos.sh`: track explicit flags and consume automatic style output.
- `tests/auto-palette.test.mjs`: new behavioral tests.
- `tests/run-tests.sh`: execute the new test file.
- `scripts/build-release.sh`: include the analyzer and its required product test file in the release whitelist.
- `README.md`: change only the allowed customization copy and author return-path line; preserve the current attribution notice exactly.
- `NOTICE.md`: remove the later release-clarification paragraph so the file matches the original baseline byte-for-byte.
- Content-workspace artifacts: create a copy-paste viewer deployment prompt and an automatic-color upgrade receipt.

Internal workflow specs remain repository-only and are intentionally excluded from the end-user release archive, matching the existing release policy for `docs/superpowers/`.

## README copy boundary

The customization section will say that omitted color values are derived from the image and supplied values win. The first-screen creator line will contain the exact searchable handle `作者抖音：@泽轩604`.

The attribution block immediately below the Hero is frozen. Tests or byte-range comparison must prove that its wording did not change during this feature.

## Viewer deployment prompt

The external copy-paste prompt must work for both GPT and text-only models such as DeepSeek. It tells the viewer's Codex to:

1. obtain the private-or-public repository URL supplied by the creator;
2. inspect README, LICENSE, NOTICE, and installation scripts;
3. confirm macOS and Codex Desktop prerequisites;
4. run the installer;
5. ask the viewer to select an owned or authorized image;
6. customize without inventing color flags unless the viewer requests them;
7. verify the live theme;
8. explain and preserve the Restore path.

The prompt never asks the model to inspect the image. Automatic local analysis is the only default color path.

## Release sequence

1. Implement and review in the isolated `auto-theme-colors` branch.
2. Prove tests fail for missing behavior, then make them pass.
3. Restore NOTICE byte identity and verify LICENSE identity.
4. Build the release ZIP and scan tracked/archive content.
5. Fast-forward `main` and push to the private remote.
6. Verify remote SHA and `PRIVATE` visibility.
7. Write the upgrade receipt and update the progress source of truth.
8. Delete the used prompt file as requested.

Public visibility is explicitly outside this design.

## Acceptance criteria

- Light, dark, explicit-priority, partial-priority, fallback, and contrast tests pass.
- The full repository test suite passes with zero failures.
- The release ZIP includes every required runtime/test file and passes integrity checks.
- README contains the automatic-color explanation and exact creator handle without changing attribution wording.
- `LICENSE` and `NOTICE.md` match the clean baseline byte-for-byte.
- No secret, personal path, private email, third-party IP asset, or prohibited claim is introduced.
- Local and remote `main` SHAs match after push.
- GitHub visibility is verified as `PRIVATE`.
- Viewer prompt, upgrade receipt, and updated progress record exist outside the repository.
- The used automatic-color task prompt is deleted only after all other acceptance criteria pass.
