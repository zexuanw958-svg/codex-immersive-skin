---
name: codex-immersive-skin
description: Install, customize, start, verify, troubleshoot, update, or restore Codex Immersive Skin on macOS or a verified Microsoft Store/MSIX Windows Codex setup. Use when a user wants to turn a personal image into a reversible Codex banner and task background while preserving the native interface, or needs safe loopback-CDP diagnosis and rollback.
---

# Codex Immersive Skin

This optional capability entry accompanies a complete standalone project. Users can run the project without installing it as a Skill.

## Workflow

1. Read `README.md` and the platform guide. On Windows, read `docs/windows/README.md` and check the validated scope in `docs/windows/适配报告.md`.
2. Run the platform doctor before mutation. Require the complete project folder and an already-initialized Codex Desktop app.
3. Run `Install Codex Immersive Skin.command` on macOS. On Windows, before restart authorization, run `Install Codex Immersive Skin.cmd --no-launch` so deployment cannot enter Start.
4. Run the matching Customize entry, choose a local image, and enter a theme name. Preserve automatic palette fields unless the user explicitly overrides them. On Windows, use `--no-apply` until restart authorization has been granted.
5. Run the matching Start entry. Obtain explicit authorization before restarting an already-running Codex instance; only then may Windows automation pass `--restart-existing`.
6. Run the matching Verify entry. Require a visible native sidebar; a composer with a visible editor, usable width, no internal horizontal overflow, and controls inside its bounds; non-interactive decoration; and—on the home route—a real banner, native cards, and a visible project selector when the route provides one. Keep manual interaction checks separate from automated results.
7. Run the matching Restore entry to restore the original appearance and close the themed debug session.

## Guardrails

- Never modify the Codex `.app`, Windows MSIX, `app.asar`, or code signature.
- On macOS, validate the app/runtime signature, Team ID, architecture, and minimum Node.js version. On Windows, validate Store package identity and content, then use only the `%LOCALAPPDATA%` Codex runtime whose hash, signature, architecture, and version match the package.
- Never disable SmartScreen, use `Bypass`, or persistently lower PowerShell policy. Keep Windows `RemoteSigned` limited to the launched process.
- Bind CDP to loopback, verify that the listener belongs to Codex, and reject non-Codex renderer targets.
- Preserve all native cards, navigation, project selectors when present, task content, composer controls, and keyboard focus.
- Keep decoration at `pointer-events: none`.
- Require explicit authorization before restarting an already-running Codex instance.
- Stop an injector only when its recorded PID, executable, command line, and start time all match.
- Keep user images and verification screenshots local; do not inspect, upload, or commit them.
- On Windows, keep Verify JSON-only by default. Request separate, explicit consent before saving a screenshot from a non-sensitive task.

## Key resources

- `README.md`: user installation and customization guide.
- `docs/windows/README.md`: Windows prerequisites, five-entry workflow, SmartScreen guidance, and recovery.
- `docs/windows/适配报告.md`: exact Windows versions, evidence, limitations, and release recommendation.
- `scripts/injector.mjs`: CDP connection, injection, removal, verification, and screenshots.
- `assets/dream-skin.css`: live native interface styling.
- `assets/renderer-inject.js`: idempotent DOM integration and cleanup.
- `scripts/doctor-macos.sh`: signed-runtime, payload, and optional live-session self-check.
- `scripts/doctor-windows.ps1`: Store/MSIX, package content, Codex runtime, payload, and optional live-session self-check.
- `scripts/common-windows.ps1`: Windows package, runtime, process, CDP, and saved-state identity checks.
- `scripts/lifecycle-windows.ps1`: Windows state-root mutation boundary shared by the five lifecycle entries.
- `references/qa-inventory.md`: release and visual acceptance criteria.
