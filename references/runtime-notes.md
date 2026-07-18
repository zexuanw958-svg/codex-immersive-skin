# Runtime notes

- Discover the official `com.openai.codex` bundle on every launch; do not assume an upgrade keeps the same executable internals.
- Use `Contents/Resources/cua_node/bin/node` from that bundle. Require Node.js 22+, a valid strict code signature, matching architecture, and OpenAI Team ID `2DC432GLL2` on both app and runtime.
- Do not ship a Node binary and do not depend on a globally installed `node` or `npm`.
- Launch the official executable through a per-user `launchd` job with `--remote-debugging-address=127.0.0.1` and a selected port. LaunchServices may discard Chromium flags.
- `launchctl submit` starts a submitted job automatically. Do not immediately force-restart it with `kickstart -k`; that race can terminate the first process and trigger launchd's startup throttle.
- Prefer port `9341`; scan through `9441` on collision and record the selected port in state.
- Accept CDP only when the listener belongs to the discovered Codex main process or one of its legitimate descendants, the WebSocket URL is loopback-only, and an `app://` renderer exposes expected native shell markers.
- Treat loopback CDP as locally privileged but unauthenticated. Keep the themed session limited to trusted local use and close the port through a full Restore when finished.
- Poll page targets and reinject after document loads. A debounced mutation observer plus a low-frequency safety timer handles in-page route changes.
- Preserve the native flex sizing of `.composer-surface-chrome`; an automatic inline margin can force the composer down to its min-content width. Live verification must check the composer, editor, scroll width, and control bounds rather than only checking that the shell exists.
- Record injector PID, start time, executable, script path, app identity, selected port, and theme directory. Refuse to stop a PID when any required identity differs.
- Store mutable data under `~/Library/Application Support/CodexImmersiveSkin`; keep the installed program under `~/.codex/codex-immersive-skin`.
- Back up and restore only `appearanceTheme` and `appearanceDarkCodeThemeId`. Leave `appearanceDarkChromeTheme` and unrelated TOML content untouched.
- Never modify, replace, unpack, repack, re-sign, or back up `app.asar`.
