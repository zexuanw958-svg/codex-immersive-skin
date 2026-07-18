import test from "node:test";
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const installer = path.join(root, "scripts", "install-dream-skin-windows.ps1");
const windowsOnly = process.platform === "win32" ? test : test.skip;
const powershell = process.env.SystemRoot
  ? path.join(process.env.SystemRoot, "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
  : "powershell.exe";

const originalConfig = [
  'model = "gpt-5"',
  "",
  "[desktop]",
  'appearanceTheme = "system"',
  'appearanceDarkCodeThemeId = "vscode-dark"',
  "keepMe = true",
  "",
].join("\r\n");

async function withFixture(run) {
  const temporaryRoot = await fs.mkdtemp(path.join(os.tmpdir(), "codex-immersive-install-test-"));
  const fixture = {
    temporaryRoot,
    installRoot: path.join(temporaryRoot, "installed"),
    stateRoot: path.join(temporaryRoot, "state"),
    configPath: path.join(temporaryRoot, "config.toml"),
  };
  try {
    await fs.mkdir(fixture.stateRoot, { recursive: true });
    await fs.writeFile(fixture.configPath, originalConfig, "utf8");
    await run(fixture);
  } finally {
    await fs.rm(temporaryRoot, { recursive: true, force: true });
  }
}

function runInstaller(fixture, environment = {}) {
  return spawnSync(powershell, [
    "-NoLogo",
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy", "RemoteSigned",
    "-File", installer,
    "--no-launch",
    "--no-launchers",
  ], {
    cwd: root,
    env: {
      ...process.env,
      CODEX_IMMERSIVE_INSTALL_ROOT: fixture.installRoot,
      CODEX_IMMERSIVE_STATE_ROOT: fixture.stateRoot,
      CODEX_IMMERSIVE_CONFIG_PATH: fixture.configPath,
      CODEX_IMMERSIVE_TEST_MODE: "1",
      CODEX_IMMERSIVE_TEST_ROOT: fixture.temporaryRoot,
      CODEX_IMMERSIVE_NO_PAUSE: "1",
      ...environment,
    },
    encoding: "utf8",
    windowsHide: true,
  });
}

function startInstaller(fixture, environment = {}) {
  return spawn(powershell, [
    "-NoLogo",
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy", "RemoteSigned",
    "-File", installer,
    "--no-launch",
    "--no-launchers",
  ], {
    cwd: root,
    env: {
      ...process.env,
      CODEX_IMMERSIVE_INSTALL_ROOT: fixture.installRoot,
      CODEX_IMMERSIVE_STATE_ROOT: fixture.stateRoot,
      CODEX_IMMERSIVE_CONFIG_PATH: fixture.configPath,
      CODEX_IMMERSIVE_TEST_MODE: "1",
      CODEX_IMMERSIVE_TEST_ROOT: fixture.temporaryRoot,
      CODEX_IMMERSIVE_NO_PAUSE: "1",
      ...environment,
    },
    stdio: "ignore",
    windowsHide: true,
  });
}

async function waitForInstallTransaction(stateRoot) {
  const deadline = Date.now() + 20_000;
  while (Date.now() < deadline) {
    const entries = await fs.readdir(stateRoot);
    if (entries.some((name) => name.startsWith("install-rollback."))) return;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error("installer transaction did not become observable");
}

function waitForExit(child) {
  return new Promise((resolve, reject) => {
    child.once("error", reject);
    child.once("exit", (code, signal) => resolve({ code, signal }));
  });
}

windowsOnly("Windows installer rejects path overrides outside explicit isolated-test mode", async () => {
  await withFixture(async (fixture) => {
    const before = await fs.readFile(fixture.configPath);
    const result = runInstaller(fixture, {
      CODEX_IMMERSIVE_TEST_MODE: "",
      CODEX_IMMERSIVE_TEST_ROOT: "",
    });
    assert.notEqual(result.status, 0);
    await assert.rejects(fs.access(fixture.installRoot));
    assert.deepEqual(await fs.readFile(fixture.configPath), before);
  });
});

windowsOnly("Windows installer refuses to replace an unowned existing directory", async () => {
  await withFixture(async (fixture) => {
    await fs.mkdir(fixture.installRoot, { recursive: true });
    await fs.writeFile(path.join(fixture.installRoot, "private-file.txt"), "keep\n", "utf8");
    const before = await fs.readFile(fixture.configPath);
    const result = runInstaller(fixture);
    assert.notEqual(result.status, 0);
    assert.equal(await fs.readFile(path.join(fixture.installRoot, "private-file.txt"), "utf8"), "keep\n");
    assert.deepEqual(await fs.readFile(fixture.configPath), before);
  });
});

windowsOnly("Windows installer succeeds without launching Codex or touching Desktop launchers", async () => {
  await withFixture(async (fixture) => {
    const result = runInstaller(fixture);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(
      (await fs.readFile(path.join(fixture.installRoot, "VERSION"), "utf8")).trim(),
      (await fs.readFile(path.join(root, "VERSION"), "utf8")).trim(),
    );
    const identity = JSON.parse(await fs.readFile(
      path.join(fixture.installRoot, ".codex-immersive-skin-install.json"),
      "utf8",
    ));
    assert.equal(identity.schemaVersion, 1);
    assert.equal(identity.product, "Codex Immersive Skin");
    assert.equal(identity.installedRoot, fixture.installRoot);
    assert.equal(await fs.readFile(path.join(fixture.stateRoot, "preferred-port"), "utf8"), "9341\n");
    assert.equal(await fs.readFile(fixture.configPath, "utf8"), originalConfig);
    await assert.rejects(fs.access(path.join(fixture.stateRoot, "theme-backup.json")));
  });
});

windowsOnly("Windows installer restores the previous tree and preserves untouched config after a late failure", async () => {
  await withFixture(async (fixture) => {
    await fs.mkdir(fixture.installRoot, { recursive: true });
    await fs.writeFile(path.join(fixture.installRoot, "previous-marker.txt"), "keep\n", "utf8");
    await fs.writeFile(path.join(fixture.installRoot, "VERSION"), "1.0.0\n", "utf8");
    await fs.mkdir(path.join(fixture.installRoot, "scripts"));
    await fs.writeFile(
      path.join(fixture.installRoot, "scripts", "install-dream-skin-windows.ps1"),
      "# previous install\n",
      "utf8",
    );
    await fs.writeFile(
      path.join(fixture.installRoot, ".codex-immersive-skin-install.json"),
      `${JSON.stringify({
        schemaVersion: 1,
        product: "Codex Immersive Skin",
        installedRoot: fixture.installRoot,
        version: "1.0.0",
      }, null, 2)}\n`,
      "utf8",
    );
    await fs.mkdir(path.join(fixture.stateRoot, "preferred-port"));
    const before = await fs.readFile(fixture.configPath);

    const result = runInstaller(fixture);
    assert.notEqual(result.status, 0, "the directory at preferred-port must force a late transactional failure");
    assert.equal(await fs.readFile(path.join(fixture.installRoot, "previous-marker.txt"), "utf8"), "keep\n");
    assert.deepEqual(await fs.readFile(fixture.configPath), before);
    await assert.rejects(fs.access(path.join(fixture.stateRoot, "theme-backup.json")));

    const siblings = await fs.readdir(fixture.temporaryRoot);
    assert.deepEqual(siblings.filter((name) => /\.(?:installing|previous|failed)\./.test(name)), []);
    const stateEntries = await fs.readdir(fixture.stateRoot);
    assert.deepEqual(stateEntries.filter((name) => name.startsWith("install-rollback.")), []);
  });
});

windowsOnly("Windows installer recovers an owned previous tree after an interrupted rename", async () => {
  await withFixture(async (fixture) => {
    const interrupted = `${fixture.installRoot}.previous.crash-test`;
    await fs.mkdir(path.join(interrupted, "scripts"), { recursive: true });
    await fs.writeFile(path.join(interrupted, "VERSION"), "1.0.0\n", "utf8");
    await fs.writeFile(path.join(interrupted, "scripts", "install-dream-skin-windows.ps1"), "# previous\n", "utf8");
    await fs.writeFile(path.join(interrupted, "previous-marker.txt"), "recovered\n", "utf8");
    await fs.writeFile(
      path.join(interrupted, ".codex-immersive-skin-install.json"),
      `${JSON.stringify({
        schemaVersion: 1,
        product: "Codex Immersive Skin",
        installedRoot: fixture.installRoot,
        version: "1.0.0",
      }, null, 2)}\n`,
      "utf8",
    );
    await fs.mkdir(path.join(fixture.stateRoot, "preferred-port"));

    const result = runInstaller(fixture);
    assert.notEqual(result.status, 0, "the preferred-port directory must force rollback after recovery");
    assert.equal(await fs.readFile(path.join(fixture.installRoot, "previous-marker.txt"), "utf8"), "recovered\n");
    await assert.rejects(fs.access(interrupted));
  });
});

windowsOnly("Windows no-launch rollback never overwrites a concurrent config edit", async () => {
  await withFixture(async (fixture) => {
    await fs.mkdir(path.join(fixture.stateRoot, "preferred-port"));
    const child = startInstaller(fixture);
    const exit = waitForExit(child);
    await waitForInstallTransaction(fixture.stateRoot);
    const concurrent = 'model = "concurrent-user-edit"\r\n';
    await fs.writeFile(fixture.configPath, concurrent, "utf8");
    const result = await exit;
    assert.notEqual(result.code, 0, "the preferred-port directory must force a late failure");
    assert.equal(await fs.readFile(fixture.configPath, "utf8"), concurrent);
  });
});
