import test from "node:test";
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const node = process.execPath;
const themeConfig = path.join(root, "scripts", "theme-config.mjs");
const commonWindows = path.join(root, "scripts", "common-windows.ps1");
const windowsOnly = process.platform === "win32" ? test : test.skip;
const powershell = process.env.SystemRoot
  ? path.join(process.env.SystemRoot, "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
  : "powershell.exe";

function run(script, args, options = {}) {
  return spawnSync(node, [script, ...args], {
    encoding: "utf8",
    ...options,
  });
}

function sha256(value) {
  return crypto.createHash("sha256").update(value, "utf8").digest("hex");
}

function start(script, args, environment) {
  const child = spawn(node, [script, ...args], {
    env: environment,
    stdio: ["ignore", "pipe", "pipe", "ipc"],
    windowsHide: true,
  });
  const barriers = new Set();
  let stdout = "";
  let stderr = "";
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (chunk) => { stdout += chunk; });
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  child.on("message", (message) => {
    if (message?.type === "theme-config-barrier-ready") barriers.add(message.stage);
  });
  const completed = new Promise((resolve, reject) => {
    child.once("error", reject);
    child.once("close", (status, signal) => resolve({ status, signal, stdout, stderr }));
  });
  return { child, completed, barriers };
}

function themeConfigBarrierEnvironment(stage) {
  return {
    ...process.env,
    CODEX_IMMERSIVE_TEST_MODE: "1",
    CODEX_IMMERSIVE_THEME_CONFIG_TEST_BARRIER_STAGE: stage,
  };
}

async function pause(milliseconds) {
  await new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function waitForBarrierOrExit(started, stage, timeoutMs = 5000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (started.barriers.has(stage)) return true;
    if (started.child.exitCode !== null) return false;
    await pause(10);
  }
  throw new Error(`Timed out waiting for theme-config barrier: ${stage}`);
}

function releaseBarrier(started, stage) {
  if (started.child.connected) {
    started.child.send({ type: "theme-config-barrier-release", stage });
  }
}

test("theme config preserves a CRLF file byte-for-byte after install and restore", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "immersive-crlf-"));
  try {
    const config = path.join(directory, "config.toml");
    const backup = path.join(directory, "theme-backup.json");
    const original = Buffer.from([
      'model = "gpt-5"',
      "",
      "[desktop]",
      'appearanceTheme = "system"',
      'appearanceDarkCodeThemeId = "vscode-dark"',
      "keepMe = true",
      "",
    ].join("\r\n"), "utf8");
    await fs.writeFile(config, original);

    const install = run(themeConfig, ["install", config, backup, "--appearance", "light"]);
    assert.equal(install.status, 0, install.stderr);
    const backupValue = JSON.parse(await fs.readFile(backup, "utf8"));
    assert.equal(backupValue.platform, process.platform);

    const restore = run(themeConfig, ["restore", config, backup]);
    assert.equal(restore.status, 0, restore.stderr);
    assert.deepEqual(await fs.readFile(config), original);
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test("theme config retries a transient Windows rename without weakening its expected-hash check", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "immersive-rename-retry-"));
  try {
    const config = path.join(directory, "config.toml");
    const backup = path.join(directory, "theme-backup.json");
    const preload = path.join(directory, "fail-first-rename.mjs");
    await fs.writeFile(config, '[desktop]\nappearanceTheme = "system"\n', "utf8");
    await fs.writeFile(preload, [
      'import fs from "node:fs";',
      'import { syncBuiltinESMExports } from "node:module";',
      "const originalRename = fs.promises.rename.bind(fs.promises);",
      "let remainingFailures = 1;",
      "fs.promises.rename = async (...args) => {",
      "  if (remainingFailures-- > 0) {",
      '    const error = new Error("simulated transient Windows rename denial");',
      '    error.code = "EPERM";',
      "    throw error;",
      "  }",
      "  return originalRename(...args);",
      "};",
      "syncBuiltinESMExports();",
      "",
    ].join("\n"), "utf8");

    const install = spawnSync(node, [
      "--import", pathToFileURL(preload).href,
      themeConfig, "install", config, backup, "--appearance", "light",
    ], { encoding: "utf8" });
    assert.equal(install.status, 0, install.stderr);
    assert.match(await fs.readFile(config, "utf8"), /^appearanceTheme = "light"$/m);
    await fs.access(backup);
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test("theme config removes only the desktop structure it created", async () => {
  const cases = [
    'model = "gpt-5"',
    'model = "gpt-5"\n\n[desktop]',
    'model = "gpt-5"\n\n[desktop] # keep-comment',
    'model = "gpt-5"\n\n[desktop]\nkeepMe = true',
  ];
  for (const [index, value] of cases.entries()) {
    const directory = await fs.mkdtemp(path.join(os.tmpdir(), `immersive-structure-${index}-`));
    try {
      const config = path.join(directory, "config.toml");
      const backup = path.join(directory, "theme-backup.json");
      const original = Buffer.from(value, "utf8");
      await fs.writeFile(config, original);
      const install = run(themeConfig, ["install", config, backup, "--appearance", "dark"]);
      assert.equal(install.status, 0, install.stderr);
      const installed = await fs.readFile(config, "utf8");
      assert.equal((installed.match(/^\[desktop\]/gm) ?? []).length, 1);
      assert.match(installed, /^\[desktop\][^\r\n]*(?:\r\n|\n)/m);
      assert.match(installed, /^appearanceTheme = /m);
      const restore = run(themeConfig, ["restore", config, backup]);
      assert.equal(restore.status, 0, restore.stderr);
      assert.deepEqual(await fs.readFile(config), original);
    } finally {
      await fs.rm(directory, { recursive: true, force: true });
    }
  }
});

test("theme config rejects injected backup lines and invalid structure metadata", async () => {
  for (const kind of ["line", "structure"]) {
    const directory = await fs.mkdtemp(path.join(os.tmpdir(), `immersive-hostile-backup-${kind}-`));
    try {
      const config = path.join(directory, "config.toml");
      const backup = path.join(directory, "theme-backup.json");
      await fs.writeFile(config, '[desktop]\nappearanceTheme = "system"\n', "utf8");
      const install = run(themeConfig, ["install", config, backup, "--appearance", "light"]);
      assert.equal(install.status, 0, install.stderr);
      const hostile = JSON.parse(await fs.readFile(backup, "utf8"));
      if (kind === "line") {
        hostile.values.appearanceTheme = 'appearanceTheme = "system"\n[injected]\nflag = true';
      } else {
        hostile.structure.contentLength = "not-a-number";
      }
      await fs.writeFile(backup, `${JSON.stringify(hostile, null, 2)}\n`, "utf8");
      const installed = await fs.readFile(config);
      const restore = run(themeConfig, ["restore", config, backup]);
      assert.notEqual(restore.status, 0);
      assert.match(restore.stderr, /backup/i);
      assert.deepEqual(await fs.readFile(config), installed);
      assert.equal(await fs.readFile(backup, "utf8").then(() => true), true);
    } finally {
      await fs.rm(directory, { recursive: true, force: true });
    }
  }
});

test("theme config supports a validated, retryable restore while retaining its backup", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "immersive-retry-restore-"));
  try {
    const config = path.join(directory, "config.toml");
    const backup = path.join(directory, "theme-backup.json");
    const original = Buffer.from('model = "gpt-5"', "utf8");
    await fs.writeFile(config, original);
    assert.equal(run(themeConfig, ["install", config, backup, "--appearance", "dark"]).status, 0);
    const installed = await fs.readFile(config);

    const validate = run(themeConfig, ["restore", config, backup, "--validate-only"]);
    assert.equal(validate.status, 0, validate.stderr);
    assert.deepEqual(await fs.readFile(config), installed, "validation must be read-only");

    const first = run(themeConfig, ["restore", config, backup, "--keep-backup"]);
    assert.equal(first.status, 0, first.stderr);
    assert.deepEqual(await fs.readFile(config), original);
    await fs.access(backup);

    const retry = run(themeConfig, ["restore", config, backup, "--keep-backup"]);
    assert.equal(retry.status, 0, retry.stderr);
    assert.deepEqual(await fs.readFile(config), original);

    const commit = run(themeConfig, ["restore", config, backup]);
    assert.equal(commit.status, 0, commit.stderr);
    await assert.rejects(fs.access(backup));
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test("theme config accepts legal indentation on desktop headers, keys, and following tables", async () => {
  const cases = [
    [
      'model = "gpt-5"',
      "",
      " \t[desktop] # indented desktop",
      '\tappearanceTheme = "system"',
      "  keepMe = true",
      "",
      "\t[features] # indented next table",
      "enabled = true",
      "",
    ].join("\n"),
    [
      "[desktop]",
      "keepMe = true",
      "",
      "  [features]",
      "enabled = true",
      "",
    ].join("\n"),
  ];

  for (const [index, original] of cases.entries()) {
    const directory = await fs.mkdtemp(path.join(os.tmpdir(), `immersive-indented-${index}-`));
    try {
      const config = path.join(directory, "config.toml");
      const backup = path.join(directory, "theme-backup.json");
      await fs.writeFile(config, original, "utf8");

      const install = run(themeConfig, ["install", config, backup, "--appearance", "light"]);
      assert.equal(install.status, 0, install.stderr);
      const installed = await fs.readFile(config, "utf8");
      assert.equal((installed.match(/^[ \t]*\[desktop\]/gm) ?? []).length, 1);
      assert.equal((installed.match(/^[ \t]*appearanceTheme[ \t]*=/gm) ?? []).length, 1);
      assert.equal((installed.match(/^[ \t]*appearanceDarkCodeThemeId[ \t]*=/gm) ?? []).length, 1);
      assert.ok(
        installed.search(/^[ \t]*appearanceDarkCodeThemeId[ \t]*=/m)
          < installed.search(/^[ \t]*\[features\]/m),
        "new desktop keys must stay before an indented following table",
      );

      const restore = run(themeConfig, ["restore", config, backup]);
      assert.equal(restore.status, 0, restore.stderr);
      assert.equal(await fs.readFile(config, "utf8"), original);
    } finally {
      await fs.rm(directory, { recursive: true, force: true });
    }
  }
});

test("theme config selectively restores owned keys after unrelated edits", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "immersive-selective-edit-"));
  try {
    const config = path.join(directory, "config.toml");
    const backup = path.join(directory, "theme-backup.json");
    const original = 'model = "a"\n';

    await fs.writeFile(config, original, "utf8");
    assert.equal(run(themeConfig, ["install", config, backup, "--appearance", "dark"]).status, 0);
    const changedPrefix = (await fs.readFile(config, "utf8")).replace(
      'model = "a"',
      'model = "changed-by-user"',
    );
    await fs.writeFile(config, changedPrefix, "utf8");
    const prefixRestore = run(themeConfig, ["restore", config, backup]);
    assert.equal(prefixRestore.status, 0, prefixRestore.stderr);
    assert.equal(await fs.readFile(config, "utf8"), 'model = "changed-by-user"\n');

    await fs.writeFile(config, original, "utf8");
    assert.equal(run(themeConfig, ["install", config, backup, "--appearance", "dark"]).status, 0);
    const changedDesktop = `${await fs.readFile(config, "utf8")}keepMe = true\n`;
    await fs.writeFile(config, changedDesktop, "utf8");
    const desktopRestore = run(themeConfig, ["restore", config, backup]);
    assert.equal(desktopRestore.status, 0, desktopRestore.stderr);
    const restored = await fs.readFile(config, "utf8");
    assert.doesNotMatch(restored, /^[ \t]*appearanceTheme[ \t]*=/m);
    assert.doesNotMatch(restored, /^[ \t]*appearanceDarkCodeThemeId[ \t]*=/m);
    assert.match(restored, /^[ \t]*\[desktop\]/m);
    assert.match(restored, /^keepMe = true$/m);
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test("theme config requires the caller's expected config snapshot before install", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "immersive-config-snapshot-"));
  try {
    const config = path.join(directory, "config.toml");
    const backup = path.join(directory, "theme-backup.json");
    const original = '[desktop]\nappearanceTheme = "system"\nkeepMe = true\n';
    await fs.writeFile(config, original, "utf8");

    const mismatch = run(themeConfig, [
      "install",
      config,
      backup,
      "--appearance",
      "dark",
      "--expected-config-sha256",
      sha256(`${original}external = true\n`),
    ]);
    assert.notEqual(mismatch.status, 0, mismatch.stderr);
    assert.match(mismatch.stderr, /expected.*config|config.*snapshot|hash.*match/i);
    assert.equal(await fs.readFile(config, "utf8"), original);
    await assert.rejects(fs.access(backup), { code: "ENOENT" });

    const matching = run(themeConfig, [
      "install",
      config,
      backup,
      "--appearance",
      "dark",
      "--expected-config-sha256",
      sha256(original).toUpperCase(),
    ]);
    assert.equal(matching.status, 0, matching.stderr);
    const installed = await fs.readFile(config, "utf8");
    const savedBackup = await fs.readFile(backup, "utf8");

    const staleAdoption = run(themeConfig, [
      "install",
      config,
      backup,
      "--appearance",
      "light",
      "--expected-config-sha256",
      sha256(original),
    ]);
    assert.notEqual(staleAdoption.status, 0, staleAdoption.stderr);
    assert.match(staleAdoption.stderr, /expected.*config|config.*snapshot|hash.*match/i);
    assert.equal(await fs.readFile(config, "utf8"), installed);
    assert.equal(await fs.readFile(backup, "utf8"), savedBackup);
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test("theme config rejects stale install and restore writes without overwriting concurrent edits", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "immersive-config-cas-"));
  try {
    const installConfig = path.join(directory, "install.toml");
    const installBackup = path.join(directory, "install-backup.json");
    const original = '[desktop]\nappearanceTheme = "system"\nkeepMe = true\n';
    await fs.writeFile(installConfig, original, "utf8");
    const installing = start(
      themeConfig,
      [
        "install",
        installConfig,
        installBackup,
        "--appearance",
        "dark",
        "--expected-config-sha256",
        sha256(original),
      ],
      themeConfigBarrierEnvironment("before-config-write"),
    );
    assert.equal(await waitForBarrierOrExit(installing, "before-config-write"), true);
    const concurrentInstall = [
      "[desktop]",
      'appearanceTheme = "external"',
      'appearanceDarkCodeThemeId = "external-code"',
      "keepMe = true",
      "concurrentInstallEdit = true",
      "",
    ].join("\n");
    await fs.writeFile(installConfig, concurrentInstall, "utf8");
    releaseBarrier(installing, "before-config-write");
    const install = await installing.completed;
    assert.notEqual(install.status, 0, install.stderr);
    assert.match(install.stderr, /changed concurrently|conflict/i);
    assert.equal(await fs.readFile(installConfig, "utf8"), concurrentInstall);
    await assert.rejects(fs.access(installBackup), { code: "ENOENT" });

    const retryInstall = run(
      themeConfig,
      ["install", installConfig, installBackup, "--appearance", "light"],
    );
    assert.equal(retryInstall.status, 0, retryInstall.stderr);
    const retryBackup = JSON.parse(await fs.readFile(installBackup, "utf8"));
    assert.equal(retryBackup.values.appearanceTheme, 'appearanceTheme = "external"');
    assert.equal(
      retryBackup.values.appearanceDarkCodeThemeId,
      'appearanceDarkCodeThemeId = "external-code"',
    );
    const retryRestore = run(themeConfig, ["restore", installConfig, installBackup]);
    assert.equal(retryRestore.status, 0, retryRestore.stderr);
    assert.equal(await fs.readFile(installConfig, "utf8"), concurrentInstall);

    const restoreConfig = path.join(directory, "restore.toml");
    const restoreBackup = path.join(directory, "restore-backup.json");
    await fs.writeFile(restoreConfig, original, "utf8");
    assert.equal(run(themeConfig, ["install", restoreConfig, restoreBackup, "--appearance", "dark"]).status, 0);
    const installed = await fs.readFile(restoreConfig, "utf8");
    const restoring = start(
      themeConfig,
      ["restore", restoreConfig, restoreBackup],
      themeConfigBarrierEnvironment("before-config-write"),
    );
    await waitForBarrierOrExit(restoring, "before-config-write");
    const concurrentRestore = `${installed}concurrentRestoreEdit = true\n`;
    await fs.writeFile(restoreConfig, concurrentRestore, "utf8");
    releaseBarrier(restoring, "before-config-write");
    const restore = await restoring.completed;
    assert.notEqual(restore.status, 0, restore.stderr);
    assert.match(restore.stderr, /changed concurrently|conflict/i);
    assert.equal(await fs.readFile(restoreConfig, "utf8"), concurrentRestore);
    await fs.access(restoreBackup);
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test("the first concurrent install cannot overwrite another process's theme backup", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "immersive-backup-race-"));
  try {
    const config = path.join(directory, "config.toml");
    const backup = path.join(directory, "theme-backup.json");
    await fs.writeFile(config, '[desktop]\nappearanceTheme = "first"\n', "utf8");

    const firstInstall = start(
      themeConfig,
      ["install", config, backup, "--appearance", "dark"],
      themeConfigBarrierEnvironment("before-backup-create"),
    );
    await waitForBarrierOrExit(firstInstall, "before-backup-create");
    await fs.writeFile(config, '[desktop]\nappearanceTheme = "second"\n', "utf8");
    const secondInstall = run(themeConfig, ["install", config, backup, "--appearance", "light"]);
    releaseBarrier(firstInstall, "before-backup-create");
    const first = await firstInstall.completed;

    assert.equal(secondInstall.status, 0, secondInstall.stderr);
    assert.notEqual(first.status, 0, first.stderr);
    assert.match(first.stderr, /backup.*concurrent|concurrent.*backup|conflict/i);
    const saved = JSON.parse(await fs.readFile(backup, "utf8"));
    assert.equal(saved.values.appearanceTheme, 'appearanceTheme = "second"');
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test("a concurrent install cannot adopt or remove another install's unfinished backup", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "immersive-backup-owner-"));
  try {
    const config = path.join(directory, "config.toml");
    const backup = path.join(directory, "theme-backup.json");
    await fs.writeFile(config, '[desktop]\nappearanceTheme = "first"\n', "utf8");

    const winnerInstall = start(
      themeConfig,
      ["install", config, backup, "--appearance", "dark"],
      themeConfigBarrierEnvironment("before-config-write"),
    );
    assert.equal(await waitForBarrierOrExit(winnerInstall, "before-config-write"), true);
    const loserInstall = run(themeConfig, ["install", config, backup, "--appearance", "light"]);
    releaseBarrier(winnerInstall, "before-config-write");
    const winner = await winnerInstall.completed;

    assert.notEqual(loserInstall.status, 0, loserInstall.stderr);
    assert.match(loserInstall.stderr, /pending|unfinished|concurrent|transaction/i);
    assert.equal(winner.status, 0, winner.stderr);
    await fs.access(backup);
    const saved = JSON.parse(await fs.readFile(backup, "utf8"));
    assert.equal(saved.values.appearanceTheme, 'appearanceTheme = "first"');
    assert.match(await fs.readFile(config, "utf8"), /^appearanceTheme = "dark"$/m);
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test("theme config rejects an invalid existing backup before changing config", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "immersive-invalid-backup-"));
  try {
    const config = path.join(directory, "config.toml");
    const backup = path.join(directory, "theme-backup.json");
    const original = Buffer.from('[desktop]\nappearanceTheme = "system"\n', "utf8");
    await fs.writeFile(config, original);
    await fs.writeFile(backup, "{}\n", "utf8");
    const install = run(themeConfig, ["install", config, backup, "--appearance", "light"]);
    assert.notEqual(install.status, 0);
    assert.match(install.stderr, /Could not validate the existing theme backup/i);
    assert.deepEqual(await fs.readFile(config), original);
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

windowsOnly("Windows path guards reject a junction below the isolated test root", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "codex-immersive-junction-"));
  const outside = await fs.mkdtemp(path.join(os.tmpdir(), "immersive-junction-outside-"));
  try {
    const hop = path.join(directory, "hop");
    await fs.writeFile(path.join(outside, "sentinel.txt"), "keep\n", "utf8");
    await fs.symlink(outside, hop, "junction");
    const escapedCommon = commonWindows.replaceAll("'", "''");
    const command = [
      `. '${escapedCommon}'`,
      "$resolved = Resolve-CodexWindowsScopedPath -EnvironmentName 'CODEX_IMMERSIVE_STATE_ROOT' -DefaultPath (Join-Path $env:LOCALAPPDATA 'CodexImmersiveSkin')",
    ].join("; ");
    const result = spawnSync(powershell, [
      "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "RemoteSigned",
      "-Command", command,
    ], {
      env: {
        ...process.env,
        CODEX_IMMERSIVE_TEST_MODE: "1",
        CODEX_IMMERSIVE_TEST_ROOT: directory,
        CODEX_IMMERSIVE_STATE_ROOT: path.join(hop, "state"),
      },
      encoding: "utf8",
      windowsHide: true,
    });
    assert.notEqual(result.status, 0, "the scoped path resolver must reject the junction");
    const treeResult = spawnSync(powershell, [
      "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "RemoteSigned",
      "-Command", `. '${escapedCommon}'; if (Test-CodexWindowsTreeNoReparse -Path '${directory.replaceAll("'", "''")}') { throw 'tree guard accepted a junction' }`,
    ], { encoding: "utf8", windowsHide: true });
    assert.equal(treeResult.status, 0, treeResult.stderr);
    assert.equal(await fs.readFile(path.join(outside, "sentinel.txt"), "utf8"), "keep\n");
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
    await fs.rm(outside, { recursive: true, force: true });
  }
});

windowsOnly("Windows lifecycle accepts only a marked installed-copy injector", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "codex-immersive-owned-copy-"));
  try {
    const installRoot = path.join(directory, "installed");
    const installedInjector = path.join(installRoot, "scripts", "injector.mjs");
    await fs.mkdir(path.dirname(installedInjector), { recursive: true });
    await fs.writeFile(installedInjector, "// installed copy\n", "utf8");
    await fs.writeFile(path.join(installRoot, "VERSION"), "1.0.1\n", "utf8");
    const identityPath = path.join(installRoot, ".codex-immersive-skin-install.json");
    const identity = {
      schemaVersion: 1,
      product: "Codex Immersive Skin",
      installedRoot: installRoot,
      version: "1.0.1",
    };
    await fs.writeFile(identityPath, `${JSON.stringify(identity, null, 2)}\n`, "utf8");

    const quote = (value) => `'${value.replaceAll("'", "''")}'`;
    const command = [
      `. ${quote(commonWindows)}`,
      `$state = [pscustomobject]@{ injectorPath = ${quote(installedInjector)} }`,
      `Resolve-CodexWindowsRecordedInjectorPath -State $state -CurrentInjectorPath ${quote(path.join(root, "scripts", "injector.mjs"))} -InstallRoot ${quote(installRoot)}`,
    ].join("; ");
    const accepted = spawnSync(powershell, [
      "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "RemoteSigned",
      "-Command", command,
    ], { encoding: "utf8", windowsHide: true });
    assert.equal(accepted.status, 0, accepted.stderr || accepted.stdout);
    assert.equal(path.resolve(accepted.stdout.trim()).toLowerCase(), path.resolve(installedInjector).toLowerCase());

    identity.product = "not-owned";
    await fs.writeFile(identityPath, `${JSON.stringify(identity, null, 2)}\n`, "utf8");
    const rejected = spawnSync(powershell, [
      "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "RemoteSigned",
      "-Command", command,
    ], { encoding: "utf8", windowsHide: true });
    assert.notEqual(rejected.status, 0, "an unowned installed copy must not be trusted");
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

windowsOnly("Windows PowerShell 5.1 reads no-BOM state JSON as UTF-8", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "codex-immersive-utf8-state-"));
  try {
    const statePath = path.join(directory, "state.json");
    const expectedInjector = path.join(directory, "中文目录", "injector.mjs");
    await fs.writeFile(statePath, `${JSON.stringify({
      schemaVersion: 5,
      platform: "win32-x64",
      injectorPid: 42,
      injectorStartedAt: "2026-07-18T00:00:00.0000000Z",
      nodePath: path.join(directory, "运行时", "node.exe"),
      injectorPath: expectedInjector,
      themeDir: path.join(directory, "主题"),
      port: 9341,
    }, null, 2)}\n`, "utf8");

    const quote = (value) => `'${value.replaceAll("'", "''")}'`;
    const command = [
      `. ${quote(commonWindows)}`,
      `$state = Read-CodexWindowsState -Path ${quote(statePath)}`,
      `if (-not [string]::Equals([string]$state.injectorPath, ${quote(expectedInjector)}, [StringComparison]::Ordinal)) { throw 'UTF-8 state path mismatch' }`,
      "'PASS'",
    ].join("; ");
    const result = spawnSync(powershell, [
      "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "RemoteSigned",
      "-Command", command,
    ], { encoding: "utf8", windowsHide: true });
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(result.stdout.trim(), "PASS");
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test("reset-demo cannot delete bundled assets through Windows path casing", {
  skip: process.platform !== "win32",
}, async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "immersive-case-"));
  try {
    const scripts = path.join(directory, "scripts");
    const assets = path.join(directory, "assets");
    await fs.mkdir(scripts);
    await fs.mkdir(assets);
    await fs.copyFile(
      path.join(root, "scripts", "write-theme.mjs"),
      path.join(scripts, "write-theme.mjs"),
    );
    await fs.writeFile(path.join(assets, "sentinel.txt"), "keep");

    const result = run(path.join(scripts, "write-theme.mjs"), [
      "reset-demo",
      "--output-dir",
      path.join(directory, "ASSETS"),
    ]);
    assert.notEqual(result.status, 0, "the bundled assets path must be rejected");
    assert.match(result.stderr, /Refusing to delete the bundled demo assets/i);
    assert.equal(await fs.readFile(path.join(assets, "sentinel.txt"), "utf8"), "keep");
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});
