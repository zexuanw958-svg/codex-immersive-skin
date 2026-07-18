---
name: codex-immersive-skin
description: Install, customize, launch, verify, repair, update, or restore Codex Immersive Skin on macOS. Use when a user wants to turn a personal image into a Codex banner and task background while preserving the native interface, or needs safe CDP theme troubleshooting and rollback.
compatibility: macOS, Codex Desktop app, signed bundled Node.js 22 or newer
---

# Codex Immersive Skin

This optional capability entry accompanies a complete standalone project. Users can run the project without installing it as a Skill.

## Workflow

1. Run `Install Codex Immersive Skin.command` from the complete project folder.
2. Run `Customize Codex Immersive Skin.command`, choose an image in Finder, and enter a theme name.
3. Verify the live result with `Verify Codex Immersive Skin.command`. A pass requires a visible native sidebar; a composer with a visible editor, usable width, no internal horizontal overflow, and controls inside its bounds; non-interactive decoration; and—on the home route—a real banner, native cards, and a visible project selector when the route provides one.
4. Restore the original appearance with `Restore Codex Immersive Skin.command`.

## Guardrails

- Never modify the Codex `.app`, `app.asar`, or its code signature.
- Use Codex's signed Node.js runtime only after validating its signature, Team ID, architecture, and minimum version.
- Bind CDP to loopback, verify that the listener belongs to Codex, and reject non-Codex renderer targets.
- Preserve all native cards, navigation, project selectors when present, task content, composer controls, and keyboard focus.
- Keep decoration at `pointer-events: none`.
- Require explicit authorization before restarting an already-running Codex instance.
- Stop an injector only when its recorded PID, executable, command line, and start time all match.

## Key resources

- `README.md`: user installation and customization guide.
- `scripts/injector.mjs`: CDP connection, injection, removal, verification, and screenshots.
- `assets/dream-skin.css`: live native interface styling.
- `assets/renderer-inject.js`: idempotent DOM integration and cleanup.
- `scripts/doctor-macos.sh`: signed-runtime, payload, and optional live-session self-check.
- `references/qa-inventory.md`: release and visual acceptance criteria.
