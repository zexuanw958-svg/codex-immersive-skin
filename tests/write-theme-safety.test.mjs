import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const writer = path.join(root, "scripts", "write-theme.mjs");

function run(args, environment = {}) {
  return spawnSync(process.execPath, [writer, ...args], {
    encoding: "utf8",
    env: { ...process.env, ...environment },
  });
}

async function makeOwnedTheme(themeDir) {
  await fs.mkdir(themeDir, { recursive: true });
  await fs.writeFile(path.join(themeDir, "background.png"), "image", "utf8");
  const result = run([
    "custom", "--output-dir", themeDir, "--image", "background.png",
    "--name", "Safety test", "--accent", "#123456",
    "--secondary", "#234567", "--highlight", "#345678",
  ]);
  assert.equal(result.status, 0, result.stderr);
}

test("reset-demo rejects arbitrary directories even with forged theme-shaped files", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "codex-immersive-reset-root-"));
  try {
    await makeOwnedTheme(directory);
    await fs.writeFile(path.join(directory, "sentinel.txt"), "keep\n", "utf8");
    const result = run(["reset-demo", "--output-dir", directory], {
      CODEX_IMMERSIVE_TEST_MODE: "1",
      CODEX_IMMERSIVE_TEST_ROOT: directory,
    });
    assert.notEqual(result.status, 0);
    assert.equal(await fs.readFile(path.join(directory, "sentinel.txt"), "utf8"), "keep\n");
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test("reset-demo removes only an owned theme child in an approved temporary root", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "codex-immersive-reset-managed-"));
  try {
    const themeDir = path.join(directory, "theme");
    await makeOwnedTheme(themeDir);
    const result = run(["reset-demo", "--output-dir", themeDir], {
      CODEX_IMMERSIVE_TEST_MODE: "1",
      CODEX_IMMERSIVE_TEST_ROOT: directory,
    });
    assert.equal(result.status, 0, result.stderr);
    await assert.rejects(fs.access(themeDir));
    await fs.access(directory);
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test("reset-demo refuses an approved path without ownership metadata", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "codex-immersive-reset-unowned-"));
  try {
    const themeDir = path.join(directory, "theme");
    await fs.mkdir(themeDir);
    await fs.writeFile(path.join(themeDir, "sentinel.txt"), "keep\n", "utf8");
    const result = run(["reset-demo", "--output-dir", themeDir], {
      CODEX_IMMERSIVE_TEST_MODE: "1",
      CODEX_IMMERSIVE_TEST_ROOT: directory,
    });
    assert.notEqual(result.status, 0);
    assert.equal(await fs.readFile(path.join(themeDir, "sentinel.txt"), "utf8"), "keep\n");
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});
