import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");

const entrypoints = new Map([
  ["Install Codex Immersive Skin.cmd", "install-dream-skin-windows.ps1"],
  ["Customize Codex Immersive Skin.cmd", "customize-theme-windows.ps1"],
  ["Verify Codex Immersive Skin.cmd", "verify-dream-skin-windows.ps1"],
  ["Restore Codex Immersive Skin.cmd", "restore-dream-skin-windows.ps1"],
  ["Start Codex Immersive Skin.cmd", "start-dream-skin-windows.ps1"],
]);

for (const [entrypoint, script] of entrypoints) {
  test(`${entrypoint} launches its installed PowerShell workflow safely`, async () => {
    const source = await fs.readFile(path.join(root, entrypoint), "utf8");
    assert.match(source, /%~dp0scripts\\/i);
    assert.match(source, new RegExp(script.replaceAll(".", "\\."), "i"));
    assert.match(source, /-NoProfile/i);
    assert.match(source, /-STA/i);
    assert.match(source, /-ExecutionPolicy\s+RemoteSigned/i);
    assert.match(source, /%\*/);
    assert.match(source, /exit\s+\/b/i);
    assert.doesNotMatch(source, /Set-ExecutionPolicy|\bBypass\b/i);
  });
}

test("double-click Start and Restore request the complete authorized lifecycle", async () => {
  const start = await fs.readFile(path.join(root, "Start Codex Immersive Skin.cmd"), "utf8");
  const restore = await fs.readFile(path.join(root, "Restore Codex Immersive Skin.cmd"), "utf8");
  assert.match(start, /--prompt-restart/i);
  assert.match(restore, /--restore-base-theme/i);
  assert.match(restore, /--restart-codex/i);
});

test("default Windows verification does not capture a private screenshot", async () => {
  const installer = await fs.readFile(
    path.join(root, "scripts", "install-dream-skin-windows.ps1"),
    "utf8",
  );
  const restore = await fs.readFile(
    path.join(root, "scripts", "restore-dream-skin-windows.ps1"),
    "utf8",
  );
  const verifyLauncher = installer
    .split("\n")
    .find((line) => line.includes("Codex Immersive Skin - Verify.lnk"));
  const restoreIdentity = restore
    .split("\n")
    .find((line) => line.includes("Codex Immersive Skin - Verify.lnk"));
  assert.ok(verifyLauncher);
  assert.ok(restoreIdentity);
  assert.match(verifyLauncher, /Extra\s*=\s*''/);
  assert.match(restoreIdentity, /Extra\s*=\s*@\(\)/);
  assert.doesNotMatch(verifyLauncher, /--screenshot|--open-screenshot/i);
  assert.doesNotMatch(restoreIdentity, /--screenshot|--open-screenshot/i);
});

test("the release manifest includes every Windows lifecycle dependency", async () => {
  const manifest = await fs.readFile(path.join(root, "scripts", "build-release.sh"), "utf8");
  for (const file of [
    "common-windows.ps1",
    "lifecycle-windows.ps1",
    "normalize-image-windows.ps1",
    "install-dream-skin-windows.ps1",
    "customize-theme-windows.ps1",
    "start-dream-skin-windows.ps1",
    "verify-dream-skin-windows.ps1",
    "restore-dream-skin-windows.ps1",
  ]) {
    assert.match(manifest, new RegExp(`scripts/${file.replaceAll(".", "\\.")}`));
  }
});

test("lifecycle scripts normalize PowerShell 5.1 empty remaining arguments", async () => {
  for (const script of entrypoints.values()) {
    const source = await fs.readFile(path.join(root, "scripts", script), "utf8");
    assert.match(source, /ConvertTo-CodexWindowsRemainingArguments\s+-Values\s+\$Arguments/);
  }
});
