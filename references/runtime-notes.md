# Runtime notes

## Shared constraints

- Do not ship a Node binary and do not depend on a globally installed `node` or `npm`.
- Prefer port `9341`, select a nearby available port on collision, and record the selected port in state.
- Treat loopback CDP as locally privileged but unauthenticated. Keep the themed session limited to trusted local use and close the port through a full Restore when finished.
- Poll page targets and reinject after document loads. A debounced mutation observer plus a low-frequency safety timer handles in-page route changes.
- Record injector PID, start time, executable, script path, app identity, selected port, and theme directory. Refuse to stop a PID when any required identity differs.
- Back up and restore only `appearanceTheme` and `appearanceDarkCodeThemeId`. Leave `appearanceDarkChromeTheme` and unrelated TOML content untouched.
- Never modify, replace, unpack, repack, re-sign, or back up `app.asar`, the macOS bundle, or the Windows MSIX.

## macOS

- Discover the official `com.openai.codex` bundle on every launch; do not assume an upgrade keeps the same executable internals.
- Use `Contents/Resources/cua_node/bin/node` from that bundle. Require Node.js 22+, a valid strict code signature, matching architecture, and OpenAI Team ID `2DC432GLL2` on both app and runtime.
- Launch the official executable through a per-user `launchd` job with `--remote-debugging-address=127.0.0.1` and a selected port. LaunchServices may discard Chromium flags.
- `launchctl submit` starts a submitted job automatically. Do not immediately force-restart it with `kickstart -k`; that race can terminate the first process and trigger launchd's startup throttle.
- Accept CDP only when the listener belongs to the discovered Codex main process or one of its legitimate descendants, the WebSocket URL is loopback-only, and an `app://` renderer exposes expected native shell markers.
- Store mutable data under `~/Library/Application Support/CodexImmersiveSkin`; keep the installed program under `~/.codex/codex-immersive-skin`.

## Windows

- Discover the current user's Store/MSIX `OpenAI.Codex` on every operation. Require the pinned package family, Publisher/Publisher ID, Store origin, manifest entry, Marketplace signature, BlockMap hashes, and protected WindowsApps location.
- The package node under WindowsApps is not directly executable. Use only `%LOCALAPPDATA%\OpenAI\Codex\runtimes\cua_node\<runtime-id>\bin\node.exe` after its executable and manifest hashes match the package, its architecture/version match the package manifest, and its Authenticode certificate matches the package node.
- Reject caller-selected runtime roots and any reparse point in the `%LOCALAPPDATA%` path chain. Rehash and lock the runtime executable before sensitive execution or recorded-process checks.
- Derive a `Global` lifecycle mutex from the current-user SID and normalized state-root hash. Protect it with a current-user-only ACL, serialize Install, Customize, Start, Verify, and Restore across Windows sessions, reject reparse points in every existing state/install/theme path segment, and recheck recursive trees immediately before cleanup.
- Accept CDP only when the listener itself is the verified Store `ChatGPT.exe` main process, both HTTP endpoints refuse redirects, all debugger URLs remain loopback on the selected port, and at least one `app://` page target exists.
- Use state schema 5 with exact platform `win32-x64` or `win32-arm64`. Require an absolute Node path, absolute injector path, absolute theme directory, matching native creation time, and the exact seven-argument watcher command line.
- Decode the validated Node runtime's stdout and stderr as strict UTF-8 through `.NET Process`; do not depend on the Windows OEM code page. Drain stderr asynchronously while streaming stdout to avoid pipe deadlocks.
- Close an authorized running Codex before changing its config. Take a complete byte snapshot, require its expected SHA-256 before writing, and use compare-and-swap for later rollback so a concurrent user or Codex edit is never overwritten.
- Create the selective config backup atomically with an owner-marked `pending` phase and promote it to `active` only after the config write commits. Never adopt or delete another install's pending backup; keep the active Restore backup until the entire restore transaction commits so the same command is retryable.
- Open the verified Codex process once and perform both gentle close and any required force termination through that same native handle after rechecking path, command line, start time, package identity, and package origin. Roll back only the process launched by the current Start transaction; if its watcher cannot be stopped with certainty, persist an emergency schema-5 identity record instead of leaving it untracked.
- Store mutable data under `%LOCALAPPDATA%\CodexImmersiveSkin`; keep the installed program under `%USERPROFILE%\.codex\codex-immersive-skin`.
- Keep `RemoteSigned` limited to each new PowerShell process. Never call `Set-ExecutionPolicy`, use `Bypass`, or advise disabling SmartScreen.
