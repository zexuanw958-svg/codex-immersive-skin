# QA inventory

## Required user-visible behavior

1. Home route shows one independent image banner, live native heading, two to four native suggestion cards, the real project selector when that route provides one, and a native composer with usable width.
2. Normal tasks show the selected image behind restrained gradients and translucent live content surfaces.
3. Sidebar, navigation, messages, approvals, project selector, attachments, composer, menus, hover, focus, and keyboard input remain native and interactive.
4. Decorative layers have `pointer-events: none`; no screenshot or raster UI is used as an overlay.
5. Route changes, renderer reloads, and ordinary refreshes reapply the current theme while the verified injector runs.
6. Official application signature and `app.asar` remain unchanged.
7. Restore removes live DOM/CSS, restores the two saved base-theme values, closes the CDP session after restart, and supports later reinstallation.

## Automated checks

- Platform shell/PowerShell and JavaScript syntax checks.
- Payload construction with bundled demo and an isolated custom theme.
- Reject unsupported theme config, unsafe image paths, invalid colors, oversized images, non-loopback WebSocket URLs, and unrecognized renderer targets.
- Exact install/restore round trip for the two TOML settings while preserving unrelated values.
- Windows config and launcher compare-and-swap behavior, owned pending/active backup transitions, interrupted `.previous` recovery, and refusal to overwrite concurrent edits.
- Empty `HOME` recovery on macOS.
- Official app and internal Node identity validation: signature, Team ID, architecture, and version on macOS; Store/MSIX identity, BlockMap, package-matching local runtime hash, Authenticode, architecture, and version on Windows.
- Port collision selection and saved-port reuse.
- PID reuse protection through PID, start time, executable, script path, and command-line matching.
- Windows cross-session current-user mutex ACLs, same-handle gentle/force process handling, strict UTF-8 child output, reparse-safe mutable trees, and owned reset-demo cleanup.
- Live verification after `Page.reload` returns version `1.1.0` and `pass: true`.
- Composer verification requires at least 240 px of visible width, a visible editor, no internal horizontal overflow, and all visible controls to stay inside the composer bounds.
- Strict home verification requires a visible banner of at least 320×160, two to four visible native cards, a visible project button when present, a valid composer layout, a visible sidebar, non-interactive decoration, and no horizontal overflow.

## Visual checks

- Home at normal desktop size: banner crop is readable, text remains live, cards are not clipped, and composer does not overlap content.
- Narrower window: quote/orbit decoration hides before covering essential controls.
- Task route: background remains atmospheric, messages and output panels keep high contrast, and the composer remains reachable.
- Selected image contains no fake interface controls or raster text intended to impersonate Codex.
- Inspect sidebar selection, header, banner edges, cards, the project label when present, composer width and buttons, scrollbars, focus outlines, dialogs, and menus.

## Release signoff

- Run `tests/run-tests.sh` on macOS or `npm.cmd test` on Windows successfully.
- Install from a clean extracted copy with no global Node.js.
- Complete install → live verify → reload verify → restore → reinstall.
- Retain the verifier JSON; Windows Verify is JSON-only by default. Capture a real CDP screenshot only with the user's explicit consent and a non-sensitive task; never commit or upload it.
- Confirm `codesign --verify --deep --strict` still succeeds on macOS, or `doctor-windows.ps1` reports Store/BlockMap/runtime checks passing on Windows.
- Build ZIP and record SHA-256.
