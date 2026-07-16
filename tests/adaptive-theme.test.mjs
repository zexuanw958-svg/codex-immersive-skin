import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const node = process.execPath;
const injector = path.join(root, "scripts", "injector.mjs");
const writer = path.join(root, "scripts", "write-theme.mjs");

async function temporaryTheme(appearance) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "dream-skin-adaptive-"));
  await fs.copyFile(path.join(root, "assets", "morning-mist.png"), path.join(dir, "background.png"));
  await fs.writeFile(path.join(dir, "theme.json"), JSON.stringify({
    schemaVersion: 1,
    id: "adaptive-test",
    name: "Adaptive Test",
    appearance,
    image: "background.png",
    colors: {},
  }));
  return dir;
}

function checkPayload(themeDir) {
  const result = spawnSync(node, [injector, "--check-payload", "--theme-dir", themeDir], {
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  return JSON.parse(result.stdout);
}

test("preserves a valid light appearance in the checked payload", async () => {
  const dir = await temporaryTheme("light");
  try {
    assert.equal(checkPayload(dir).appearance, "light");
  } finally {
    await fs.rm(dir, { recursive: true, force: true });
  }
});

test("falls back to dark for an invalid appearance", async () => {
  const dir = await temporaryTheme("neon");
  try {
    assert.equal(checkPayload(dir).appearance, "dark");
  } finally {
    await fs.rm(dir, { recursive: true, force: true });
  }
});

test("custom theme writer persists the requested appearance", async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "dream-skin-writer-"));
  try {
    await fs.copyFile(path.join(root, "assets", "morning-mist.png"), path.join(dir, "background.png"));
    const result = spawnSync(node, [
      writer, "custom",
      "--output-dir", dir,
      "--image", "background.png",
      "--appearance", "light",
    ], { encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
    const theme = JSON.parse(await fs.readFile(path.join(dir, "theme.json"), "utf8"));
    assert.equal(theme.appearance, "light");
    assert.equal(theme.colors.background, "#e7f0f1");
    assert.equal(theme.colors.panel, "#f8fbfb");
    assert.equal(theme.colors.text, "#17343a");
  } finally {
    await fs.rm(dir, { recursive: true, force: true });
  }
});

test("bundled neutral themes load with opposite appearances", () => {
  const morning = checkPayload(path.join(root, "assets"));
  const warm = checkPayload(path.join(root, "examples", "warm-sand"));
  assert.equal(morning.themeId, "morning-mist");
  assert.equal(morning.appearance, "light");
  assert.equal(warm.themeId, "warm-sand");
  assert.equal(warm.appearance, "dark");
  assert.ok(morning.imageBytes > 0);
  assert.ok(warm.imageBytes > 0);
});

test("renderer exposes and cleans the appearance attribute", async () => {
  const source = await fs.readFile(path.join(root, "assets", "renderer-inject.js"), "utf8");
  assert.match(source, /dataset\.dreamSkinAppearance/);
  assert.match(source, /delete\s+document\.documentElement\?\.dataset\.dreamSkinAppearance/);
});

test("CSS maps adaptive palettes to native Codex and VS Code tokens", async () => {
  const css = await fs.readFile(path.join(root, "assets", "dream-skin.css"), "utf8");
  assert.match(css, /data-dream-skin-appearance="light"/);
  assert.match(css, /data-dream-skin-appearance="dark"/);
  assert.match(css, /--color-background-surface:/);
  assert.match(css, /--color-background-button-primary:/);
  assert.match(css, /--vscode-sideBar-background:/);
  assert.match(css, /--vscode-input-background:/);
  assert.match(css, /button\.no-drag/);
  assert.doesNotMatch(css, /rgba\(43,\s*48,\s*72/);
  assert.doesNotMatch(css, /rgba\(37,\s*42,\s*68/);
  assert.doesNotMatch(css, /rgba\(42,\s*47,\s*77/);
});

test("watcher reloads the payload instead of retaining the startup payload", async () => {
  const source = await fs.readFile(path.join(root, "scripts", "injector.mjs"), "utf8");
  const start = source.indexOf("async function runWatch");
  const end = source.indexOf("\ntry {", start);
  const watch = source.slice(start, end);
  assert.doesNotMatch(watch, /const\s+\{\s*payload\s*\}\s*=\s*await\s+loadPayload/);
  assert.match(watch, /applyCurrentTheme/);
  assert.match(watch, /await\s+loadPayload\(options\.themeDir\)/);
});

test("desktop and customize launchers reuse the saved dynamic port", async () => {
  const installer = await fs.readFile(path.join(root, "scripts", "install-dream-skin-macos.sh"), "utf8");
  const customize = await fs.readFile(path.join(root, "scripts", "customize-theme-macos.sh"), "utf8");
  const start = await fs.readFile(path.join(root, "scripts", "start-dream-skin-macos.sh"), "utf8");
  assert.match(installer, /write_launcher[^\n]+start_script --prompt-restart/);
  assert.doesNotMatch(installer, /write_launcher[^\n]+start_script --port/);
  assert.doesNotMatch(customize, /start-dream-skin-macos\.sh" --port/);
  assert.match(start, /saved_port="\$\(state_field port\)"/);
  assert.match(start, /PREFERRED_PORT_PATH/);
  assert.match(installer, /LAUNCH_AFTER_INSTALL" = "true"/);
  assert.match(installer, /preferred_tmp="\$PREFERRED_PORT_PATH/);
  assert.match(installer, /CODEX_IMMERSIVE_PREVIOUS_INSTALL/);
  assert.match(installer, /CODEX_IMMERSIVE_DEPLOY_TRANSACTION/);
  assert.ok(installer.indexOf("trap rollback_deployed_install_on_exit EXIT") < installer.indexOf("discover_codex_app"));
  assert.match(installer, /trap rollback_install EXIT/);
  assert.match(start, /trap rollback_start_config_on_exit EXIT/);
  assert.match(start, /config-before-start/);
});

test("home verification allows a valid new task without a selected project", async () => {
  const source = await fs.readFile(path.join(root, "scripts", "injector.mjs"), "utf8");
  assert.match(source, /projectControlOptional/);
  assert.doesNotMatch(source, /visibleCardCount\s*<=\s*4\s*&&\s*Boolean\(result\.projectButton/);
});
