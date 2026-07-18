import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const customizer = path.join(root, "scripts", "customize-theme-windows.ps1");
const analyzer = path.join(root, "scripts", "analyze-image.mjs");
const windowsOnly = { skip: process.platform !== "win32" };

function powershellPath() {
  const systemRoot = process.env.SystemRoot ?? process.env.WINDIR;
  assert.ok(systemRoot, "Windows must provide SystemRoot or WINDIR");
  return path.join(
    systemRoot,
    "System32",
    "WindowsPowerShell",
    "v1.0",
    "powershell.exe",
  );
}

function redactPrivateValues(value) {
  let result = String(value ?? "");
  const replacements = [
    [process.env.LOCALAPPDATA, "%LOCALAPPDATA%"],
    [process.env.APPDATA, "%APPDATA%"],
    [process.env.USERPROFILE, "%USERPROFILE%"],
    [process.env.HOME, "%USERPROFILE%"],
    [process.env.USERNAME, "%USERNAME%"],
  ].filter(([privateValue]) => privateValue);
  replacements.sort(([first], [second]) => second.length - first.length);
  for (const [privateValue, placeholder] of replacements) {
    const escaped = privateValue.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    result = result.replace(new RegExp(escaped, "gi"), placeholder);
  }
  return result;
}

function executionDetails(result) {
  return redactPrivateValues([
    result.error?.message,
    result.stderr,
    result.stdout,
  ].filter(Boolean).join("\n"));
}

function createPaletteBmp(width, height) {
  const rowStride = Math.ceil((width * 3) / 4) * 4;
  const pixelOffset = 54;
  const buffer = Buffer.alloc(pixelOffset + rowStride * height);
  buffer.write("BM", 0, "ascii");
  buffer.writeUInt32LE(buffer.length, 2);
  buffer.writeUInt32LE(pixelOffset, 10);
  buffer.writeUInt32LE(40, 14);
  buffer.writeInt32LE(width, 18);
  buffer.writeInt32LE(height, 22);
  buffer.writeUInt16LE(1, 26);
  buffer.writeUInt16LE(24, 28);
  buffer.writeUInt32LE(0, 30);
  buffer.writeUInt32LE(rowStride * height, 34);

  const colors = [
    { red: 157, green: 112, blue: 79 },
    { red: 68, green: 116, blue: 158 },
    { red: 137, green: 73, blue: 123 },
  ];
  for (let row = 0; row < height; row += 1) {
    const color = colors[row % colors.length];
    const rowOffset = pixelOffset + row * rowStride;
    for (let column = 0; column < width; column += 1) {
      const offset = rowOffset + column * 3;
      buffer[offset] = color.blue;
      buffer[offset + 1] = color.green;
      buffer[offset + 2] = color.red;
    }
  }
  return buffer;
}

function runCustomizer(fixture, stateRoot, image, extraArguments = []) {
  return spawnSync(powershellPath(), [
    "-NoLogo",
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy", "RemoteSigned",
    "-File", customizer,
    "--image", image,
    "--name", "Windows Integration Theme",
    "--tagline", "Local integration test",
    "--quote", "OFFLINE ONLY",
    ...extraArguments,
    "--no-apply",
  ], {
    cwd: root,
    encoding: "utf8",
    env: {
      ...process.env,
      CODEX_IMMERSIVE_STATE_ROOT: stateRoot,
      CODEX_IMMERSIVE_TEST_MODE: "1",
      CODEX_IMMERSIVE_TEST_ROOT: fixture.root,
      CODEX_IMMERSIVE_NO_PAUSE: "1",
    },
    timeout: 120_000,
    windowsHide: true,
  });
}

function runAnalyzer(image, extraArguments = []) {
  return spawnSync(process.execPath, [
    analyzer,
    "--image", image,
    ...extraArguments,
    "--format", "json",
  ], {
    cwd: root,
    encoding: "utf8",
    timeout: 120_000,
    windowsHide: true,
  });
}

async function readTheme(stateRoot) {
  const themeDirectory = path.join(stateRoot, "theme");
  const theme = JSON.parse(await fs.readFile(path.join(themeDirectory, "theme.json"), "utf8"));
  const image = path.join(themeDirectory, theme.image);
  const imageBytes = await fs.readFile(image);
  assert.deepEqual([...imageBytes.subarray(0, 2)], [0xff, 0xd8]);
  return { themeDirectory, theme, image };
}

async function snapshotTree(directory) {
  const snapshot = {};
  async function visit(current, relative) {
    const entries = await fs.readdir(current, { withFileTypes: true });
    entries.sort((first, second) => first.name.localeCompare(second.name));
    for (const entry of entries) {
      const entryRelative = path.join(relative, entry.name);
      const entryPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        snapshot[`${entryRelative}${path.sep}`] = "directory";
        await visit(entryPath, entryRelative);
      } else {
        const bytes = await fs.readFile(entryPath);
        snapshot[entryRelative] = crypto.createHash("sha256").update(bytes).digest("hex");
      }
    }
  }
  await visit(directory, "");
  return snapshot;
}

test("Windows customizer applies local palettes transactionally without launching Codex", windowsOnly, async (t) => {
  const fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), "codex-immersive-customize-test-"));
  const fixture = {
    root: fixtureRoot,
    configPath: path.join(fixtureRoot, "profile", ".codex", "config.toml"),
    installRoot: path.join(fixtureRoot, "install"),
  };
  const sourceImage = path.join(fixtureRoot, "local palette.bmp");
  const configContents = "model = \"fixture-only\"\n";
  const installMarker = path.join(fixture.installRoot, "fixture-marker.txt");

  try {
    await fs.mkdir(path.dirname(fixture.configPath), { recursive: true });
    await fs.mkdir(fixture.installRoot, { recursive: true });
    await fs.writeFile(fixture.configPath, configContents);
    await fs.writeFile(installMarker, "untouched\n");
    await fs.writeFile(sourceImage, createPaletteBmp(96, 48));

    const automaticState = path.join(fixtureRoot, "state-auto");
    let automatic;

    await t.test("automatic colors are written from the local image with fallback disabled", async () => {
      const result = runCustomizer(fixture, automaticState, sourceImage);
      assert.equal(result.status, 0, executionDetails(result));
      assert.equal(redactPrivateValues(result.stderr).trim(), "");

      automatic = await readTheme(automaticState);
      const analysisResult = runAnalyzer(automatic.image);
      assert.equal(analysisResult.status, 0, executionDetails(analysisResult));
      assert.equal(redactPrivateValues(analysisResult.stderr).trim(), "");
      const style = JSON.parse(analysisResult.stdout);
      assert.equal(style.fallback, false);
      assert.equal(automatic.theme.appearance, style.appearance);
      assert.deepEqual(
        [
          automatic.theme.colors.accent,
          automatic.theme.colors.secondary,
          automatic.theme.colors.highlight,
        ],
        [style.accent, style.secondary, style.highlight],
      );
    });

    await t.test("a single accent override preserves every other automatic field", async () => {
      const partialState = path.join(fixtureRoot, "state-partial");
      const result = runCustomizer(fixture, partialState, sourceImage, ["--accent", "#123456"]);
      assert.equal(result.status, 0, executionDetails(result));
      assert.equal(redactPrivateValues(result.stderr).trim(), "");

      const partial = await readTheme(partialState);
      assert.equal(partial.theme.colors.accent, "#123456");
      assert.equal(partial.theme.appearance, automatic.theme.appearance);
      assert.equal(partial.theme.colors.secondary, automatic.theme.colors.secondary);
      assert.equal(partial.theme.colors.highlight, automatic.theme.colors.highlight);

      const analysisResult = runAnalyzer(partial.image, ["--accent", "#123456"]);
      assert.equal(analysisResult.status, 0, executionDetails(analysisResult));
      const style = JSON.parse(analysisResult.stdout);
      assert.equal(style.fallback, false);
      assert.deepEqual(
        [style.accent, style.secondary, style.highlight],
        [
          partial.theme.colors.accent,
          partial.theme.colors.secondary,
          partial.theme.colors.highlight,
        ],
      );
    });

    await t.test("a complete explicit style override is preserved exactly", async () => {
      const explicitState = path.join(fixtureRoot, "state-explicit");
      const explicitArguments = [
        "--appearance", "dark",
        "--accent", "#112233",
        "--secondary", "#445566",
        "--highlight", "#778899",
      ];
      const result = runCustomizer(fixture, explicitState, sourceImage, explicitArguments);
      assert.equal(result.status, 0, executionDetails(result));
      assert.equal(redactPrivateValues(result.stderr).trim(), "");

      const explicit = await readTheme(explicitState);
      assert.equal(explicit.theme.appearance, "dark");
      assert.deepEqual(
        [
          explicit.theme.colors.accent,
          explicit.theme.colors.secondary,
          explicit.theme.colors.highlight,
        ],
        ["#112233", "#445566", "#778899"],
      );

      const analysisResult = runAnalyzer(explicit.image, explicitArguments);
      assert.equal(analysisResult.status, 0, executionDetails(analysisResult));
      assert.deepEqual(JSON.parse(analysisResult.stdout), {
        appearance: "dark",
        accent: "#112233",
        secondary: "#445566",
        highlight: "#778899",
        fallback: false,
      });
    });

    await t.test("a failed image conversion leaves the existing theme byte-for-byte unchanged", async () => {
      const before = await snapshotTree(path.join(automaticState, "theme"));
      const malformedImage = path.join(fixtureRoot, "malformed.bmp");
      await fs.writeFile(malformedImage, "not a bitmap");

      const result = runCustomizer(fixture, automaticState, malformedImage);
      assert.notEqual(result.status, 0, "malformed local image must be rejected");
      const after = await snapshotTree(path.join(automaticState, "theme"));
      assert.deepEqual(after, before);

      const stateEntries = await fs.readdir(automaticState);
      assert.deepEqual(
        stateEntries.filter((name) => /^theme\.(?:staging|previous)\./i.test(name)),
        [],
      );
    });

    await t.test("an owned previous theme is recovered after an interrupted rename", async () => {
      const recoveryState = path.join(fixtureRoot, "state-recovery");
      const interrupted = path.join(recoveryState, "theme.previous.crash-test");
      await fs.mkdir(interrupted, { recursive: true });
      await fs.writeFile(path.join(interrupted, ".codex-immersive-theme.json"), `${JSON.stringify({
        schemaVersion: 1,
        product: "Codex Immersive Skin theme",
      }, null, 2)}\n`, "utf8");
      await fs.writeFile(path.join(interrupted, "theme.json"), `${JSON.stringify({
        schemaVersion: 1,
        brandSubtitle: "CODEX IMMERSIVE SKIN",
      }, null, 2)}\n`, "utf8");
      await fs.writeFile(path.join(interrupted, "recovery-marker.txt"), "recovered\n", "utf8");
      const malformedImage = path.join(fixtureRoot, "recovery-malformed.bmp");
      await fs.writeFile(malformedImage, "not a bitmap", "utf8");

      const result = runCustomizer(fixture, recoveryState, malformedImage);
      assert.notEqual(result.status, 0, "the malformed image must fail after recovery");
      assert.equal(
        await fs.readFile(path.join(recoveryState, "theme", "recovery-marker.txt"), "utf8"),
        "recovered\n",
      );
      await assert.rejects(fs.access(interrupted));
    });

    assert.equal(await fs.readFile(fixture.configPath, "utf8"), configContents);
    assert.equal(await fs.readFile(installMarker, "utf8"), "untouched\n");
  } finally {
    await fs.rm(fixtureRoot, { recursive: true, force: true });
  }
});
